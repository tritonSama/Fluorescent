# PowerShell runner script for Fluorescent E2E Integration Suite
# Usage: .\test\e2e\run_e2e_tests.ps1

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Executing Fluorescent 3D Engine Unified E2E Test Suite" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$fluorescentRoot = Resolve-Path "$scriptDir\..\.."

Push-Location $fluorescentRoot
try {
    # Check if package config exists in fluorescent_core for package resolution
    $pkgConfig = "$fluorescentRoot\packages\fluorescent_core\.dart_tool\package_config.json"
    if (Test-Path $pkgConfig) {
        dart --packages="$pkgConfig" test/e2e/e2e_runner_test.dart
    } else {
        dart test/e2e/e2e_runner_test.dart
    }
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        Write-Host "E2E Tests Failed with exit code $exit" -ForegroundColor Red
        exit $exit
    }
    Write-Host "E2E Tests Passed Successfully!" -ForegroundColor Green
} finally {
    Pop-Location
}
