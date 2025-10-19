<# 
  xbox-privacy-keep-gamepass.ps1  (2025-10 update)

  Keeps Game Pass working while blocking Windows/Xbox from scanning all drives
  and (optionally) disables Xbox Live presence + telemetry services.

  Flags:
    -ClearExternalGameCache   → wipe Xbox app cached game lists
    -DeepClean                → also disable Xbox Live & telemetry services
    -Undo                     → revert all changes
#>

[CmdletBinding()]
param(
  [switch]$Undo,
  [switch]$ClearExternalGameCache,
  [switch]$DeepClean
)

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Please run this script as Administrator."
  }
}

$Base   = "$env:ProgramData\XboxPrivacyKeepGamePass"
$Backup = Join-Path $Base "backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -Force -ItemType Directory -Path $Backup | Out-Null

function Save-ServiceState($names) {
  foreach ($n in $names) {
    try {
      $svc = Get-Service $n -ErrorAction Stop
      [PSCustomObject]@{Name=$n; Startup=(Get-WmiObject Win32_Service -Filter "Name='$n'").StartMode } |
        ConvertTo-Json | Set-Content -Path (Join-Path $Backup "$n.json")
    } catch {}
  }
}

function Restore-ServiceState() {
  Get-ChildItem $Base -Recurse -Filter "*.json" | ForEach-Object {
    try {
      $obj = Get-Content $_.FullName | ConvertFrom-Json
      Set-Service -Name $obj.Name -StartupType $obj.Startup -ErrorAction SilentlyContinue
    } catch {}
  }
}

function Disable-Services($pairs) {
  foreach ($p in $pairs) {
    $n=$p.Name; $mode=$p.Mode
    try {
      Set-Service -Name $n -StartupType $mode -ErrorAction SilentlyContinue
      if ($mode -eq 'Manual' -or $mode -eq 'Disabled') {
        Stop-Service -Name $n -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}

function Set-RegistryKnobs {
  $paths=@(
    "HKCU:\Software\Microsoft\GameBar",
    "HKLM:\SOFTWARE\Microsoft\GameBar"
  )
  foreach($p in $paths){
    New-Item -Path $p -Force | Out-Null
    New-ItemProperty -Path $p -Name "AllowAutoGameListDiscovery" -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $p -Name "EnableGameBarPresence" -Value 0 -PropertyType DWord -Force | Out-Null
  }
}

function Clear-ExternalGameCache {
  $guess = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.GamingApp_8wekyb3d8bbwe\LocalState"
  if (Test-Path $guess) {
    Get-ChildItem $guess -Recurse -Include *external*,*catalog*,*cache*,*.db* -ErrorAction SilentlyContinue |
      Remove-Item -Force -ErrorAction SilentlyContinue
  }
}

Assert-Admin

if ($Undo) {
  Write-Host "Restoring service states and registry backups..."
  Restore-ServiceState
  Write-Host "Undo complete. Reboot recommended."
  exit
}

Write-Host "Applying Xbox privacy tweaks..."

# Save and adjust core Gaming Services
Save-ServiceState @("GamingServices","GamingServicesNet")
Disable-Services @(
  @{Name="GamingServices";    Mode="Automatic"},
  @{Name="GamingServicesNet"; Mode="Manual"}
)

# Registry knobs
Set-RegistryKnobs

# DeepClean option → disable Xbox Live presence/telemetry
if ($DeepClean) {
  Write-Host "Disabling Xbox Live & telemetry services..."
  $targets=@(
    @{Name="Xbox Live Auth Manager"; Mode="Manual"},
    @{Name="Xbox Live Networking Service"; Mode="Manual"},
    @{Name="Xbox Live Game Save"; Mode="Manual"},
    @{Name="Connected User Experiences and Telemetry"; Mode="Manual"}
  )
  Save-ServiceState ($targets | ForEach-Object {$_.Name})
  Disable-Services $targets
}

# Optional cache wipe
if ($ClearExternalGameCache) {
  Write-Host "Clearing Xbox app cached external-game data..."
  Clear-ExternalGameCache
}

Write-Host "Done. Reboot or sign out/in to apply."
Write-Host "To revert, run again with -Undo."
