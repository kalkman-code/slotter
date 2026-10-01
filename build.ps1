$ErrorActionPreference = "Stop"

# The .svg is the mark and the .ico is generated from it, so the two cannot drift apart
# again. Skipped when no rasteriser is installed - the generated .ico is committed.
# A Windows without Python still has a python.exe on PATH: the Store's install stub under
# WindowsApps, which prints "Python was not found" and exits 1. Get-Command finds it, so the
# skip below has to look at where it resolves to, not whether it resolved.
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python -and $python.Source -like "*\WindowsApps\*") { $python = $null }
if ($python) {
    & $python.Source "$PSScriptRoot\tools\make-icons.py" "$PSScriptRoot\Slotter.svg" --if-needed
}
if (-not (Test-Path "$PSScriptRoot\Slotter.ico")) { throw "$PSScriptRoot\Slotter.ico missing" }
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw "dotnet SDK not found" }

$stage = Join-Path $env:LOCALAPPDATA "Slotter-build\publish"
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }

& dotnet publish "$PSScriptRoot\Slotter.csproj" -c Release -o $stage --nologo
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

$exe = Join-Path $stage "Slotter.exe"
if (-not (Test-Path $exe)) { throw "dotnet publish produced no Slotter.exe in $stage" }

# Staged into the repo only so Install-App can pick it up beside profiles.ini;
# install.ps1 deletes it again on the way out. Nothing built may stay in a
# Syncthing-shared repo.
Copy-Item -LiteralPath $exe -Destination "$PSScriptRoot\Slotter.exe" -Force
"Built $PSScriptRoot\Slotter.exe ({0:N1} MB)" -f ((Get-Item "$PSScriptRoot\Slotter.exe").Length / 1MB)
