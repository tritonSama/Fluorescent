#!/usr/bin/env bash
# Bash runner script for Fluorescent E2E Integration Suite
# Usage: ./test/e2e/run_e2e_tests.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUORESCENT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$FLUORESCENT_ROOT"

echo "================================================================"
echo "  Executing Fluorescent 3D Engine Unified E2E Test Suite"
echo "================================================================"

PKG_CONFIG="$FLUORESCENT_ROOT/packages/fluorescent_core/.dart_tool/package_config.json"

if [ -f "$PKG_CONFIG" ]; then
    dart --packages="$PKG_CONFIG" test/e2e/e2e_runner_test.dart
else
    dart test/e2e/e2e_runner_test.dart
fi
