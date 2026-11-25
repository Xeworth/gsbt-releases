# Install Game Save Backup Tool (GSBT) on Windows.
#
# Default = Terminal (CLI) from GSBT_CLI_*.zip — small, immersion-friendly.
#   irm https://gsbt.dev/install | iex
#
# Desktop GUI (same folder later):
#   gsbt get gui
#
# Or install a desktop flavor up front:
#   & { $env:GSBT_FLAVOR = 'gui'; irm ... | iex }   # Desktop and CLI
#   & { $env:GSBT_FLAVOR = 'full'; irm ... | iex }  # Alias for the same desktop installer
#
# Optional:
#   $env:GSBT_INSTALLER_URL / $env:GSBT_CLI_URL  — pin a specific asset URL
#   $env:GSBT_FLAVOR = cli | gui | full

$ErrorActionPreference = "Stop"

$Repo = "Xeworth/gsbt-releases"
$DefaultTag = "latest"
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA "Game Save Backup Tool"

function Get-Flavor {
  $raw = if ($env:GSBT_FLAVOR) { $env:GSBT_FLAVOR.Trim().ToLowerInvariant() } else { "cli" }
  switch ($raw) {
    { $_ -in @("cli", "terminal") } { return "cli" }
    { $_ -in @("gui", "desktop", "compact") } { return "gui" }
    { $_ -in @("full") } { return "full" }
    default {
      throw "Unknown GSBT_FLAVOR '$raw'. Use cli, gui, or full."
    }
  }
}

function Get-UserPath {
  $property = Get-ItemProperty -Path 'HKCU:\Environment' -Name Path -ErrorAction SilentlyContinue
  if ($property.PSPath) {
    return (Get-Item -LiteralPath $property.PSPath).GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  }
  return [string]$property.Path
}

