param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('keycloak', 'zitadel')]
    [string]$Provider
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$providerDir = Join-Path $PSScriptRoot $Provider
$envPath = Join-Path $providerDir '.env'

function New-RandomSecret([int]$Length) {
    $alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes($Length)
    $chars = foreach ($byte in $bytes) { $alphabet[[int]$byte % $alphabet.Length] }
    return -join $chars
}

if (-not (Test-Path -LiteralPath $envPath)) {
    if ($Provider -eq 'keycloak') {
        $lines = @(
            'KC_BOOTSTRAP_ADMIN_USERNAME=kunde-local-admin',
            "KC_BOOTSTRAP_ADMIN_PASSWORD=$(New-RandomSecret 28)",
            "KC_DB_PASSWORD=$(New-RandomSecret 28)"
        )
    } else {
        $lines = @(
            "ZITADEL_MASTERKEY=$(New-RandomSecret 32)",
            "ZITADEL_LOGIN_COOKIE_SECRET=$(New-RandomSecret 48)",
            "ZITADEL_DB_PASSWORD=$(New-RandomSecret 28)",
            'ZITADEL_ADMIN_USERNAME=kunde-local-admin',
            'ZITADEL_ADMIN_LOGIN=kunde-local-admin@localhost',
            "ZITADEL_ADMIN_PASSWORD=$(New-RandomSecret 27)!"
        )
    }
    Set-Content -LiteralPath $envPath -Value $lines -Encoding ascii
}

Push-Location $providerDir
try {
    $startupClock = [System.Diagnostics.Stopwatch]::StartNew()
    docker compose --env-file .env -f compose.yaml config --quiet
    docker compose --env-file .env -f compose.yaml up -d --wait --wait-timeout 300
    $startupClock.Stop()
    Write-Host "$Provider startup and health-check time: $([Math]::Round($startupClock.Elapsed.TotalSeconds, 1)) seconds."
    if ($Provider -eq 'keycloak') {
        Write-Host 'Keycloak discovery: http://localhost:8180/realms/kunde-dev/.well-known/openid-configuration'
        Write-Host 'Admin console: http://localhost:8180/admin/'
    } else {
        Write-Host 'ZITADEL discovery: http://localhost:8280/.well-known/openid-configuration'
        Write-Host 'Console: http://localhost:8280/ui/console/'
    }
    Write-Host 'Local bootstrap credentials are in this provider folder .env (ignored by git). Do not reuse them.'
} finally {
    Pop-Location
}
