# Reverts fix.ps1. Leaves Sluz-CA in the Windows store, since the school installs it anyway.

foreach ($name in 'REQUESTS_CA_BUNDLE', 'SSL_CERT_FILE', 'NODE_EXTRA_CA_CERTS') {
    [Environment]::SetEnvironmentVariable($name, $null, 'User')
}

Remove-Item -Recurse -Force (Join-Path $HOME '.ktlu-certs') -ErrorAction SilentlyContinue

$curlrc = Join-Path $HOME '.curlrc'
if (Test-Path $curlrc) {
    $rest = Get-Content $curlrc | Where-Object { $_ -notmatch '^\s*ssl-no-revoke' }
    if ($rest) { Set-Content $curlrc $rest } else { Remove-Item $curlrc }
}

Write-Host 'Removed. Open a new terminal for it to take effect.'
