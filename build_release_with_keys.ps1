$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$definesPath = Join-Path $projectRoot "dart_defines.local.json"

if (-not (Test-Path $definesPath)) {
  Write-Host "Missing dart_defines.local.json" -ForegroundColor Red
  Write-Host "Copy dart_defines.example.json to dart_defines.local.json and fill in your real keys." -ForegroundColor Yellow
  exit 1
}

$json = Get-Content $definesPath -Raw | ConvertFrom-Json
$requiredKeys = @(
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
  "OPENWEATHER_API_KEY"
)

$missing = @()
foreach ($key in $requiredKeys) {
  $value = $json.$key
  if ([string]::IsNullOrWhiteSpace([string]$value) -or [string]$value -like "your-*") {
    $missing += $key
  }
}

if ($missing.Count -gt 0) {
  Write-Host "These required keys are missing or still using placeholder values:" -ForegroundColor Red
  $missing | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
  exit 1
}

Push-Location $projectRoot
try {
  flutter build apk --release --dart-define-from-file="$definesPath"
}
finally {
  Pop-Location
}
