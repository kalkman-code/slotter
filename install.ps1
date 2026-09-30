$ErrorActionPreference = "Stop"
trap { Write-Host $_; Read-Host 'Press Enter to close'; break }

& "$PSScriptRoot\build.ps1"

$ykit = Join-Path (Split-Path $PSScriptRoot) "ykit"
if (-not (Test-Path "$ykit\BuildKit.ps1")) {
    throw "ykit not found at $ykit - clone ykit beside this repo"
}
. "$ykit\BuildKit.ps1"

# The running copy holds Snappy.exe open, so it has to go before the file can be
# replaced. Snappy runs elevated (it self-elevates on launch to snap admin windows),
# so stopping it from a non-elevated install session can fail — that is reported
# rather than treated as fatal, since the copy step below will fail loudly of its
# own accord if the file is still locked.
$running = Get-Process -Name Snappy -ErrorAction SilentlyContinue
# Installing is not a reason to put a window on screen (Toby, 16-09-2026):
# the app is started again only if it was already running.
$wasRunning = [bool]$running
if ($running) {
    try {
        $running | Stop-Process -ErrorAction Stop
        $running | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    } catch {
        "Could not stop the running Snappy (it is elevated) - close it by hand from the tray if the install fails below."
    }
}

$result = Install-App "$PSScriptRoot\Snappy.exe" @("profiles.ini")

# Nothing built may stay in the repo: the hub is a Syncthing share, and a versioned
# copy of Snappy.exe in .stversions is what a startup shortcut could end up pointing at.
Remove-Item -LiteralPath "$PSScriptRoot\Snappy.exe" -Force -ErrorAction SilentlyContinue

"Installed $($result.Path)"
if ($result.Pin -eq "unsupported") {
    "Windows 11 has no Pin to taskbar verb, so nothing can pin it for you - drag it there once."
} elseif ($result.Pin -ne "pinned") {
    "Taskbar pin failed - pin it by hand."
}

# Autostart is never written by the installer. Snappy asks for it in its own tray
# menu, and a reinstall must not re-add one Toby has turned off.
if ($wasRunning) {
    Start-Process -FilePath $result.Path
    Write-Host 'Started Snappy. Approve the UAC prompt - Snappy needs to run elevated to snap admin windows.'
} else { Write-Host 'Installed Snappy. Not started - it was not running.' }
Read-Host 'Press Enter to close'
