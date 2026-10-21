param(
    [switch]$NoSign,
    [string]$Thumbprint = $(if ($env:SLOTTER_SIGN_THUMBPRINT) { $env:SLOTTER_SIGN_THUMBPRINT } else { "EA6F2A81A84E49D31FF7965A50D7DE771601DA0A" })
)

$ErrorActionPreference = "Stop"

$version = (Get-Content -LiteralPath "$PSScriptRoot\VERSION" -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+-alpha\.\d+$') { throw "Unsupported release version: $version" }
$dist = Join-Path $PSScriptRoot "dist"
$stage = Join-Path $env:TEMP "Slotter-release-$PID"
$zip = Join-Path $dist "Slotter-$version-win-x64.zip"
$exe = Join-Path $PSScriptRoot "Slotter.exe"

try {
    & "$PSScriptRoot\build.ps1"
    if ($LASTEXITCODE -ne 0) { throw "Publish failed" }

    if (-not $NoSign) {
        $st = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"
        if (-not (Test-Path -LiteralPath $st)) { throw "SignTool was not found at $st" }
        & $st sign /sha1 $Thumbprint /tr http://time.certum.pl /td sha256 /fd sha256 $exe
        if ($LASTEXITCODE -ne 0) {
            throw "Authenticode signing failed. Check that the Certum SimplySign session is logged in and the signing certificate is available."
        }
        & $st verify /pa /tw $exe
        if ($LASTEXITCODE -ne 0) { throw "Authenticode signature verification failed for $exe" }
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $exe
    "Authenticode status: $($signature.Status)"
    "Signer thumbprint: $($signature.SignerCertificate.Thumbprint)"
    "Executable SHA-256: $((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant())"

    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item -LiteralPath $exe -Destination $stage
    Copy-Item -LiteralPath "$PSScriptRoot\LICENSE" -Destination $stage
    Copy-Item -LiteralPath "$PSScriptRoot\README.md" -Destination $stage
    @'
Slotter for Windows

Unzip this folder and run Slotter.exe. Slotter asks for administrator permission once because Windows only lets it move elevated windows, such as Task Manager or an administrator terminal.

The Windows executable is signed by Toby Kalkman using Certum open source code signing. SmartScreen may still warn on a new download until the certificate builds reputation.
'@ | Set-Content -LiteralPath (Join-Path $stage "INSTALL.txt") -Encoding utf8
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -Force
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $(Split-Path -Leaf $zip)" | Set-Content -LiteralPath "$zip.sha256" -Encoding ascii
    "Created $zip"
    Get-Content -LiteralPath "$zip.sha256"
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
}
