# Run frontend in dev using .env BACKEND_URL if present
# Usage: .\run_dev.ps1
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $scriptDir '.env'

# Load .env entries into process env vars (skip comments/empty lines)
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if (-not [string]::IsNullOrWhiteSpace($line) -and -not $line.StartsWith('#')) {
                if ($line -match '^(?<k>[^=]+)=(?<v>.*)$') {
                    $k = $matches['k'].Trim()
                    $v = $matches['v'].Trim()
                    # Remove surrounding quotes if present
                    if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1,$v.Length-2) }
                    # Use dynamic env var assignment safely
                    ${env:$k} = $v
                }
        }
    }
}

$backend = $env:BACKEND_URL
if (-not $backend) { $backend = 'http://127.0.0.1:8000' }

Write-Host "Using BACKEND_URL = $backend"

# Ensure deps and generated code
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs

# Run Flutter with dart-define to inject BACKEND_URL
flutter run --dart-define="BACKEND_URL=$backend"
