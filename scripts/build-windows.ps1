#Requires -Version 5.1
<#
.SYNOPSIS
    Build Mergelio for Windows.

.DESCRIPTION
    Produces a release build, a zip archive and an Inno Setup installer in
    DIST_DIR. Configuration is read from .env in the repository root (see
    .env.example); values already present in the environment take precedence.

    The installer puts the app in Program Files, creates Start menu and
    optional desktop shortcuts, and registers an uninstall entry. Building it
    needs Inno Setup 6: winget install -e --id JRSoftware.InnoSetup

.PARAMETER Version
    Version used in the archive name. Defaults to the version in pubspec.yaml.

.EXAMPLE
    .\scripts\build-windows.ps1
    .\scripts\build-windows.ps1 1.4.2
    $env:CLEAN = 1;        .\scripts\build-windows.ps1   # flutter clean first
    $env:SKIP_GEN = 1;     .\scripts\build-windows.ps1   # skip code generation
    $env:SKIP_PACKAGE = 1; .\scripts\build-windows.ps1   # build no archive
    $env:SKIP_INSTALLER = 1; .\scripts\build-windows.ps1 # zip only, no setup.exe
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'

# ─── Output ──────────────────────────────────────────────────────────────────

function Write-Step { param([string]$Message) Write-Host "`n> $Message" -ForegroundColor White }
function Write-Ok   { param([string]$Message) Write-Host "  [ok] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "  [!]  $Message" -ForegroundColor Yellow }
function Stop-WithError {
    param([string]$Message)
    Write-Host "`n[x] $Message`n" -ForegroundColor Red
    exit 1
}

# ─── Environment ─────────────────────────────────────────────────────────────

# Reads KEY=VALUE pairs from .env without executing anything. Values already
# present in the environment are left alone, which allows one-off overrides.
function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(#|$)') { continue }
        if ($line -notmatch '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { continue }
        $key = $Matches[1]
        $value = $Matches[2]
        if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") { $value = $Matches[1] }
        if ([Environment]::GetEnvironmentVariable($key)) { continue }
        Set-Item -Path "Env:$key" -Value $value
    }
}

function Get-EnvOrDefault {
    param([string]$Name, [string]$Default)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($value)) { return $Default }
    return $value
}

# The repository root is one level above this script.
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location -LiteralPath $RepoRoot

if (-not (Test-Path 'pubspec.yaml') -or -not (Test-Path 'lib')) {
    Stop-WithError 'This does not look like the Mergelio repository.'
}

Import-DotEnv '.env'

$AppName = Get-EnvOrDefault 'APP_NAME' 'Mergelio'
$DistDir = Get-EnvOrDefault 'DIST_DIR' 'dist'

# ─── Preflight ───────────────────────────────────────────────────────────────

Write-Step 'Checking environment'

if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    Stop-WithError 'Windows builds require a Windows host.'
}

foreach ($tool in @('flutter', 'dart')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Stop-WithError "$tool not found in PATH."
    }
}
Write-Ok 'flutter and dart are in PATH'

# A newer Flutter than the pinned one fails deep inside build_runner with an
# analyzer stack trace that says nothing about versions, so name the mismatch
# here while the output is still readable.
if (Test-Path '.fvmrc') {
    $pinned = $null
    $match = Select-String -Path '.fvmrc' -Pattern '"flutter"\s*:\s*"([^"]+)"' |
        Select-Object -First 1
    if ($match) { $pinned = $match.Matches[0].Groups[1].Value }

    if ($pinned) {
        $current = $null
        $line = (flutter --version 2>$null | Select-Object -First 1)
        if ($line -match '^Flutter (\d+\.\d+\.\d+)') { $current = $Matches[1] }

        if (-not $current) {
            Write-Warn "Could not read the Flutter version; this project expects $pinned."
        } elseif ($current -eq $pinned) {
            Write-Ok "Flutter $current (pinned in .fvmrc)"
        } else {
            Write-Warn "Flutter $current, but this project is pinned to $pinned (.fvmrc)."
            Write-Warn "Code generation may fail. Switch with 'fvm use' or 'flutter downgrade $pinned'."
        }
    }
}

# Flutter needs the Visual Studio C++ desktop workload. Its absence surfaces as
# an obscure CMake failure, so look for it up front.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $vswhere) {
    $vs = & $vswhere -latest -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property displayName 2>$null
    if ($vs) {
        Write-Ok "Visual Studio: $vs"
    } else {
        Write-Warn 'Visual Studio "Desktop development with C++" workload not found.'
        Write-Warn 'Install it, or run: flutter doctor'
    }
} else {
    Write-Warn 'vswhere.exe not found; cannot verify the Visual Studio C++ workload.'
}

if (-not $Version) {
    $line = Select-String -Path 'pubspec.yaml' -Pattern '^version:' | Select-Object -First 1
    if ($line) {
        $Version = ($line.Line -replace '^version:\s*', '') -replace '\+.*$', ''
        $Version = $Version.Trim()
    }
}
if (-not $Version) { Stop-WithError 'Could not determine the version.' }
Write-Ok "Version: $Version"

$Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
Write-Ok "Architecture: $Arch"

# ─── Build ───────────────────────────────────────────────────────────────────

if ($env:CLEAN) {
    Write-Step 'Cleaning'
    flutter clean | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'flutter clean failed.' }
    Write-Ok 'flutter clean done'
}

