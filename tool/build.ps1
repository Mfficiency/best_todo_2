param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$BuildArgs
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$Arguments = @()
  )

  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

# Which app a set of `flutter build` arguments builds. android/app/build.gradle.kts
# defines the `todo` (BestToDo) and `music` (Best Music — lib/main_music.dart,
# SPEC.md §10.6f) product flavors, and an `apk` build now *requires* an explicit
# --flavor, so default to `todo` here rather than making every existing
# `build.ps1 apk --release` caller pass one. The returned flavor also drives the
# artifact name (best_<flavor>_<version>.apk, the prefix UpdateService filters
# the per-app update check on) and which version file/changelog is used.
function Get-FlavorArg {
  param([string[]]$ArgsForFlutter)

  $prev = ""
  foreach ($arg in $ArgsForFlutter) {
    if ($prev -eq "--flavor") {
      return $arg
    }
    $prev = $arg
  }
  return ""
}

function Get-PubspecVersion {
  $versionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:" | Select-Object -First 1
  if ($null -eq $versionLine) {
    throw "Could not find version: in pubspec.yaml"
  }
  return (($versionLine.Line -split "\s+", 2)[1]).Trim()
}

# Best Music versions independently of BestToDo, out of its own MUSIC_VERSION
# file rather than pubspec.yaml (CLAUDE.md / SPEC.md §10.6i).
function Get-MusicVersion {
  $versionLine = Select-String -Path "MUSIC_VERSION" -Pattern "^version:" | Select-Object -First 1
  if ($null -eq $versionLine) {
    throw "Could not find version: in MUSIC_VERSION"
  }
  return (($versionLine.Line -split "\s+", 2)[1]).Trim()
}

function Get-AppVersion {
  param([string]$Flavor)

  if ($Flavor -eq "music") {
    return Get-MusicVersion
  }
  return Get-PubspecVersion
}

function Test-IsCacheableReleaseBuild {
  param([string[]]$ArgsForFlutter)

  if ($ArgsForFlutter.Count -eq 0) {
    return $false
  }

  if ($ArgsForFlutter.Count -gt 1) {
    $skipNext = $false
    foreach ($arg in $ArgsForFlutter[1..($ArgsForFlutter.Count - 1)]) {
      if ($skipNext) {
        $skipNext = $false
        continue
      }
      switch ($arg) {
        "--release" { }
        # Flavor/entrypoint selection picks *which* app is built, not how; both
        # take a value, which must not be mistaken for an extra build switch.
        "--flavor" { $skipNext = $true }
        "-t" { $skipNext = $true }
        default { return $false }
      }
    }
  }
  return $true
}

function Get-ExistingBuildArtifact {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string[]]$ArgsForFlutter = @(),
    [string]$Prefix = "best_todo"
  )

  if ($env:FORCE_BUILD -eq "1" -or -not (Test-IsCacheableReleaseBuild $ArgsForFlutter)) {
    return $null
  }

  $target = if ($ArgsForFlutter.Count -gt 0) { $ArgsForFlutter[0] } else { "" }
  $candidates = switch ($target) {
    "apk" {
      @(
        "github_releases/${Prefix}_$Version.apk",
        "build/app/outputs/flutter-apk/${Prefix}_$Version.apk"
      )
    }
    "web" { @("build/web-$Version") }
    "windows" { @("build/windows/x64/runner/Release/BestToDo-$Version.exe") }
    default { @() }
  }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }
  return $null
}

function Rename-IfExists {
  param(
    [Parameter(Mandatory = $true)]
    [string]$From,
    [Parameter(Mandatory = $true)]
    [string]$To
  )

  if (Test-Path -LiteralPath $From) {
    if (Test-Path -LiteralPath $To) {
      Remove-Item -LiteralPath $To -Force
    }
    Move-Item -LiteralPath $From -Destination $To
    Write-Host "Renamed $From -> $To"
  }
}

