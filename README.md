# ktlu-wifi-ssl-fix

If you code on the `KTLU-Internal` Wi-Fi, you've probably hit this:

```
requests.exceptions.SSLError: ... CERTIFICATE_VERIFY_FAILED ... self-signed certificate in certificate chain
```

and ended up slapping `verify=False` or `--ssl-verify=false` on everything. You don't have to. One script fixes it properly.

## What's going on

The school network runs HTTPS inspection on some sites (google.com, api.anthropic.com and others; GitHub, npm and PyPI went through untouched when I tested). For those sites, the certificate your laptop receives looks like this:

```
www.google.com
  issued by  Swisscom SecurePOP
    issued by  Sluz-CA   (the school's own root)
```

Your school laptop already trusts `Sluz-CA`. It sits in the Windows certificate store, so Edge and Chrome work fine. The trouble starts with tools that ship their own list of trusted roots and ignore Windows:

| Tool | Before | Why |
|---|---|---|
| Python `requests`, pip, httpx | fails | uses certifi's bundle |
| OpenSSL, Git Bash tools | fails | uses its own bundle |
| curl (Windows) | fails | trusts the cert but can't reach the revocation server |
| Node, Python `urllib` | works | already reads the Windows store |

## The fix

Clone the repo, or just download `fix.ps1`, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\fix.ps1
```

Then close and reopen your terminal and VS Code.

The script:

1. Looks up Sluz-CA in your Windows store by thumbprint. If it's missing, the script pulls it from the network, checks the thumbprint, and installs it for your user. Windows will pop up a confirmation dialog for that.
2. Saves it to `%USERPROFILE%\.ktlu-certs\sluz-ca.pem`, along with `ca-bundle.pem`, which holds the normal public roots plus Sluz-CA. That way regular sites keep working too.
3. Sets three user environment variables:
   - `REQUESTS_CA_BUNDLE`: Python requests and pip
   - `SSL_CERT_FILE`: OpenSSL, Python's ssl module, plenty of others
   - `NODE_EXTRA_CA_CERTS`: Node, npm

You don't need admin rights, and verification stays on for everything.

### curl

Windows curl will still complain with `CRYPT_E_NO_REVOCATION_CHECK`. The network blocks the revocation lookup, so use `--ssl-no-revoke` (not `-k`, which turns off verification entirely). To make that the default:

```powershell
powershell -ExecutionPolicy Bypass -File .\fix.ps1 -Curl
```

That adds `ssl-no-revoke` to your `~/.curlrc`.

## Check that it worked

In a new terminal:

```powershell
python -c "import requests; print(requests.get('https://www.google.com').status_code)"
```

You should see `200`.

## Undo

```powershell
powershell -ExecutionPolicy Bypass -File .\undo.ps1
```

This removes the env vars, the `.ktlu-certs` folder and the curlrc line. It leaves Sluz-CA in the Windows store, because the school puts it there anyway.

## Notes

- The certificate fingerprint (SHA-1) is `D6:B6:52:AF:8C:E8:8D:50:34:F6:DA:9D:13:59:E9:1E:E8:C1:0F:40`, valid until 2065. The script refuses any other certificate.
- The bundle copies certifi at the moment you run the script. If you hit errors on some public site months later, run `fix.ps1` again to refresh it.
- At home or on another network, nothing breaks. The bundle still contains all the normal roots.
- This is for your own school machine on the school network. It doesn't get around any filtering, it just stops your tools from rejecting the network's certificate.
