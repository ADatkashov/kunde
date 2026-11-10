param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('keycloak', 'zitadel')]
    [string]$Provider
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$dbDir = Join-Path $PSScriptRoot 'backend-db'
$envPath = Join-Path $dbDir '.env'
if (-not (Test-Path -LiteralPath $envPath)) {
    $alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $password = -join ($bytes | ForEach-Object { $alphabet[[int]$_ % $alphabet.Length] })
    Set-Content -LiteralPath $envPath -Value "POC_DB_PASSWORD=$password" -Encoding ascii
}

$issuer = if ($Provider -eq 'keycloak') { 'http://localhost:8180/realms/kunde-dev' } else { 'http://localhost:8280' }
$audience = if ($Provider -eq 'keycloak') {
    'kunde-api'
} else {
    Read-Host 'Enter the KUNDE POC project ID used as the ZITADEL token audience'
}

Push-Location $dbDir
try {
    docker compose --env-file .env -f compose.yaml config --quiet
    docker compose --env-file .env -f compose.yaml up -d --wait --wait-timeout 120
} finally {
    Pop-Location
}

$dbPassword = (Get-Content -LiteralPath $envPath | Where-Object { $_ -like 'POC_DB_PASSWORD=*' }) -replace '^POC_DB_PASSWORD=', ''
$env:SPRING_PROFILES_ACTIVE = 'identity-poc'
$env:POC_ALLOW_HTTP_ISSUER = 'true'
$env:OIDC_ISSUER_URI = $issuer
$env:OIDC_AUDIENCE = $audience
$env:DB_URL = 'jdbc:postgresql://localhost:5544/kunde_identity_poc'
$env:DB_USERNAME = 'kunde_poc'
$env:DB_PASSWORD = $dbPassword
Write-Host "Running KUNDE backend locally against $Provider; protected test endpoint is /api/v1/poc/whoami."
. (Join-Path $PSScriptRoot 'Initialize-MavenTrust.ps1')
Push-Location (Join-Path $PSScriptRoot '..\..\..\backend')
try {
    $maven = Join-Path $PSScriptRoot '.local\apache-maven-3.9.9\bin\mvn.cmd'
    $mavenArgs = @('--batch-mode', '--no-transfer-progress', "-Dmaven.repo.local=$(Join-Path $PSScriptRoot '.local\m2-identity-poc')", 'spring-boot:run')
    if (Test-Path -LiteralPath $maven) { & $maven @mavenArgs } else { mvn @mavenArgs }
} finally { Pop-Location }
