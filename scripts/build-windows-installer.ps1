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
    .\scripts\build-windows-installer.ps1
    .\scripts\build-windows-installer.ps1 1.4.2
    $env:CLEAN = 1;        .\scripts\build-windows-installer.ps1   # flutter clean first
    $env:SKIP_GEN = 1;     .\scripts\build-windows-installer.ps1   # skip code generation
    $env:SKIP_PACKAGE = 1; .\scripts\build-windows-installer.ps1   # stop after building
    $env:SKIP_INSTALLER = 1; .\scripts\build-windows-installer.ps1 # zip only, no setup.exe
    $env:SKIP_ARCHIVE = 1;   .\scripts\build-windows-installer.ps1 # setup.exe only, no zip
    $env:SKIP_BUILD = 1;     .\scripts\build-windows-installer.ps1   # package an existing build
    $env:SKIP_BUILD = 1; $env:TARGET_ARCH = 'arm64'; .\scripts\build-windows-installer.ps1  # package an arm64 build made elsewhere
    $env:WINDOWS_SIGN_SHA1 = '<thumbprint>'; .\scripts\build-windows-installer.ps1  # sign everything
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

# Locates ISCC.exe. Its installer does not put it on PATH, winget may install
# it per-user rather than per-machine, and the directory is named after the
# major version - so look in every place it can legitimately be rather than
# guessing one path.
function Find-Iscc {
    if ($env:ISCC -and (Test-Path -LiteralPath $env:ISCC)) { return $env:ISCC }

    # A shell opened before the install still has the old PATH, so this misses
    # a fresh install even when it is on PATH for new shells.
    $onPath = (Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue).Source
    if ($onPath) { return $onPath }

    # The uninstall entry records the install directory whatever the version
    # and whichever scope it was installed into.
    foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        $hit = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'Inno Setup*' -and $_.InstallLocation } |
            ForEach-Object { Join-Path $_.InstallLocation 'ISCC.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($hit) { return $hit }
    }

    # Default locations, any major version, machine-wide or per-user.
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)},
               (Join-Path $env:LOCALAPPDATA 'Programs')) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($root in $roots) {
        $hit = Get-ChildItem -Path $root -Filter 'Inno Setup*' -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'ISCC.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($hit) { return $hit }
    }

    return $null
}

# Locates signtool.exe. It ships with the Windows SDK, which never puts it on
# PATH, and a machine can carry several SDK versions side by side - the newest
# x64 build is the one to use: the SimplySign virtual card driver is 64-bit.
function Find-SignTool {
    if ($env:SIGNTOOL -and (Test-Path -LiteralPath $env:SIGNTOOL)) { return $env:SIGNTOOL }

    $onPath = (Get-Command 'signtool.exe' -ErrorAction SilentlyContinue).Source
    if ($onPath) { return $onPath }

    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kits) {
        $hit = Get-ChildItem -LiteralPath $kits -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($hit) { return $hit }
    }

    return $null
}

# Files under $Dir that carry no valid Authenticode signature. Binaries already
# signed by their own vendor keep that signature rather than gaining ours.
function Get-UnsignedBinaries {
    param([string]$Dir)
    Get-ChildItem -LiteralPath $Dir -Recurse -File |
        Where-Object { $_.Extension -in '.exe', '.dll' } |
        Where-Object { (Get-AuthenticodeSignature -LiteralPath $_.FullName).Status -ne 'Valid' } |
        ForEach-Object { $_.FullName }
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

# Flutter builds for the machine it runs on and has no switch to target the
# other Windows architecture. TARGET_ARCH therefore only says which existing
# build to package: an arm64 build made on an Arm machine can be signed and
# packed on an x64 one, where the signing tools are known to work.
# An x64 shell running under emulation on an Arm machine reports AMD64 in
# PROCESSOR_ARCHITECTURE and the real architecture in PROCESSOR_ARCHITEW6432.
$HostArch = if ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64' -or
    $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
$Arch = Get-EnvOrDefault 'TARGET_ARCH' $HostArch
if ($Arch -notin @('x64', 'arm64')) {
    Stop-WithError "TARGET_ARCH must be x64 or arm64, not '$Arch'."
}
if ($Arch -ne $HostArch -and -not $env:SKIP_BUILD) {
    Stop-WithError ("Cannot build for $Arch on an $HostArch machine.`n" +
        "  Build on $Arch, then package here with `$env:SKIP_BUILD = 1.")
}
Write-Ok "Architecture: $Arch"

# Packaging an existing build needs neither Flutter nor a compiler.
if ($env:SKIP_BUILD) {
    Write-Ok 'SKIP_BUILD is set - not checking the build toolchain'
} else {
    $VcComponent = if ($HostArch -eq 'arm64') {
        'Microsoft.VisualStudio.Component.VC.Tools.ARM64'
    } else {
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
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
            -requires $VcComponent `
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

# Signing is switched on by naming the certificate. The private key never sits
# on this machine: with Certum SimplySign the certificate shows up in the user's
# store only while SimplySign Desktop is logged in, and every signature is made
# in Certum's cloud. Checking for it here fails in seconds instead of after a
# full build.
$SignSha1 = (Get-EnvOrDefault 'WINDOWS_SIGN_SHA1' '') -replace '\s', ''
$SignSha1 = $SignSha1.ToUpperInvariant()
$TimestampUrl = Get-EnvOrDefault 'WINDOWS_TIMESTAMP_URL' 'http://time.certum.pl'
$SignTool = $null

if ($SignSha1) {
    $SignTool = Find-SignTool
    if (-not $SignTool) {
        Stop-WithError ("signtool.exe not found.`n" +
            "  It comes with the Windows SDK. Point at it directly with:`n" +
            "    `$env:SIGNTOOL = 'C:\Path\To\signtool.exe'")
    }
    Write-Ok "signtool: $SignTool"

    $Cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $SignSha1 } |
        Select-Object -First 1
    if (-not $Cert) {
        Stop-WithError ("No certificate with thumbprint $SignSha1 in Cert:\CurrentUser\My.`n" +
            '  Is SimplySign Desktop running and logged in?')
    }
    Write-Ok "Signing as: $($Cert.Subject) (valid to $($Cert.NotAfter.ToString('yyyy-MM-dd')))"
} elseif ($env:SKIP_PACKAGE) {
    # A build-only pass leaves signing to a later SKIP_BUILD run, which is how
    # the release pipeline keeps the signing session short; nothing to warn of.
    Write-Ok 'Build only - signing, if any, happens when this build is packaged'
} else {
    Write-Warn 'WINDOWS_SIGN_SHA1 is empty - building unsigned'
}

