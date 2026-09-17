@echo off
rem tests/run_e2e_tests.bat
rem Automated single-command runner for Fluorite AAA Engine Phase 1 E2E Test Suite (Windows CMD).

setlocal enabledelayedexpansion
set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%.."

echo ================================================================================
echo         FLUORITE AAA ENGINE PHASE 1 — E2E TEST RUNNER (Windows Batch)
echo ================================================================================
echo.

set "FAILED=0"

echo [1/2] Executing Dart E2E Test Suite (Tiers 1-4)...
where dart >nul 2>&1
if %ERRORLEVEL% equ 0 (
    dart run tests\e2e_runner.dart
    if !ERRORLEVEL! neq 0 (
        echo [FAIL] Dart E2E Suite failed.
        set "FAILED=1"
    ) else (
        echo [PASS] Dart E2E Suite passed successfully.
    )
) else (
    echo Dart SDK not found on PATH. Skipping.
)

echo.
echo [2/2] Executing Rust Native E2E Test Suite (Cargo)...
where cargo >nul 2>&1
if %ERRORLEVEL% equ 0 (
    cargo test --manifest-path tests\Cargo.toml
    if !ERRORLEVEL! neq 0 (
        echo [FAIL] Cargo E2E Suite failed.
        set "FAILED=1"
    ) else (
        echo [PASS] Cargo E2E Suite passed successfully.
    )
) else (
    echo Cargo not found on PATH. Skipping.
)

echo.
echo ================================================================================
if %FAILED% equ 0 (
    echo OVERALL RESULT: ALL TEST SUITES PASSED (100%%)
    echo ================================================================================
    exit /b 0
) else (
    echo OVERALL RESULT: TEST FAILURES DETECTED
    echo ================================================================================
    exit /b 1
)
