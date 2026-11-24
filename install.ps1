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

function Add-UserPath {
  param([Parameter(Mandatory)][string]$Directory)

  $envKey = "HKCU:\Environment"
  $current = (Get-ItemProperty -Path $envKey -Name Path -ErrorAction SilentlyContinue).Path
  $parts = @()
  if (-not [string]::IsNullOrWhiteSpace($current)) {
    $parts = $current -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  }

  if ($parts | Where-Object { $_.TrimEnd('\') -ieq $Directory.TrimEnd('\') }) {
    $env:PATH = "$Directory;$env:PATH"
    Write-Host "PATH already contains: $Directory"
    return
  }

  $newPath = if ([string]::IsNullOrWhiteSpace($current)) { $Directory } else { "$current;$Directory" }
  Set-ItemProperty -Path $envKey -Name Path -Value $newPath
  $env:PATH = "$Directory;$env:PATH"
  Write-Host "Added to user PATH: $Directory"
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

    New-Item -ItemType Directory -Path $DefaultInstallDir -Force | Out-Null
    Write-Host "Installing CLI into: $DefaultInstallDir"
    Copy-Item -Path (Join-Path $source "*") -Destination $DefaultInstallDir -Recurse -Force

    Add-UserPath -Directory $DefaultInstallDir

    Write-Host ""
    Write-Host "GSBT Terminal installed. Open a new terminal and try:"
    Write-Host "  gsbt status"
    Write-Host "  gsbt get gui    # optional desktop app"
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
