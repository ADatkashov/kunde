param(
  [ValidateSet('keycloak', 'zitadel')]
  [string[]] $Provider = @('keycloak', 'zitadel')
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

foreach ($name in $Provider) {
  if ($name -eq 'keycloak') {
    $issuer = 'http://localhost:8180/realms/kunde-dev'
    $discoveryUri = "$issuer/.well-known/openid-configuration"
  } else {
    $issuer = 'http://localhost:8280'
    $discoveryUri = "$issuer/.well-known/openid-configuration"
  }

  $discovery = Invoke-RestMethod -Uri $discoveryUri -TimeoutSec 15
  if ($discovery.issuer -cne $issuer) {
    throw "$name issuer mismatch: expected $issuer, received $($discovery.issuer)"
  }
  foreach ($property in @('authorization_endpoint', 'token_endpoint', 'jwks_uri', 'end_session_endpoint')) {
    if ([string]::IsNullOrWhiteSpace($discovery.$property)) {
      throw "$name discovery is missing $property"
    }
  }
  $jwks = Invoke-RestMethod -Uri $discovery.jwks_uri -TimeoutSec 15
  if (@($jwks.keys).Count -lt 1) { throw "$name JWKS returned no keys" }
  Write-Host "$name OK issuer=$($discovery.issuer) jwks_keys=$(@($jwks.keys).Count)"
}
