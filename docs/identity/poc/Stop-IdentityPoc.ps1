param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('keycloak', 'zitadel')]
    [string]$Provider,
    [switch]$RemoveLocalData
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$providerDir = Join-Path $PSScriptRoot $Provider
Push-Location $providerDir
try {
    $args = @('--env-file', '.env', '-f', 'compose.yaml', 'down')
    if ($RemoveLocalData) { $args += @('--volumes', '--remove-orphans') }
    & docker compose @args
    if ($RemoveLocalData) {
        Remove-Item -LiteralPath (Join-Path $providerDir '.env') -Force -ErrorAction SilentlyContinue
    }
} finally {
    Pop-Location
}
