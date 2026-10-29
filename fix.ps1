# Makes Python, Node, OpenSSL and curl trust the Sluz-CA certificate that
# KTLU-Internal uses to inspect HTTPS traffic. Run it once, then open a new terminal.
#
#   powershell -ExecutionPolicy Bypass -File .\fix.ps1 [-Curl]

param(
    # Also add "ssl-no-revoke" to ~/.curlrc (Windows curl can't reach the CRL on this network)
    [switch]$Curl
)

$ErrorActionPreference = 'Stop'

# SHA-1 thumbprint of CN=Sluz-CA, DC=sluz, DC=ch (valid until 2065)
$Thumbprint = 'D6B652AF8CE88D5034F6DA9D1359E91EE8C10F40'
$OutDir     = Join-Path $HOME '.ktlu-certs'
$CaPem      = Join-Path $OutDir 'sluz-ca.pem'
$BundlePem  = Join-Path $OutDir 'ca-bundle.pem'

function ConvertTo-Pem($cert) {
    $b64 = [Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks')
    "-----BEGIN CERTIFICATE-----`n$b64`n-----END CERTIFICATE-----`n"
}

# 1. Find Sluz-CA in the Windows store, or grab it off the wire and install it
$ca = Get-ChildItem Cert:\CurrentUser\Root, Cert:\LocalMachine\Root |
      Where-Object Thumbprint -eq $Thumbprint | Select-Object -First 1

if (-not $ca) {
    Write-Host 'Sluz-CA is not in your certificate store. Fetching it from the network...'
    $script:chainCerts = @()
    $tcp = New-Object Net.Sockets.TcpClient('www.google.com', 443)
    $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, {
        param($s, $c, $chain, $e)
        $script:chainCerts = @($chain.ChainElements | ForEach-Object { $_.Certificate })
        $true
    })
    try { $ssl.AuthenticateAsClient('www.google.com') } finally { $ssl.Dispose(); $tcp.Close() }

    $ca = $script:chainCerts | Where-Object Thumbprint -eq $Thumbprint | Select-Object -First 1
    if (-not $ca) {
        throw "Didn't find Sluz-CA in the TLS chain. Are you connected to KTLU-Internal?"
    }

    # Windows will show a confirmation dialog here. Check the thumbprint matches and click Yes.
    $store = New-Object Security.Cryptography.X509Certificates.X509Store('Root', 'CurrentUser')
    $store.Open('ReadWrite'); $store.Add($ca); $store.Close()
    Write-Host 'Installed Sluz-CA into your user root store.'
} else {
    Write-Host "Found Sluz-CA in $($ca.PSParentPath.Split(':')[-1])"
}

# 2. Write the cert and a full bundle (public roots + Sluz-CA)
New-Item -ItemType Directory -Force $OutDir | Out-Null
$caText = ConvertTo-Pem $ca
[IO.File]::WriteAllText($CaPem, $caText)

$certifi = $null
if (Get-Command python -ErrorAction SilentlyContinue) {
    $certifi = python -c "import certifi; print(certifi.where())" 2>$null
}
if ($certifi -and (Test-Path $certifi)) {
    Write-Host "Using public roots from certifi ($certifi)"
    $roots = [IO.File]::ReadAllText($certifi)
} else {
    Write-Host 'certifi not found, using the Windows root store instead'
    $roots = (Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root |
              Sort-Object Thumbprint -Unique | ForEach-Object { ConvertTo-Pem $_ }) -join ''
}
[IO.File]::WriteAllText($BundlePem, $roots.TrimEnd() + "`n" + $caText)

# 3. Point the tools at it (user-level env vars, survive reboots)
[Environment]::SetEnvironmentVariable('REQUESTS_CA_BUNDLE',  $BundlePem, 'User')
[Environment]::SetEnvironmentVariable('SSL_CERT_FILE',       $BundlePem, 'User')
[Environment]::SetEnvironmentVariable('NODE_EXTRA_CA_CERTS', $CaPem,     'User')

if ($Curl) {
    $curlrc = Join-Path $HOME '.curlrc'
    if (-not ((Test-Path $curlrc) -and (Select-String -Quiet -Pattern '^\s*ssl-no-revoke' $curlrc))) {
        Add-Content $curlrc 'ssl-no-revoke'
        Write-Host "Added ssl-no-revoke to $curlrc"
    }
}

Write-Host ''
Write-Host "Done. Files are in $OutDir"
Write-Host 'Open a new terminal (or restart VS Code) so the env vars kick in.'
