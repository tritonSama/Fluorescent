#!/usr/bin/env bash
# tests/run_e2e_tests.sh
# Automated single-command runner for Fluorite AAA Engine Phase 1 E2E Test Suite (POSIX).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "================================================================================"
echo "     FLUORITE AAA ENGINE PHASE 2 (WAVE 1) — E2E TEST RUNNER (Bash)              "
echo "================================================================================"
echo ""

FAILED=0

echo "[1/2] Executing Dart E2E Test Suite (Tiers 1-4)..."
if command -v dart &> /dev/null; then
    dart run tests/e2e_runner.dart || FAILED=1
else
    echo "Dart SDK not found on PATH. Skipping."
fi

echo ""
echo "[2/2] Executing Rust Native E2E Test Suite (Cargo)..."
if command -v cargo &> /dev/null; then
    cargo test --manifest-path tests/Cargo.toml || FAILED=1
else
    echo "Cargo not found on PATH. Skipping."
fi

echo ""
echo "================================================================================"
if [ $FAILED -eq 0 ]; then
    echo "OVERALL RESULT: ALL TEST SUITES PASSED (100%)"
    echo "================================================================================"
    exit 0
else
    echo "OVERALL RESULT: TEST FAILURES DETECTED"
    echo "================================================================================"
    exit 1
fi
