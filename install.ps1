$ErrorActionPreference = "Stop"
trap { Write-Host $_; Read-Host 'Press Enter to close'; break }

& "$PSScriptRoot\build.ps1"

$dest = Join-Path $env:LOCALAPPDATA "Slotter"
$programs = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
# Slotter was called Snappy before 1.0; its install is retired below.
$oldDir = Join-Path $env:LOCALAPPDATA "Snappy"

# The running copy holds Slotter.exe open, so it has to go before the file can be
# replaced. Slotter runs elevated (it self-elevates on launch to snap admin windows),
# so stopping it from a non-elevated install session can fail. That is reported
# rather than treated as fatal: the copy below fails loudly if the file is still locked.
$running = @(Get-Process -Name Slotter, Snappy -ErrorAction SilentlyContinue)
# Installing is not a reason to put a window on screen: the app is started again
# only if it (or Snappy) was already running.
$wasRunning = $running.Count -gt 0
foreach ($p in $running) {
    try {
        $p | Stop-Process -ErrorAction Stop
        $p | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    } catch {
        "Could not stop the running $($p.ProcessName) (it is elevated) - quit it from the tray if the install fails below."
    }
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -LiteralPath "$PSScriptRoot\Slotter.exe" -Destination "$dest\Slotter.exe" -Force
Copy-Item -LiteralPath "$PSScriptRoot\Slotter.ico" -Destination "$dest\Slotter.ico" -Force
# Nothing built may stay in the repo.
Remove-Item -LiteralPath "$PSScriptRoot\Slotter.exe" -Force -ErrorAction SilentlyContinue

# The installed profiles.ini is the live config, so it is never overwritten. A first
# install carries Snappy's over; with neither, Slotter writes an example on first run.
$ini = Join-Path $dest "profiles.ini"
if (-not (Test-Path -LiteralPath $ini) -and (Test-Path -LiteralPath "$oldDir\profiles.ini")) {
    Copy-Item -LiteralPath "$oldDir\profiles.ini" -Destination $ini
    "Carried workspaces over from $oldDir\profiles.ini"
}

$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut("$programs\Slotter.lnk")
$link.TargetPath = "$dest\Slotter.exe"
$link.WorkingDirectory = $dest
$link.IconLocation = "$dest\Slotter.ico,0"
$link.Save()
Remove-Item -LiteralPath "$([Environment]::GetFolderPath('Desktop'))\Slotter.lnk" -Force -ErrorAction SilentlyContinue

# Retire Snappy: its Start Menu entry, desktop shortcut and install folder. Its logon
# task needs elevation to delete, so Slotter removes it the first time it runs.
Remove-Item -LiteralPath "$programs\Snappy.lnk" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath "$([Environment]::GetFolderPath('Desktop'))\Snappy.lnk" -Force -ErrorAction SilentlyContinue
if ((Test-Path -LiteralPath $oldDir) -and (Test-Path -LiteralPath $ini)) {
    Remove-Item -LiteralPath $oldDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $oldDir) { "Could not remove $oldDir - delete it once Snappy has exited." }
    else { "Removed the old Snappy install" }
}

"Installed $dest\Slotter.exe"
# Autostart is never written by the installer: Slotter's own "Start with Windows"
# setting is the only thing that adds or removes it.
if ($wasRunning -and -not $env:INSTALL_NO_LAUNCH) {
    Start-Process -FilePath "$dest\Slotter.exe"
    Write-Host 'Started Slotter. Approve the UAC prompt - Slotter runs elevated to snap admin windows.'
} else { Write-Host 'Installed Slotter. Not started - it was not running.' }
Read-Host 'Press Enter to close'
