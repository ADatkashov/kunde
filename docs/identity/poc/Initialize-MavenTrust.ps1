# Dot-source this script so MAVEN_OPTS applies to Maven launched by the current shell:
# . .\docs\identity\poc\Initialize-MavenTrust.ps1
$ErrorActionPreference = 'Stop'

$hostName = 'repo.maven.apache.org'
$javaHome = $env:JAVA_HOME
if ([string]::IsNullOrWhiteSpace($javaHome) -or -not (Test-Path (Join-Path $javaHome 'bin\keytool.exe'))) {
  throw 'Set JAVA_HOME to the Java 21 runtime used by Maven.'
}
$pocLocal = Join-Path $PSScriptRoot '.local'
New-Item -ItemType Directory -Path $pocLocal -Force | Out-Null
$truststore = Join-Path $pocLocal 'maven-central-windows-root.p12'
$rootDer = Join-Path $pocLocal '.maven-central-windows-root.cer'

# Let Windows perform normal TLS chain and hostname validation. Never accept an
# untrusted certificate through a permissive validation callback.
$client = [System.Net.Sockets.TcpClient]::new($hostName, 443)
$ssl = $null
try {
  $ssl = [System.Net.Security.SslStream]::new($client.GetStream(), $false)
  $ssl.AuthenticateAsClient($hostName)
  $leaf = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)
  $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
  if (-not $chain.Build($leaf) -or $chain.ChainStatus.Count -gt 0) {
    throw "Windows did not validate the TLS chain for $hostName. No certificate was imported."
  }
  $rootThumbprint = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate.Thumbprint
  $trustedRoot = Get-ChildItem Cert:\CurrentUser\Root, Cert:\LocalMachine\Root |
    Where-Object { $_.Thumbprint -eq $rootThumbprint } | Select-Object -First 1
  if ($null -eq $trustedRoot) {
    throw 'The validated chain root is not present in a Windows Trusted Root store. No certificate was imported.'
  }

  # Import only the exact root already trusted by Windows after successful TLS
  # hostname and chain validation. The local store contains no private keys.
  [System.IO.File]::WriteAllBytes($rootDer, $trustedRoot.RawData)
  if (Test-Path $truststore) { Remove-Item -LiteralPath $truststore -Force }
  $random = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
  $storePassword = [Convert]::ToBase64String($random)
  $alias = "windows-root-$rootThumbprint"
  & (Join-Path $javaHome 'bin\keytool.exe') -importcert -noprompt -alias $alias `
    -file $rootDer -keystore $truststore -storetype PKCS12 -storepass $storePassword
  if ($LASTEXITCODE -ne 0) { throw 'keytool failed to create the local Maven truststore.' }
  Remove-Item -LiteralPath $rootDer -Force

  & (Join-Path $javaHome 'bin\keytool.exe') -list -alias $alias -keystore $truststore -storetype PKCS12 -storepass $storePassword *> $null
  if ($LASTEXITCODE -ne 0) {
    throw 'The generated truststore did not contain the Windows-validated root.'
  }
  $env:MAVEN_OPTS = "-Djavax.net.ssl.trustStore=`"$truststore`" -Djavax.net.ssl.trustStoreType=PKCS12 -Djavax.net.ssl.trustStorePassword=$storePassword"
  Write-Host "Maven TLS trust configured from Windows-validated root: $($trustedRoot.Subject) [$rootThumbprint]"
  Write-Host 'Certificate verification and hostname verification remain enabled. No private key was imported.'
} finally {
  if ($ssl) { $ssl.Dispose() }
  $client.Dispose()
  if (Test-Path $rootDer) { Remove-Item -LiteralPath $rootDer -Force }
}