function Invoke-SingleBuild {
  param([string[]]$ArgsForFlutter)

  $target = if ($ArgsForFlutter.Count -gt 0) { $ArgsForFlutter[0] } else { "" }

  $flavor = ""
  if ($target -eq "apk") {
    $flavor = Get-FlavorArg $ArgsForFlutter
    if ([string]::IsNullOrWhiteSpace($flavor)) {
      $flavor = "todo"
      $ArgsForFlutter = $ArgsForFlutter + @("--flavor", "todo")
    }
  }
  $appFlavor = if ([string]::IsNullOrWhiteSpace($flavor)) { "todo" } else { $flavor }
  $prefix = "best_$appFlavor"

  $version = Get-AppVersion -Flavor $appFlavor
  $existingArtifact = Get-ExistingBuildArtifact -Version $version `
    -ArgsForFlutter $ArgsForFlutter -Prefix $prefix
  if ($null -ne $existingArtifact) {
    Write-Host "==> existing release build found: $existingArtifact"
    Write-Host "    skipping flutter build (set FORCE_BUILD=1 to rebuild)"

    if ($target -eq "apk" -and $existingArtifact -like "build/app/outputs/flutter-apk/*") {
      Invoke-Checked "dart" @("run", "tool/stage_local_release.dart",
        "--apk", $existingArtifact, "--prefix", $prefix, "--version", $version)
    }

    # tool/publish_apk.dart only ever publishes a BestToDo GitHub release --
    # Best Music's update check never looks at GitHub releases, only at
    # github_releases/ (UpdateService.checkReleases), so publishing there for a
    # music build would just mislabel this APK as a BestToDo one.
    if ($env:PUBLISH_APK -eq "1" -and $appFlavor -ne "music") {
      if ($existingArtifact -like "*.apk") {
        Invoke-Checked "dart" @("run", "tool/publish_apk.dart", "--apk", $existingArtifact)
      } else {
        Invoke-Checked "dart" @("run", "tool/publish_apk.dart")
      }
    }
    return
  }

  if ($env:SKIP_PREFLIGHT -ne "1") {
    Invoke-Checked "dart" @("run", "tool/pull_test_report.dart")
    Invoke-Checked "flutter" @("test", "test/core/build_smoke_test.dart")
  }

  $buildStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  & flutter @("build") @ArgsForFlutter
  $buildStatus = $LASTEXITCODE
  $buildStopwatch.Stop()
  $buildDurationSeconds = [int][Math]::Round($buildStopwatch.Elapsed.TotalSeconds)

  if ($buildStatus -eq 0) {
    # A music build notes its time in CHANGELOG_MUSIC.md instead of CHANGELOG.md.
    $appArgs = @()
    if ($appFlavor -eq "music") {
      $appArgs = @("--app", "music")
    }
    Invoke-Checked "dart" (@("run", "tool/append_build_time.dart",
      "--duration", "$buildDurationSeconds", "--target", $target) + $appArgs)
  } else {
    Write-Error "flutter build $($ArgsForFlutter -join ' ') failed (status $buildStatus)"
    exit $buildStatus
  }

  # Android APK -> best_<flavor>_<version>.apk (Gradle's createVersionedReleaseApk
  # task already writes this file directly; this is a fallback for whichever of
  # the two names the Flutter/Gradle tooling actually produced).
  Rename-IfExists `
    "build/app/outputs/flutter-apk/app-$appFlavor-release.apk" `
    "build/app/outputs/flutter-apk/${prefix}_$version.apk"

  $apkPath = "build/app/outputs/flutter-apk/${prefix}_$version.apk"
  if (Test-Path -LiteralPath $apkPath) {
    Invoke-Checked "dart" @("run", "tool/stage_local_release.dart",
      "--apk", $apkPath, "--prefix", $prefix, "--version", $version)
  }

  if (Test-Path -LiteralPath "build/web") {
    $webBuildPath = "build/web-$version"
    if (Test-Path -LiteralPath $webBuildPath) {
      Remove-Item -LiteralPath $webBuildPath -Recurse -Force
    }
    Move-Item -LiteralPath "build/web" -Destination $webBuildPath
    Write-Host "Renamed build/web -> $webBuildPath"
  }

  Rename-IfExists `
    "build/windows/x64/runner/Release/BestToDo.exe" `
    "build/windows/x64/runner/Release/BestToDo-$version.exe"

  if ($env:PUBLISH_APK -eq "1" -and $appFlavor -ne "music") {
    Invoke-Checked "dart" @("run", "tool/publish_apk.dart")
  }
}

function Invoke-BuildAll {
  param([string[]]$ArgsForTargets)

  if ($ArgsForTargets.Count -eq 0) {
    $ArgsForTargets = @("--release")
  }

  $windowsStatus = "skipped"
  $androidStatus = "skipped"
  $musicStatus = "skipped"

  if ($env:ANDROID -ne "0") {
    Write-Host "==> flutter build apk --flavor todo $($ArgsForTargets -join ' ')"
    Invoke-SingleBuild (@("apk", "--flavor", "todo") + $ArgsForTargets)
    $androidStatus = "ok"
    $env:SKIP_PREFLIGHT = "1"
  }

  # Best Music ships from this same repo as its own APK (SPEC.md §10.6f), so
  # "everything this project ships" includes it. MUSIC=0 skips it.
  if ($env:ANDROID -ne "0" -and $env:MUSIC -ne "0") {
    Write-Host "==> flutter build apk --flavor music $($ArgsForTargets -join ' ')"
    Invoke-SingleBuild (@("apk", "--flavor", "music", "-t", "lib/main_music.dart") + $ArgsForTargets)
    $musicStatus = "ok"
    $env:SKIP_PREFLIGHT = "1"
  }

  if ($env:WINDOWS -ne "0") {
    Write-Host "==> flutter build windows $($ArgsForTargets -join ' ')"
    try {
      Invoke-SingleBuild (@("windows") + $ArgsForTargets)
      $windowsStatus = "ok"
    } catch {
      $windowsStatus = "FAILED"
      if ($env:REQUIRE_WINDOWS -eq "1") {
        Write-Error "Windows build failed and REQUIRE_WINDOWS=1 -- stopping."
        throw
      }
      Write-Warning "Windows build failed -- continuing with the Android artifacts."
    }
    $env:SKIP_PREFLIGHT = "1"
  }

  $version = Get-PubspecVersion

  if ($env:SYNC -eq "0") {
    Write-Host "==> SYNC=0: skipping git commit/push"
  } else {
    $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
      throw "git rev-parse failed with exit code $LASTEXITCODE"
    }

    Write-Host "==> syncing github_releases/ + changelogs on $branch"
    Invoke-Checked "git" @("add", "github_releases", "CHANGELOG.md")
    # Best Music's build time lands in its own changelog, not CHANGELOG.md.
    if (Test-Path -LiteralPath "CHANGELOG_MUSIC.md") {
      Invoke-Checked "git" @("add", "CHANGELOG_MUSIC.md")
    }
    if (Test-Path -LiteralPath "build_history.json") {
      Invoke-Checked "git" @("add", "build_history.json")
    }

    & git diff --cached --quiet
    $hasNoCachedDiff = ($LASTEXITCODE -eq 0)
    if ($hasNoCachedDiff) {
      Write-Host "    nothing to commit (github_releases/ already up to date)"
    } else {
      Invoke-Checked "git" @("commit", "-m", "chore: release build $version")
      Write-Host "    committed release build $version"
    }

    if ($env:PUSH -eq "0") {
      Write-Host "    PUSH=0: not pushing"
    } else {
      Invoke-Checked "git" @("pull", "--rebase", "--autostash", "origin", $branch)
      Invoke-Checked "git" @("push", "origin", $branch)
      Write-Host "    pushed $branch to origin"
    }

    $staleFiles = & git ls-files --others --exclude-standard github_releases
    if ($LASTEXITCODE -ne 0) {
      throw "git ls-files failed with exit code $LASTEXITCODE"
    }
    foreach ($stale in $staleFiles) {
      if ([string]::IsNullOrWhiteSpace($stale)) {
        continue
      }
      Remove-Item -LiteralPath $stale -Force
      Write-Host "    removed pruned leftover $stale"
    }
  }

  Write-Host ""
  Write-Host "=== build all ($version) ==="
  Write-Host "  android : $androidStatus"
  Write-Host "  music   : $musicStatus"
  Write-Host "  windows : $windowsStatus"

  Get-ChildItem -Path "github_releases" -Filter "*.apk" -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Host "  staged  : $($_.FullName)" }

  $exePath = "build/windows/x64/runner/Release/BestToDo-$version.exe"
  if (Test-Path -LiteralPath $exePath) {
    Write-Host "  exe     : $exePath"
  }

  if ($windowsStatus -eq "FAILED") {
    exit 1
  }
}

Set-Location (Get-RepoRoot)

if ($BuildArgs.Count -gt 0 -and $BuildArgs[0] -eq "all") {
  if ($BuildArgs.Count -eq 1) {
    Invoke-BuildAll @()
  } else {
    Invoke-BuildAll $BuildArgs[1..($BuildArgs.Count - 1)]
  }
} elseif ($BuildArgs.Count -gt 0 -and $BuildArgs[0] -eq "music-apk") {
  # Shorthand for the Best Music flavor, matching `sh tool/build.sh music-apk`:
  #   powershell -File tool\build.ps1 music-apk --release
  $rest = if ($BuildArgs.Count -gt 1) { $BuildArgs[1..($BuildArgs.Count - 1)] } else { @() }
  Invoke-SingleBuild (@("apk", "--flavor", "music", "-t", "lib/main_music.dart") + $rest)
} else {
  Invoke-SingleBuild $BuildArgs
}
