@echo off
rem Batch runner script for Fluorescent E2E Integration Suite
rem Usage: test\e2e\run_e2e_tests.bat

set SCRIPT_DIR=%~dp0
cd /d "%SCRIPT_DIR%..\.."

set PKG_CONFIG=packages\fluorescent_core\.dart_tool\package_config.json

if exist "%PKG_CONFIG%" (
    dart --packages="%PKG_CONFIG%" test\e2e\e2e_runner_test.dart
) else (
    dart test\e2e\e2e_runner_test.dart
)
