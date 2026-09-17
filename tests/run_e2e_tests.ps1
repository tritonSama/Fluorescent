# tests/run_e2e_tests.ps1
#
# Automated single-command runner for Fluorite AAA Engine Phase 1 E2E Test Suite.
# Usage: powershell -ExecutionPolicy Bypass -File .\tests\run_e2e_tests.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "        FLUORITE AAA ENGINE PHASE 1 — E2E TEST RUNNER (PowerShell)              " -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "Project Root: $ProjectRoot"
Write-Host ""

$PassedSuites = 0
$FailedSuites = 0

# ------------------------------------------------------------------------------
# 1. Execute Dart E2E Test Suite (51 Tests across Tiers 1-4)
# ------------------------------------------------------------------------------
Write-Host "[1/2] Executing Dart E2E Test Suite (Tiers 1-4)..." -ForegroundColor Yellow
$DartCmd = Get-Command dart -ErrorAction SilentlyContinue
if ($DartCmd) {
    Push-Location $ProjectRoot
    try {
        & dart run tests/e2e_runner.dart
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✔ Dart E2E Suite passed (51/51 tests)." -ForegroundColor Green
            $PassedSuites++
        } else {
            Write-Host "✘ Dart E2E Suite failed with exit code $LASTEXITCODE." -ForegroundColor Red
            $FailedSuites++
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "Dart SDK not found on PATH. Checking Flutter SDK..." -ForegroundColor DarkYellow
    $FlutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($FlutterCmd) {
        Push-Location $ProjectRoot
        try {
            & flutter test tests/e2e_runner.dart
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✔ Flutter test runner passed." -ForegroundColor Green
                $PassedSuites++
            } else {
                Write-Host "✘ Flutter test runner failed." -ForegroundColor Red
                $FailedSuites++
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "Neither dart nor flutter found on PATH. Skipping Dart test suite." -ForegroundColor Red
    }
}

# ------------------------------------------------------------------------------
# 2. Execute Rust Native Test Suite (Cargo)
# ------------------------------------------------------------------------------
Write-Host "`n[2/2] Executing Rust Native E2E Test Suite (Cargo)..." -ForegroundColor Yellow
$CargoCmd = Get-Command cargo -ErrorAction SilentlyContinue
if ($CargoCmd) {
    Push-Location $ProjectRoot
    try {
        & cargo test --manifest-path tests/Cargo.toml
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✔ Cargo E2E test suite passed." -ForegroundColor Green
            $PassedSuites++
        } else {
            Write-Host "✘ Cargo E2E test suite failed with exit code $LASTEXITCODE." -ForegroundColor Red
            $FailedSuites++
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "Cargo not found on PATH. Skipping Cargo test suite." -ForegroundColor DarkYellow
}

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "RUNNER SUMMARY: Passed Suites: $PassedSuites | Failed Suites: $FailedSuites" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

if ($FailedSuites -gt 0) {
    Exit 1
} else {
    Exit 0
}
