$ErrorActionPreference = "Stop"

$ykit = Join-Path (Split-Path $PSScriptRoot) "ykit"
if (-not (Test-Path "$ykit\wpf\Desk.xaml")) {
    throw "ykit not found at $ykit - clone ykit beside this repo"
}
# The .svg is the mark and the .ico is generated from it, so the two cannot drift apart
# again. Skipped when no rasteriser is installed - the generated .ico is committed.
# A Windows without Python still has a python.exe on PATH: the Store's install stub under
# WindowsApps, which prints "Python was not found" and exits 1. Get-Command finds it, so the
# skip below has to look at where it resolves to, not whether it resolved.
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python -and $python.Source -like "*\WindowsApps\*") { $python = $null }
if ($python) {
    & $python.Source "$ykit\tools\make-icons.py" "$PSScriptRoot\Snappy.svg" --if-needed
}
if (-not (Test-Path "$PSScriptRoot\Snappy.ico")) { throw "$PSScriptRoot\Snappy.ico missing" }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw "dotnet SDK not found" }

$stage = Join-Path $env:LOCALAPPDATA "Y-Family-build\snappy\publish"
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }

& dotnet publish "$PSScriptRoot\Snappy.csproj" -c Release -o $stage --nologo
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

$exe = Join-Path $stage "Snappy.exe"
if (-not (Test-Path $exe)) { throw "dotnet publish produced no Snappy.exe in $stage" }

# Staged into the repo only so Install-App can pick it up beside profiles.ini;
# install.ps1 deletes it again on the way out. Nothing built may stay in a
# Syncthing-shared repo.
Copy-Item -LiteralPath $exe -Destination "$PSScriptRoot\Snappy.exe" -Force
"Built $PSScriptRoot\Snappy.exe ({0:N1} MB)" -f ((Get-Item "$PSScriptRoot\Snappy.exe").Length / 1MB)
