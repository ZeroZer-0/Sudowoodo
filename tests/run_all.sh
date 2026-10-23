#!/bin/bash
# run_all.sh — Run all Sudowoodo test suites
# Usage:
#   ./run_all.sh              # run everything
#   ./run_all.sh file_ops     # run just test_file_ops.sh
#   ./run_all.sh edge sudo    # run edge cases and sudo tests
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SUITES=(
    "file_ops:test_file_ops.sh"
    "sudo:test_sudo.sh"
    "cred:test_cred_wrappers.sh"
    "monitoring:test_monitoring.sh"
    "edge:test_edge_cases.sh"
    "deploy:test_deploy.sh"
)

if [ $# -gt 0 ]; then
    # Run only specified suites
    SELECTED=("$@")
else
    SELECTED=()
    for s in "${SUITES[@]}"; do
        SELECTED+=("${s%%:*}")
    done
fi

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
SUITE_RESULTS=()

for sel in "${SELECTED[@]}"; do
    FOUND=false
    for s in "${SUITES[@]}"; do
        NAME="${s%%:*}"
        FILE="${s##*:}"
        if [ "$sel" = "$NAME" ]; then
            FOUND=true
            echo ""
            echo "╔══════════════════════════════════════════╗"
            echo "║  Suite: $NAME"
            echo "╚══════════════════════════════════════════╝"
            echo ""

            if bash "$SCRIPT_DIR/$FILE"; then
                SUITE_RESULTS+=("${NAME}: PASSED")
            else
                SUITE_RESULTS+=("${NAME}: HAD FAILURES")
            fi
            break
        fi
    done
    if ! $FOUND; then
        echo "Unknown suite: $sel"
        echo "Available: ${SUITES[*]%%:*}"
        exit 1
    fi
done

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           ALL SUITES COMPLETE            ║"
echo "╠══════════════════════════════════════════╣"
for r in "${SUITE_RESULTS[@]}"; do
    printf "║  %-38s ║\n" "$r"
done
echo "╚══════════════════════════════════════════╝"
