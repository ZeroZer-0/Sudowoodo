#!/bin/bash
# test_sudo.sh — exercise sudo wrapper with patterns real scripts use
# Non-destructive: reads, temp files, and no-op commands only.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

echo "=== sudo wrapper tests ==="
echo "  TESTDIR: $TESTDIR"
echo "  NOTE: These tests require a user with sudo access."
echo "        Some may prompt for a password — that's expected and tests the wrapper."
echo ""

# ---- Basic invocations ----
echo "--- Standard patterns ---"
assert_ok "sudo: basic command" sudo id
assert_ok "sudo: whoami" sudo whoami
assert_output "sudo: output preserved" "root" sudo whoami
assert_ok "sudo: -n non-interactive (cached)" sudo -n true || true  # may fail if no cache

# ---- Flag combos ----
echo ""
echo "--- Flag combinations ---"
assert_ok "sudo: -u root" sudo -u root id
assert_ok "sudo: -u root whoami" sudo -u root whoami
assert_ok "sudo: -H preserve HOME" sudo -H id
assert_ok "sudo: -E preserve env" sudo -E id
assert_ok "sudo: -H -S (Ansible-like)" sh -c 'echo "" | sudo -H -S id' || true

# ---- Complex commands ----
echo ""
echo "--- Complex command arguments ---"
assert_ok "sudo: sh -c 'simple'" sudo sh -c 'echo hello'
assert_ok "sudo: sh -c 'pipeline'" sudo sh -c 'echo hello | cat'
assert_ok "sudo: sh -c 'semicolons'" sudo sh -c 'echo a; echo b; echo c'
assert_ok "sudo: bash -c 'subshell'" sudo bash -c 'echo $(whoami)'
assert_ok "sudo: env setting" sudo env TEST_VAR=hello env
assert_ok "sudo: command with args" sudo ls -la /tmp

# ---- Ansible-style patterns ----
echo ""
echo "--- Ansible-style invocations ---"
# Ansible become module patterns
assert_ok "ansible: -H -S -n -u root /bin/sh -c" \
    sh -c 'echo "" | sudo -H -S -n -u root /bin/sh -c "echo BECOME-SUCCESS-test"' || true
assert_ok "ansible: python discovery" \
    sudo sh -c 'which python3 || which python || echo NONE'
assert_ok "ansible: tmp file execution" \
    sudo sh -c 'echo test > /tmp/ansible_test_$$ && cat /tmp/ansible_test_$$ && rm /tmp/ansible_test_$$'

# ---- Redirect patterns ----
echo ""
echo "--- Redirect and tee patterns ---"
# sudo tee (the standard way to write to root-owned files)
assert_ok "sudo tee: write pattern" \
    sh -c 'echo "test content" | sudo tee /tmp/sudotest_$$ >/dev/null && sudo rm /tmp/sudotest_$$'
# sudo tee -a (append)
assert_ok "sudo tee -a: append pattern" \
    sh -c 'echo "line" | sudo tee -a /tmp/sudotest_$$ >/dev/null && sudo rm /tmp/sudotest_$$'

# ---- Exit code preservation ----
echo ""
echo "--- Exit code preservation ---"
assert_exit_code "sudo: exit 0 preserved" 0 sudo true
assert_exit_code "sudo: exit 1 preserved" 1 sudo false
assert_exit_code "sudo: exit 42 preserved" 42 sudo sh -c 'exit 42'

# ---- Arguments with special characters ----
echo ""
echo "--- Special character arguments ---"
assert_output "sudo: echo with quotes" 'hello "world"' \
    sudo sh -c 'echo "hello \"world\""'
assert_output "sudo: echo with backslash" 'back\slash' \
    sudo sh -c 'printf "back\\slash"'
assert_output "sudo: echo with dollar" '$HOME' \
    sudo sh -c "echo '\$HOME'"
assert_ok "sudo: echo with newlines" \
    sudo sh -c 'printf "line1\nline2\n"'

# ---- Long argument lists ----
echo ""
echo "--- Long/many arguments ---"
assert_ok "sudo: many args" sudo echo a b c d e f g h i j k l m n o p q r s t u v w x y z
LONG_ARG=$(python3 -c "print('A'*4096)")
assert_ok "sudo: 4KB argument" sudo echo "$LONG_ARG" 

# ---- Repeated rapid calls ----
echo ""
echo "--- Rapid successive calls ---"
ALL_OK=true
for i in $(seq 1 5); do
    sudo true 2>/dev/null || ALL_OK=false
done
$ALL_OK && echo -e "  ${GRN}PASS${RST}  sudo: 5 rapid calls" && ((PASS++)) \
    || { echo -e "  ${RED}FAIL${RST}  sudo: rapid calls failed"; ((FAIL++)); }

# ---- sudo with stdin ----
echo ""
echo "--- stdin handling ---"
assert_output "sudo: cat from stdin" "piped input" \
    sh -c 'echo "piped input" | sudo cat'
assert_ok "sudo: multi-line stdin" \
    sh -c 'printf "line1\nline2\nline3\n" | sudo cat'

# ---- sudo -k (invalidate cache, then re-auth) ----
echo ""
echo "--- Cache operations ---"
assert_ok "sudo -k: invalidate timestamp" sudo -k
# Next sudo will require password — just test it doesn't crash
echo -e "  ${YLW}SKIP${RST}  sudo after -k: would prompt interactively"
((SKIP++))

# ---- sudo -i / -s (interactive shells) ----
echo ""
echo "--- Shell modes ---"
assert_ok "sudo -i: login shell with command" sudo -i whoami
assert_ok "sudo -s: shell with command" sudo -s whoami

echo ""
summary