function Test-UserPathEntry([string]$Current, [string]$Directory) {
  return [bool]($Current -split ';' | Where-Object { $_.Trim().Trim('"').TrimEnd('\') -ieq $Directory.TrimEnd('\') })
}

function Add-UserPath {
  param([Parameter(Mandatory)][string]$Directory)
  $envKey = "HKCU:\Environment"
  $current = Get-UserPath
  if (Test-UserPathEntry $current $Directory) {
    if (!(Test-UserPathEntry $env:PATH $Directory)) { $env:PATH = "$Directory;$env:PATH" }
    Write-Host "PATH already contains: $Directory"
    return
  }

  $newPath = if ([string]::IsNullOrWhiteSpace($current)) { $Directory } else { "$current;$Directory" }
  Set-ItemProperty -Path $envKey -Name Path -Value $newPath
  $env:PATH = "$Directory;$env:PATH"
  Write-Host "Added to user PATH: $Directory"
}

function Assert-OrdinaryInstallPath([string]$Path) {
  while ($Path) {
    $entry = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($entry -and ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      throw "The CLI installer cannot write through a linked path: $Path"
    }
    $Path = [IO.Path]::GetDirectoryName($Path)
  }
}

function Install-CliPayload([string]$Source) {
  $mutex = [Threading.Mutex]::new($false, 'Local\GSBT-StandaloneCliMaintenance')
  try {
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (!$locked) { throw 'Another CLI installation or removal is in progress.' }
    Assert-OrdinaryInstallPath $DefaultInstallDir
    if ((Test-Path -LiteralPath (Join-Path $DefaultInstallDir 'gsbt-main.exe')) -or
        (Get-ChildItem -LiteralPath $DefaultInstallDir -Filter 'unins*.dat' -File -ErrorAction SilentlyContinue)) {
      throw 'The desktop installation already includes the CLI. Use its updater to update that copy.'
    }
    $receipt = Join-Path $DefaultInstallDir '.gsbt-cli-install'
    Assert-OrdinaryInstallPath $receipt
    $prior = @()
    $header = 'GSBT CLI 1 keep-path'
    if (Test-Path -LiteralPath $receipt -PathType Leaf) {
      $old = [IO.File]::ReadAllLines($receipt)
      if ($old.Count -lt 2 -or $old[0] -cnotin 'GSBT CLI 1 keep-path','GSBT CLI 1 own-path') { throw 'Invalid existing CLI receipt.' }
      $header = $old[0]
      $prior = $old[1..($old.Count-1)]
    }
    if (!(Test-UserPathEntry (Get-UserPath) $DefaultInstallDir)) { $header = 'GSBT CLI 1 own-path' }
    $files = @(Get-ChildItem -LiteralPath $Source -Recurse -File -Force)
    $entries = foreach ($file in $files) {
      $name = $file.FullName.Substring($Source.Length + 1)
      if ($name -eq '.gsbt-cli-install' -or $name.Split([IO.Path]::DirectorySeparatorChar)[0] -eq 'gsbt') { throw "Unexpected CLI package path: $name" }
      Assert-OrdinaryInstallPath (Join-Path $DefaultInstallDir $name)
      (Get-FileHash -LiteralPath $file.FullName).Hash + '  ' + $name
    }
    [void][IO.Directory]::CreateDirectory($DefaultInstallDir)
    # Install can be interrupted after any copy. Until the next install the receipt
    # covers both old and new packaged bytes, including files retired by an update.
    $tempReceipt = Join-Path $DefaultInstallDir ('.gsbt-cli-install-' + [guid]::NewGuid().ToString('N'))
    try {
      $hashes = @($prior) + @($entries) | Sort-Object -Unique
      [IO.File]::WriteAllLines($tempReceipt, [string[]](@($header) + @($hashes)), [Text.UTF8Encoding]::new($false))
      if ([IO.File]::Exists($receipt)) { [IO.File]::Replace($tempReceipt, $receipt, [System.Management.Automation.Language.NullString]::Value) }
      else { [IO.File]::Move($tempReceipt, $receipt) }
    } finally { if ([IO.File]::Exists($tempReceipt)) { [IO.File]::Delete($tempReceipt) } }
    foreach ($file in $files) {
      $destination = Join-Path $DefaultInstallDir $file.FullName.Substring($Source.Length + 1)
      [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
      [IO.File]::Copy($file.FullName, $destination, $true)
    }
    Add-UserPath -Directory $DefaultInstallDir
  } finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
  }
}

function Get-Release {
  param([string]$Tag = "latest")

  $api = "https://api.github.com/repos/$Repo/releases/$Tag"
  Write-Host "Resolving assets from GitHub release ($Tag)..."
  return Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "gsbt-install" }
}

function Get-ReleaseAsset($Release, [string]$NameLike) {
  $assets = @($Release.assets | Where-Object { $_.name -like $NameLike })
  if ($assets.Count -ne 1) { throw "Expected one asset matching '$NameLike' on this release." }
  $asset = $assets[0]
  if ($asset.digest -notmatch '^sha256:[0-9a-f]{64}$' -or [long]$asset.size -le 0) {
    throw "The release is missing a valid SHA-256 or size for $($asset.name)."
  }
  return $asset
}

function Save-Download([string]$Url, [string]$File, $ReleaseAsset) {
  Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing
  # Explicit URL overrides can refer to a developer's own local release feed.
  if ($ReleaseAsset -and ((Get-Item -LiteralPath $File).Length -ne [long]$ReleaseAsset.size -or
      (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $ReleaseAsset.digest.Substring(7))) {
    throw "The downloaded file differs from the release record for $($ReleaseAsset.name)."
  }
}

function Install-CliZip {
  param([string]$ZipUrl, $ReleaseAsset)

  $tempZip = Join-Path $env:TEMP ("gsbt_cli_" + [guid]::NewGuid().ToString("n") + ".zip")
  $tempDir = Join-Path $env:TEMP ("gsbt_cli_extract_" + [guid]::NewGuid().ToString("n"))
  try {
    Write-Host "Downloading $ZipUrl"
    Save-Download $ZipUrl $tempZip $ReleaseAsset

    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Expand-Archive -LiteralPath $tempZip -DestinationPath $tempDir -Force

    $source = $tempDir
    $nested = Get-ChildItem -LiteralPath $tempDir -Directory -ErrorAction SilentlyContinue |
      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "gsbt.exe") } |
      Select-Object -First 1
    if ($nested) {
      $source = $nested.FullName
    }

    if (-not (Test-Path -LiteralPath (Join-Path $source "gsbt.exe"))) {
      throw "CLI zip did not contain gsbt.exe."
    }

    Write-Host "Installing CLI into: $DefaultInstallDir"
    Install-CliPayload $source

    Write-Host ""
    Write-Host "GSBT Terminal installed. Open a new terminal and try:"
    Write-Host "  gsbt            # interactive prompt"
    Write-Host "  gsbt status"
    Write-Host "  gsbt get gui    # optional desktop app"
    Write-Host "  gsbt uninstall  # remove this standalone installation"
  }
  finally {
    Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Install-DesktopSetup {
  param(
    [string]$InstallerUrl, $ReleaseAsset
  )

  $temp = Join-Path $env:TEMP ("gsbt_setup_" + [guid]::NewGuid().ToString("n") + ".exe")
  try {
    Write-Host "Downloading $InstallerUrl"
    Save-Download $InstallerUrl $temp $ReleaseAsset

    Write-Host "Running installer (per-user, adds gsbt to PATH)..."
    $args = @(
      "/VERYSILENT",
      "/SUPPRESSMSGBOXES",
      "/NORESTART",
      "/TASKS=addpath"
    )
    $proc = Start-Process -FilePath $temp -ArgumentList $args -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
      throw "Installer exited with code $($proc.ExitCode)"
    }

    Add-UserPath -Directory $DefaultInstallDir

    Write-Host ""
    Write-Host "GSBT Desktop installed. Open a new terminal and try:"
    Write-Host "  gsbt list"
    Write-Host "  gsbt gui"
  }
  finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
  }
}

try {
  $flavor = Get-Flavor
  Write-Host "Install flavor: $flavor"

  if ($flavor -eq "cli") {
    if ($env:GSBT_CLI_URL) {
      Install-CliZip -ZipUrl $env:GSBT_CLI_URL
    }
    else {
      $release = Get-Release -Tag $DefaultTag
      $asset = Get-ReleaseAsset $release "GSBT_CLI_*.zip"
      Install-CliZip -ZipUrl $asset.browser_download_url -ReleaseAsset $asset
    }
  }
  else {
    if ($env:GSBT_INSTALLER_URL) {
      Install-DesktopSetup -InstallerUrl $env:GSBT_INSTALLER_URL
    }
    else {
      $release = Get-Release -Tag $DefaultTag
      $asset = Get-ReleaseAsset $release "GSBT_Setup_*.exe"
      Install-DesktopSetup -InstallerUrl $asset.browser_download_url -ReleaseAsset $asset
    }
  }
}
catch {
  Write-Error $_
  exit 1
}