# ─── Build ───────────────────────────────────────────────────────────────────

if ($env:SKIP_BUILD) {
    Write-Warn 'SKIP_BUILD is set - packaging the build that is already there'
} else {
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
}

$ReleaseDir = Join-Path 'build' "windows\$Arch\runner\Release"
# With an explicit TARGET_ARCH the first Release directory found could belong
# to the other architecture, so only the exact path counts.
if (-not (Test-Path -LiteralPath $ReleaseDir) -and -not $env:TARGET_ARCH) {
    $found = Get-ChildItem -Path 'build\windows' -Recurse -Directory -Filter 'Release' `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $ReleaseDir = $found.FullName }
}
if (-not (Test-Path -LiteralPath $ReleaseDir)) {
    if ($env:SKIP_BUILD) {
        Stop-WithError "SKIP_BUILD is set, but there is no $Arch build under build\windows to package."
    }
    Stop-WithError 'No release output was produced under build\windows'
}
Write-Ok "Built: $ReleaseDir"

# An installer named for one architecture around an exe built for the other
# installs fine and then fails to start, so read the machine type out of the
# PE header rather than trust the directory name.
$MainExe = Join-Path $ReleaseDir "$AppName.exe"
if (-not (Test-Path -LiteralPath $MainExe)) {
    $MainExe = Get-ChildItem -LiteralPath $ReleaseDir -Filter '*.exe' -File |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $MainExe) { Stop-WithError "No .exe in $ReleaseDir" }
# .NET resolves relative paths against the process directory, which
# Set-Location above does not move, so hand it an absolute one.
$PeBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $MainExe).ProviderPath)
$PeOffset = [System.BitConverter]::ToInt32($PeBytes, 0x3C)
$PeMachine = [System.BitConverter]::ToUInt16($PeBytes, $PeOffset + 4)
$ExpectedMachine = @{ 'x64' = 0x8664; 'arm64' = 0xAA64 }[$Arch]
if ($PeMachine -ne $ExpectedMachine) {
    Stop-WithError ("$MainExe is machine type 0x{0:X4}, not the {1} type 0x{2:X4}." -f
        $PeMachine, $Arch, $ExpectedMachine)
}
Write-Ok "$(Split-Path -Leaf $MainExe) is an $Arch binary"

# ─── Sign ────────────────────────────────────────────────────────────────────

# Inno Setup packs these files into setup.exe, so they are signed before it is
# built: a signed installer around unsigned binaries still trips SmartScreen
# and antivirus heuristics once installed.
if ($SignSha1) {
    Write-Step 'Signing binaries'

    # A timestamp server or the cloud key can drop a request now and then.
    # Each retry signs only what is still unsigned, so nothing gets signed twice.
    $Attempts = 3
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $Pending = @(Get-UnsignedBinaries $ReleaseDir)
        if ($Pending.Count -eq 0) { break }
        Write-Ok "$($Pending.Count) file(s) to sign (attempt $attempt of $Attempts)"

        & $SignTool sign /sha1 $SignSha1 /fd SHA256 /tr $TimestampUrl /td SHA256 /d $AppName @Pending
        if ($LASTEXITCODE -eq 0) { break }
        if ($attempt -lt $Attempts) {
            Write-Warn "signtool exited with $LASTEXITCODE - retrying"
            Start-Sleep -Seconds (5 * $attempt)
        }
    }

    $Left = @(Get-UnsignedBinaries $ReleaseDir)
    if ($Left.Count -gt 0) {
        Stop-WithError ("These binaries are still unsigned:`n  " + ($Left -join "`n  "))
    }
    Write-Ok 'Every .exe and .dll carries a valid signature'
}

# ─── Package ─────────────────────────────────────────────────────────────────

if ($env:SKIP_PACKAGE) {
    Write-Host "`n[ok] Done: $ReleaseDir`n" -ForegroundColor Green
    exit 0
}

Write-Step 'Packaging'

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

$Archive = $null

if ($env:SKIP_ARCHIVE) {
    Write-Warn 'SKIP_ARCHIVE is set - building no zip'
} else {
    $Archive = Join-Path $DistDir "$AppName-$Version-windows-$Arch.zip"
    if (Test-Path -LiteralPath $Archive) { Remove-Item -LiteralPath $Archive -Force }

    Compress-Archive -Path (Join-Path $ReleaseDir '*') -DestinationPath $Archive
    Write-Ok "Archive: $Archive"

    $SizeMb = [math]::Round((Get-Item -LiteralPath $Archive).Length / 1MB, 1)
}

# ─── Installer ───────────────────────────────────────────────────────────────

$Installer = $null

if ($env:SKIP_INSTALLER) {
    Write-Warn 'SKIP_INSTALLER is set - building no setup.exe'
} else {
    Write-Step 'Building the installer'

    $Iscc = Find-Iscc
    if (-not $Iscc) {
        Stop-WithError ("Inno Setup not found (ISCC.exe).`n" +
            "  Install it:  winget install -e --id JRSoftware.InnoSetup`n" +
            "  Already installed? A shell opened before the install has a stale`n" +
            "  PATH - reopen it, or point at the binary directly:`n" +
            "    `$env:ISCC = 'C:\Path\To\Inno Setup 6\ISCC.exe'`n" +
            '  Or skip it:  $env:SKIP_INSTALLER = 1')
    }
    Write-Ok "Inno Setup: $Iscc"

    # ISCC resolves relative paths against the .iss file, so hand it absolute
    # ones for the directories that live outside windows\packaging.
    $IssFile     = (Resolve-Path 'windows\packaging\mergelio.iss').Path
    $SourceAbs   = (Resolve-Path $ReleaseDir).Path
    $OutputAbs   = (Resolve-Path $DistDir).Path

    $IsccArgs = @(
        "/DAppName=$AppName",
        "/DAppVersion=$Version",
        "/DAppArch=$Arch",
        "/DSourceDir=$SourceAbs",
        "/DOutputDir=$OutputAbs"
    )
    # Handing Inno Setup a sign tool makes it sign both setup.exe and the
    # uninstaller it writes into Program Files, which no later step could
    # reach: the uninstaller only exists inside the compressed installer.
    # Inno expands $q to a quote and $f to the quoted path of the file.
    if ($SignSha1) {
        $IsccArgs += '/DSignToolName=mergelio'
        $IsccArgs += ('/Smergelio=$q' + $SignTool + '$q sign /sha1 ' + $SignSha1 +
            ' /fd SHA256 /tr ' + $TimestampUrl + ' /td SHA256 /d $q' + $AppName + '$q $f')
    }

    & $Iscc @IsccArgs $IssFile
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'Inno Setup failed to build the installer.' }

    $Installer = Join-Path $DistDir "$AppName-$Version-windows-$Arch-setup.exe"
    if (-not (Test-Path -LiteralPath $Installer)) {
        Stop-WithError "Inno Setup reported success but $Installer is missing."
    }
    Write-Ok "Installer: $Installer"
}

Write-Host "`n[ok] Done" -ForegroundColor Green
Write-Host "  build:   $ReleaseDir"
if ($Archive) {
    Write-Host "  archive: $Archive ($SizeMb MB)"
}
if ($Installer) {
    $InstallerMb = [math]::Round((Get-Item -LiteralPath $Installer).Length / 1MB, 1)
    Write-Host "  setup:   $Installer ($InstallerMb MB)"
}
# Whether the installer ends up signed is decided by the pipeline that calls
# this script, so report what the file actually carries rather than assuming.
if ($Installer) {
    $Signature = Get-AuthenticodeSignature -LiteralPath $Installer
    if ($Signature.Status -eq 'Valid') {
        Write-Host "`n  Signed by: $($Signature.SignerCertificate.Subject)`n" -ForegroundColor Green
    } elseif ($SignSha1) {
        Stop-WithError "Signing was requested, but $Installer is $($Signature.Status): $($Signature.StatusMessage)"
    } else {
        Write-Host "`n  Unsigned: SmartScreen will warn on other machines.`n" -ForegroundColor Yellow
    }
} else {
    Write-Host ''
}
