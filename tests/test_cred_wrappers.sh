#!/bin/bash
# test_cred_wrappers.sh — test credential-capturing wrappers (su, ssh, passwd)
# NON-DESTRUCTIVE: uses --help, dry-run, nonexistent targets, and localhost.
# Some tests will prompt for passwords — that exercises the wrapper.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

echo "=== Credential wrapper tests (su, ssh, passwd) ==="
echo "  NOTE: Some tests intentionally trigger auth failures."
echo "        Error messages from su/ssh are expected."
echo ""

# ==================================================================
echo "--- su ---"
# su to self (will prompt for root password, which tests the expect block)
# We can't fully test su without knowing a password, but we can verify
# it doesn't crash on bad input

# su with -c (run command as root)
echo -e "  ${YLW}SKIP${RST}  su -c: requires root password"
((SKIP++))

# su to own user (might not prompt on some systems)
echo -e "  ${YLW}SKIP${RST}  su - \$USER: behavior varies by system"
((SKIP++))

# su --help should work
assert_ok "su: --help" su --help 2>/dev/null || true

# su with nonexistent user (should fail cleanly)
assert_fail "su: nonexistent user" su nonexistent_user_$$ -c "echo hi" </dev/null

# su with special characters in intended password (if we could test it)
echo -e "  ${YLW}SKIP${RST}  su: special char password (manual test)"
((SKIP++))

# ==================================================================
echo ""
echo "--- ssh ---"
# ssh to nonexistent host (should fail fast, not hang)
assert_fail "ssh: nonexistent host" \
    timeout 5 ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
    definitely_not_real_host_$$.example.invalid ls 2>/dev/null

# ssh localhost (if sshd is running) with command
if systemctl is-active sshd >/dev/null 2>&1 || pgrep -x sshd >/dev/null 2>&1; then
    # Non-interactive command via ssh
    assert_ok "ssh: localhost whoami" \
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes localhost whoami 2>/dev/null || true

    # ssh with -t (force tty) — common in scripts
    echo -e "  ${YLW}SKIP${RST}  ssh -t localhost: interactive, skipping"
    ((SKIP++))

    # ssh with complex command
    assert_ok "ssh: localhost sh -c" \
        ssh -o StrictHostKeyChecking=no -o BatchMode=yes \
        localhost 'echo hello && echo world' 2>/dev/null || true

    # ssh with -o options (various)
    assert_ok "ssh: multiple -o flags" \
        ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes \
        localhost true 2>/dev/null || true

    # ssh with -i key file (nonexistent key = should fail gracefully)
    assert_fail "ssh: nonexistent key file" \
        ssh -i /tmp/no_such_key_$$ -o BatchMode=yes localhost true 2>/dev/null

    # ssh with port
    assert_ok "ssh: -p port" \
        ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -o BatchMode=yes \
        -p 22 localhost true 2>/dev/null || true
else
    skip_test "ssh: localhost tests" "sshd not running"
fi

# ssh argument handling
assert_ok "ssh: --help or version" ssh -V 2>/dev/null || ssh --help 2>/dev/null || true

# ==================================================================
echo ""
echo "--- passwd ---"
# passwd --help
assert_ok "passwd: --help" passwd --help 2>/dev/null || true

# passwd --status (read-only query)
assert_ok "passwd: -S status" passwd -S 2>/dev/null || sudo passwd -S "$(whoami)" 2>/dev/null || true

# passwd for nonexistent user (should fail)
assert_fail "passwd: nonexistent user" sudo passwd nonexistent_user_$$ </dev/null 2>/dev/null

echo ""
echo "--- Credential wrapper argument patterns ---"

# ssh with user@host (common alternative to -l)
assert_fail "ssh: user@host format" \
    timeout 3 ssh -o ConnectTimeout=1 -o BatchMode=yes \
    "testuser_$$@192.0.2.1" true 2>/dev/null

# ssh with ProxyCommand (Ansible uses this)
assert_fail "ssh: -o ProxyCommand" \
    timeout 3 ssh -o ConnectTimeout=1 -o ProxyCommand="none" \
    -o BatchMode=yes localhost true 2>/dev/null

# su with -s (specify shell)
assert_fail "su: -s /bin/sh" su -s /bin/sh -c "echo test" nobody </dev/null 2>/dev/null

# su with - (login shell)
assert_fail "su: - (login shell)" su - -c "echo test" </dev/null 2>/dev/null

echo ""
summary