# .dart_tool\package_config.json records absolute paths to the Flutter SDK, so
# a working copy carried over from another machine (zip, scp, shared volume)
# brings that machine's paths with it. pub skips rewriting the file when it
# looks newer than the pubspecs, so 'pub get' reports success and build_runner
# then dies on a path that does not exist here.
$PackageConfig = '.dart_tool\package_config.json'
if (Test-Path -LiteralPath $PackageConfig) {
    try {
        $cfg = Get-Content -LiteralPath $PackageConfig -Raw | ConvertFrom-Json
        $sky = $cfg.packages | Where-Object { $_.name -eq 'sky_engine' } | Select-Object -First 1
        if ($sky -and $sky.rootUri -like 'file:*') {
            $skyPath = ([uri]$sky.rootUri).LocalPath
            if (-not (Test-Path -LiteralPath $skyPath)) {
                Write-Warn "package_config.json points at $skyPath, which does not exist here."
                Write-Warn "Discarding .dart_tool so 'pub get' regenerates it for this machine."
                Remove-Item -Recurse -Force '.dart_tool'
            }
        }
    } catch {
        Write-Warn 'package_config.json could not be read; discarding .dart_tool.'
        Remove-Item -Recurse -Force '.dart_tool' -ErrorAction SilentlyContinue
    }
}

Write-Step 'Fetching dependencies'
flutter pub get
if ($LASTEXITCODE -ne 0) { Stop-WithError 'flutter pub get failed.' }
Write-Ok 'Dependencies ready'

# Generated sources (*.g.dart, *.freezed.dart) are not committed, so a fresh
# clone will not compile until build_runner has run.
if ($env:SKIP_GEN) {
    Write-Warn 'SKIP_GEN is set - skipping code generation'
} else {
    Write-Step 'Generating sources (freezed / json / drift)'
    dart run build_runner build --delete-conflicting-outputs
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'Code generation failed.' }
    Write-Ok 'Generated sources up to date'
}

Write-Step 'Building (flutter build windows --release)'
flutter build windows --release
if ($LASTEXITCODE -ne 0) { Stop-WithError 'flutter build windows failed.' }

$ReleaseDir = Join-Path 'build' "windows\$Arch\runner\Release"
if (-not (Test-Path -LiteralPath $ReleaseDir)) {
    $found = Get-ChildItem -Path 'build\windows' -Recurse -Directory -Filter 'Release' `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $ReleaseDir = $found.FullName }
}
if (-not (Test-Path -LiteralPath $ReleaseDir)) {
    Stop-WithError 'No release output was produced under build\windows'
}
Write-Ok "Built: $ReleaseDir"

# ─── Package ─────────────────────────────────────────────────────────────────

if ($env:SKIP_PACKAGE) {
    Write-Host "`n[ok] Done: $ReleaseDir`n" -ForegroundColor Green
    exit 0
}

Write-Step 'Packaging'

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$Archive = Join-Path $DistDir "$AppName-$Version-windows-$Arch.zip"
if (Test-Path -LiteralPath $Archive) { Remove-Item -LiteralPath $Archive -Force }

Compress-Archive -Path (Join-Path $ReleaseDir '*') -DestinationPath $Archive
Write-Ok "Archive: $Archive"

$SizeMb = [math]::Round((Get-Item -LiteralPath $Archive).Length / 1MB, 1)

# ─── Installer ───────────────────────────────────────────────────────────────

$Installer = $null

if ($env:SKIP_INSTALLER) {
    Write-Warn 'SKIP_INSTALLER is set - building no setup.exe'
} else {
    Write-Step 'Building the installer'

    # ISCC is not added to PATH by its own installer, so fall back to the
    # default locations before giving up.
    $Iscc = (Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue).Source
    if (-not $Iscc) {
        foreach ($candidate in @(
            (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
            (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
        )) {
            if ($candidate -and (Test-Path -LiteralPath $candidate)) { $Iscc = $candidate; break }
        }
    }
    if (-not $Iscc) {
        Stop-WithError ("Inno Setup 6 not found (ISCC.exe).`n" +
            "  Install it:  winget install -e --id JRSoftware.InnoSetup`n" +
            '  Or skip it:  $env:SKIP_INSTALLER = 1')
    }
    Write-Ok "Inno Setup: $Iscc"

    # ISCC resolves relative paths against the .iss file, so hand it absolute
    # ones for the directories that live outside windows\packaging.
    $IssFile     = (Resolve-Path 'windows\packaging\mergelio.iss').Path
    $SourceAbs   = (Resolve-Path $ReleaseDir).Path
    $OutputAbs   = (Resolve-Path $DistDir).Path

    & $Iscc `
        "/DAppName=$AppName" `
        "/DAppVersion=$Version" `
        "/DAppArch=$Arch" `
        "/DSourceDir=$SourceAbs" `
        "/DOutputDir=$OutputAbs" `
        $IssFile
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'Inno Setup failed to build the installer.' }

    $Installer = Join-Path $DistDir "$AppName-$Version-windows-$Arch-setup.exe"
    if (-not (Test-Path -LiteralPath $Installer)) {
        Stop-WithError "Inno Setup reported success but $Installer is missing."
    }
    Write-Ok "Installer: $Installer"
}

Write-Host "`n[ok] Done" -ForegroundColor Green
Write-Host "  build:   $ReleaseDir"
Write-Host "  archive: $Archive ($SizeMb MB)"
if ($Installer) {
    $InstallerMb = [math]::Round((Get-Item -LiteralPath $Installer).Length / 1MB, 1)
    Write-Host "  setup:   $Installer ($InstallerMb MB)"
}
Write-Host "`n  Unsigned: SmartScreen will warn on other machines.`n"
