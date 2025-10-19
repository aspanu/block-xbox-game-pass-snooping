<# 
  xbox-privacy-keep-gamepass.ps1
  Goal: Keep Game Pass functional but prevent Xbox/Windows from auto-discovering other launchers’ games.

  What it does (Apply):
    - Sets GamingServicesNet -> Manual, GamingServices -> Automatic (default) 
    - Stops GamingServicesNet (once)
    - Disables Game Bar discovery/presence registry flags (creates keys if missing)
    - Disables any scheduled tasks that look like Game Bar presence writers / game detection
    - (Optional) Clears Xbox app external games cache if present

  Undo:
    - Reverts services to their prior startup types
    - Re-enables previously disabled tasks
    - Restores registry from timestamped .reg backups

  Notes:
    - Run as Administrator.
    - This is conservative: Game Pass installs/updates/auth should continue working. 
    - Major Windows/Xbox updates may reflip some switches; just re-run.
#>

[CmdletBinding()]
param(
  [switch]$Undo,
  [switch]$ClearExternalGameCache
)

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Please run this script in an elevated PowerShell (Run as administrator)."
  }
}

# Paths & backup
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Base    = "$env:ProgramData\XboxPrivacyKeepGamePass"
$Backup  = Join-Path $Base "backup-$stamp"
$Latest  = Join-Path $Base "latest"

function Ensure-Dirs {
  New-Item -Force -ItemType Directory -Path $Base    | Out-Null
  New-Item -Force -ItemType Directory -Path $Backup  | Out-Null
  if (Test-Path $Latest) { Remove-Item -Recurse -Force $Latest }
  New-Item -Force -ItemType Directory -Path $Latest  | Out-Null
}

function Save-StartupType($Name, $File) {
  try {
    $svc = Get-Service -Name $Name -ErrorAction Stop
    $wmi = Get-WmiObject -Class Win32_Service -Filter "Name='$Name'"
    $startup = $wmi.StartMode  # "Auto", "Manual", "Disabled"
    $obj = @{ Name=$Name; Startup=$startup }
    $obj | ConvertTo-Json | Set-Content -Encoding UTF8 -Path $File
  } catch {
    # service might not exist on all builds
  }
}

function Restore-StartupType($File) {
  if (!(Test-Path $File)) { return }
  $obj = Get-Content $File | ConvertFrom-Json
  if ($null -eq $obj) { return }
  $target = switch ($obj.Startup.ToLower()) {
    "auto"     { "Automatic" }
    "automatic"{ "Automatic" }
    "manual"   { "Manual" }
    "disabled" { "Disabled" }
    default    { "Manual" }
  }
  try {
    Set-Service -Name $obj.Name -StartupType $target -ErrorAction SilentlyContinue
  } catch {}
}

function Export-Reg($HivePath, $OutPath) {
  try {
    reg.exe export $HivePath $OutPath /y | Out-Null
  } catch {
    # key may not exist yet
  }
}

function Import-Reg-IfExists($RegFile) {
  if (Test-Path $RegFile) {
    try { reg.exe import $RegFile | Out-Null } catch {}
  }
}

function Set-RegistryKnobs {
  # Discovery/presence flags commonly honored by Game Bar / Xbox components.
  # Creating if absent is safe; they’re ignored by components that don’t read them.
  $keys = @(
    "HKCU:\Software\Microsoft\GameBar",
    "HKLM:\SOFTWARE\Microsoft\GameBar"
  )
  foreach ($k in $keys) {
    New-Item -Path $k -Force | Out-Null

    New-ItemProperty -Path $k -Name "AllowAutoGameListDiscovery" -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $k -Name "AutoGameListEnabled"       -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $k -Name "EnableGameBarPresence"     -Value 0 -PropertyType DWord -Force | Out-Null
  }
}

function Disable-DiscoveryTasks {
  # Broad pattern match to catch variations across builds
  $patterns = @(
    "*GameBar*",
    "*Presence*",
    "*GameDetect*",
    "*GameSave*"  # presence writer sometimes lives here
  )

  $disabled = @()
  foreach ($p in $patterns) {
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
      $_.TaskName -like $p -or $_.TaskPath -like "\Microsoft\*$p*"
    }
    foreach ($t in $tasks) {
      try {
        if ($t.State -ne 'Disabled') {
          Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null
          $disabled += [PSCustomObject]@{ Name=$t.TaskName; Path=$t.TaskPath }
        }
      } catch {}
    }
  }
  # Save list for undo
  if ($disabled.Count -gt 0) {
    $disabled | ConvertTo-Json | Set-Content -Encoding UTF8 -Path (Join-Path $Latest "disabled-tasks.json")
    $disabled | ConvertTo-Json | Set-Content -Encoding UTF8 -Path (Join-Path $Backup "disabled-tasks.json")
  }
}

