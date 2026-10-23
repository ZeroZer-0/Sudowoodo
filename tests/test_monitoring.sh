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
    assert_ok "systemctl: list-units" systemctl list-units --no-pager 2>/dev/null || true
    assert_ok "systemctl: status sshd" systemctl status sshd --no-pager 2>/dev/null || true
    assert_ok "systemctl: is-active sshd" systemctl is-active sshd 2>/dev/null || true
    assert_ok "systemctl: is-enabled sshd" systemctl is-enabled sshd 2>/dev/null || true
    assert_ok "systemctl: list-unit-files" systemctl list-unit-files --no-pager 2>/dev/null || true
    # systemctl show (machine-parseable)
    assert_ok "systemctl: show sshd" systemctl show sshd --no-pager 2>/dev/null || true
else
    skip_test "systemctl: all" "not available"
fi

# ---- iptables ----
echo ""
echo "--- iptables ---"
if command -v iptables >/dev/null 2>&1; then
    # These are read-only — -L lists, -S prints
    assert_ok "iptables: -L list" sudo iptables -L --line-numbers -n 2>/dev/null || true
    assert_ok "iptables: -S print rules" sudo iptables -S 2>/dev/null || true
    assert_ok "iptables: -L INPUT" sudo iptables -L INPUT -n 2>/dev/null || true
    assert_ok "iptables: -t nat -L" sudo iptables -t nat -L -n 2>/dev/null || true
else
    skip_test "iptables: all" "not available"
fi

# ---- iptables-save ----
echo ""
echo "--- iptables-save ---"
if command -v iptables-save >/dev/null 2>&1; then
    assert_ok "iptables-save: basic" sudo iptables-save 2>/dev/null || true
    assert_ok "iptables-save: -t filter" sudo iptables-save -t filter 2>/dev/null || true
else
    skip_test "iptables-save: all" "not available"
fi

# ---- ufw ----
echo ""
echo "--- ufw ---"
if command -v ufw >/dev/null 2>&1; then
    assert_ok "ufw: status" sudo ufw status 2>/dev/null || true
    assert_ok "ufw: status verbose" sudo ufw status verbose 2>/dev/null || true
    assert_ok "ufw: status numbered" sudo ufw status numbered 2>/dev/null || true
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
