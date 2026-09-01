$ErrorActionPreference = "Stop"
$log = "C:\OEM\post-install.log"
Start-Transcript -Path $log -Append

function Get-Winget {
  $command = Get-Command winget.exe -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  $bundle = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"
  Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile $bundle
  Add-AppxPackage -Path $bundle
  $command = Get-Command winget.exe -ErrorAction SilentlyContinue
  if (!$command) { throw "WinGet did not become available after App Installer installation." }
  return $command.Source
}

function Install-Package($winget, $id) {
  Write-Host "Installing $id"
  & $winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
  if ($LASTEXITCODE -ne 0) { throw "WinGet failed for $id (exit $LASTEXITCODE)." }
}

try {
  $winget = Get-Winget
  $failed = @()
  foreach ($id in "Microsoft.Sysinternals", "voidtools.Everything", "ImputNet.Helium", "PuTTY.PuTTY") {
    try { Install-Package $winget $id } catch { Write-Error $_; $failed += $id }
  }
  if ($failed.Count) { throw "Failed packages: $($failed -join ', ')" }
} finally {
  Stop-Transcript
}