function Enable-PreviouslyDisabledTasks {
  $file = Get-ChildItem $Base -Filter "disabled-tasks.json" -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $file) { return }
  $list = Get-Content $file.FullName | ConvertFrom-Json
  foreach ($t in $list) {
    try {
      Enable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction SilentlyContinue | Out-Null
    } catch {}
  }
}

function Clear-ExternalGameCache {
  # Best-effort cleanup of any cached “external/other” games the Xbox app already indexed.
  $pkgRoot = Join-Path $env:LOCALAPPDATA "Packages"
  $guess = Join-Path $pkgRoot "Microsoft.GamingApp_8wekyb3d8bbwe"
  if (Test-Path $guess) {
    $state = Join-Path $guess "LocalState"
    # Common cache/db filenames vary by build. We remove obvious candidates if they exist.
    $candidates = @(
      "externalgames.json","externalgames.db","gamecatalog.db","gamecatalog.sqlite",
      "ExternalCatalog","Catalog","Cache","Db"
    )
    $deleted = 0
    foreach ($c in $candidates) {
      Get-ChildItem -Path $state -Filter $c -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue; $deleted++ } catch {}
      }
    }
    if ($deleted -gt 0) {
      Write-Host "Cleared $deleted cached catalog file(s) from Xbox app LocalState."
    }
  }
}

try {
  Assert-Admin

  if ($Undo) {
    Write-Host "== Undo: restoring previous settings =="

    # Services
    Restore-StartupType (Join-Path $Base "GamingServices.json")
    Restore-StartupType (Join-Path $Base "GamingServicesNet.json")

    # Re-enable tasks
    Enable-PreviouslyDisabledTasks

    # Restore registry (from most recent full backup if present)
    $lastBackup = Get-ChildItem $Base -Directory -Filter "backup-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($lastBackup) {
      Import-Reg-IfExists (Join-Path $lastBackup "HKCU_GameBar.reg")
      Import-Reg-IfExists (Join-Path $lastBackup "HKLM_GameBar.reg")
    }

    Write-Host "Undo complete. You may need to sign out/in or reboot for all effects."
    return
  }

  Write-Host "== Apply: Xbox privacy while keeping Game Pass =="

  Ensure-Dirs

  # Backup current service startup types
  Save-StartupType "GamingServices"     (Join-Path $Backup "GamingServices.json")
  Save-StartupType "GamingServicesNet"  (Join-Path $Backup "GamingServicesNet.json")
  Copy-Item (Join-Path $Backup "GamingServices.json")    (Join-Path $Latest "GamingServices.json") -Force -ErrorAction SilentlyContinue
  Copy-Item (Join-Path $Backup "GamingServicesNet.json") (Join-Path $Latest "GamingServicesNet.json") -Force -ErrorAction SilentlyContinue

  # Export registry before changes
  Export-Reg "HKCU\Software\Microsoft\GameBar" (Join-Path $Backup "HKCU_GameBar.reg")
  Export-Reg "HKLM\SOFTWARE\Microsoft\GameBar" (Join-Path $Backup "HKLM_GameBar.reg")
  Copy-Item (Join-Path $Backup "HKCU_GameBar.reg") (Join-Path $Latest "HKCU_GameBar.reg") -Force -ErrorAction SilentlyContinue
  Copy-Item (Join-Path $Backup "HKLM_GameBar.reg") (Join-Path $Latest "HKLM_GameBar.reg") -Force -ErrorAction SilentlyContinue

  # Services: keep core GamingServices Automatic, set helper Net to Manual (curbs scanning but preserves Game Pass)
  try {
    Set-Service -Name "GamingServices"    -StartupType Automatic -ErrorAction SilentlyContinue
  } catch {}
  try {
    Set-Service -Name "GamingServicesNet" -StartupType Manual    -ErrorAction SilentlyContinue
    Stop-Service -Name "GamingServicesNet" -Force -ErrorAction SilentlyContinue
  } catch {}

  # Registry knobs
  Set-RegistryKnobs

  # Scheduled tasks that watch for game presence/detection
  Disable-DiscoveryTasks

  if ($ClearExternalGameCache) {
    Clear-ExternalGameCache
  }

  Write-Host "`nAll set. Reboot (recommended) or sign out/in to ensure changes take full effect."
  Write-Host "To revert later, run this script with -Undo."
}
catch {
  Write-Error $_.Exception.Message
  exit 1
}
