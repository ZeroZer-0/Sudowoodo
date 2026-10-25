#!/bin/bash
# test_monitoring.sh — test monitoring/system wrappers (systemctl, ufw, iptables, ps, etc.)
# Non-destructive: read-only operations only.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

echo "=== Monitoring/system wrapper tests ==="
echo ""

# ---- ps ----
echo "--- ps ---"
assert_ok "ps: basic" ps
assert_ok "ps: aux" ps aux
assert_ok "ps: -ef" ps -ef
assert_ok "ps: -eo custom format" ps -eo pid,user,comm
assert_ok "ps: --no-headers" ps --no-headers -eo pid,comm
# ps | grep pattern (the most common use)
assert_ok "ps|grep: find bash" sh -c 'ps aux | grep bash | grep -v grep'
# ps output to variable
MYPROCS=$(ps -eo comm --no-headers | wc -l)
[ "$MYPROCS" -gt 0 ] && echo -e "  ${GRN}PASS${RST}  ps: parsed $MYPROCS processes" && ((PASS++)) \
    || { echo -e "  ${RED}FAIL${RST}  ps: no processes"; ((FAIL++)); }

# ---- systemctl ----
echo ""
echo "--- systemctl ---"
if command -v systemctl >/dev/null 2>&1; then
    assert_ok "systemctl: list-units" timeout 10 systemctl list-units --no-pager
    assert_ok "systemctl: status ssh" timeout 10 systemctl status ssh --no-pager
    assert_ok "systemctl: is-active ssh" timeout 10 systemctl is-active ssh
    assert_ok "systemctl: is-enabled ssh" timeout 10 systemctl is-enabled ssh
    assert_ok "systemctl: list-unit-files" timeout 10 systemctl list-unit-files --no-pager
    # systemctl show (machine-parseable)
    assert_ok "systemctl: show ssh" timeout 10 systemctl show ssh --no-pager
else
    skip_test "systemctl: all" "not available"
fi

# ---- iptables ----
echo ""
echo "--- iptables ---"
if command -v iptables >/dev/null 2>&1; then
    # These are read-only — -L lists, -S prints
    # NOTE: iptables -S hangs on nf_tables backend (v1.8.10) — known system bug, skip it
    assert_ok "iptables: -L list" timeout 30 sudo iptables -L --line-numbers -n
    assert_ok "iptables: -L INPUT" timeout 30 sudo iptables -L INPUT -n
    assert_ok "iptables: -t nat -L" timeout 30 sudo iptables -t nat -L -n
else
    skip_test "iptables: all" "not available"
fi

# ---- iptables-save ----
echo ""
echo "--- iptables-save ---"
if command -v iptables-save >/dev/null 2>&1; then
    assert_ok "iptables-save: basic" timeout 10 sudo iptables-save
    assert_ok "iptables-save: -t filter" timeout 10 sudo iptables-save -t filter
else
    skip_test "iptables-save: all" "not available"
fi

# ---- ufw ----
echo ""
echo "--- ufw ---"
if command -v ufw >/dev/null 2>&1; then
    assert_ok "ufw: status" timeout 10 sudo ufw status
    assert_ok "ufw: status verbose" timeout 10 sudo ufw status verbose
    assert_ok "ufw: status numbered" timeout 10 sudo ufw status numbered
else
    skip_test "ufw: all" "not available"
fi

# ---- less / more ----
echo ""
echo "--- less / more (non-interactive) ---"
# In non-interactive (piped) mode these should just cat through
echo "test content for pager" > "$TESTDIR/pager_test.txt"
assert_ok "less: file (piped stdout)" sh -c "less '$TESTDIR/pager_test.txt' | cat"
assert_ok "more: file (piped stdout)" sh -c "more '$TESTDIR/pager_test.txt' | cat"
# less with stdin
assert_ok "less: stdin pipe" sh -c "echo 'piped' | less | cat"

echo ""
summary
