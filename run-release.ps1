#!/usr/bin/env pwsh
# Run NeoStation in release mode with environment variables from .env
# Usage: .\run-release.ps1
# Or with a custom env file: .\run-release.ps1 -EnvFile .\.env.local

param(
    [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $EnvFile)) {
    Write-Error "Environment file not found: $EnvFile"
    exit 1
}

Write-Host "Loading environment from: $EnvFile" -ForegroundColor Cyan
flutter run --release --dart-define-from-file=$EnvFile @args
