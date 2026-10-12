param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$BuildArgs
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

# Exit code of a native command, without throwing or printing its output.
function Test-Native {
  param([string]$Exe, [string[]]$Arguments = @())
  $saved = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $Exe @Arguments *> $null
    return $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $saved
  }
}

# The commit a release build is for: HEAD, or, when HEAD is this script's own
# APK commit (it only changes $Folder), the newest commit below it that
# changes something else. So an APK commit whose release went out finds that
# release and stops, a release that failed after the push is retried, and a
# push the APK commit was rebased onto still gets built.
function Get-SourceCommit {
  param([string]$Folder)
  $commit = (& git rev-parse HEAD).Trim()
  while ($true) {
    $parents = @((& git rev-list --parents -n 1 $commit).Trim() -split ' ' | Select-Object -Skip 1)
    if ($parents.Count -ne 1) { return $commit }
    if ((Test-Native "git" @("diff", "--quiet", $parents[0], $commit, "--", ".", ":(exclude)$Folder")) -ne 0) {
      return $commit
    }
    $commit = $parents[0]
  }
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
    # What was built, so its size is tracked too ("- APK size:" line and
    # build_history.json's sizeBytes).
    $artifact = $null
    if ($target -eq "apk") {
      $artifact = "build/app/outputs/flutter-apk/${prefix}_$version.apk"
      if (-not (Test-Path -LiteralPath $artifact)) {
        $artifact = "build/app/outputs/flutter-apk/app-$appFlavor-release.apk"
      }
    } elseif ($target -eq "windows") {
      $artifact = "build/windows/x64/runner/Release"
    }
    if ($artifact) {
      $appArgs += @("--artifact", $artifact)
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

# `build.ps1 release` -- the laptop builder's entry point (one dedicated clone
# per branch, see SPEC.md section 11 "Laptop channel builds"). Builds BOTH apps' release
# APKs for the channel in BUILD_CHANNEL (dev / staging / main; unset = main)
# with versionCode BUILD_NUMBER (used as is: minutes since 2020-01-01 UTC of
# the source commit, computed by the builder) into github_releases/<channel>/
# (newest 2 per app kept). Every channel builds the same app (same id and
# name; only the tag, release and folder carry the channel). With PUBLISH=1
# it commits and pushes that folder to the branch
# ([skip ci], so it doesn't trigger another build), then publishes one GitHub
# release per app (tool/publish_apk.dart). Nothing else is committed: no
# version bumps, no changelog build notes. An app whose release for this
# exact build already exists is skipped; the other one is still built. When
# HEAD only changes github_releases/ (this script's own commit), the build is
# for the commit below it (Get-SourceCommit). Exits non-zero if any app
# failed.
function Get-KeyProperties {
  $path = "android/key.properties"
  if (-not (Test-Path -LiteralPath $path)) {
    throw "release mode needs android/key.properties (the upload key) -- refusing to build a debug-signed APK"
  }
  $props = @{}
  foreach ($line in Get-Content -LiteralPath $path) {
    if ($line -match '^\s*([^#=]+?)\s*=\s*(.*?)\s*$') {
      $props[$Matches[1]] = $Matches[2]
    }
  }
  foreach ($key in @("storeFile", "storePassword", "keyAlias", "keyPassword")) {
    if ([string]::IsNullOrWhiteSpace($props[$key])) {
      throw "android/key.properties has no $key -- refusing to build a debug-signed APK"
    }
  }
  $store = $props["storeFile"]
  # Gradle resolves a relative storeFile against android/app.
  if (-not [System.IO.Path]::IsPathRooted($store)) {
    $store = Join-Path "android/app" $store
  }
  if (-not (Test-Path -LiteralPath $store)) {
    throw "keystore $($props['storeFile']) (from android/key.properties) not found"
  }
}

function Invoke-ChannelRelease {
  $channel = if ([string]::IsNullOrWhiteSpace($env:BUILD_CHANNEL)) { "main" } else { $env:BUILD_CHANNEL.Trim().ToLower() }
  if (@("main", "staging", "dev") -notcontains $channel) {
    throw "BUILD_CHANNEL must be dev, staging or main (got '$channel')"
  }
  $env:BUILD_CHANNEL = $channel
  $buildNumber = "$env:BUILD_NUMBER".Trim()
  if ($buildNumber -ne "" -and $buildNumber -notmatch '^\d+$') {
    throw "BUILD_NUMBER must be an integer (got '$buildNumber')"
  }
  $publish = ($env:PUBLISH -eq "1")
  $sha = Get-SourceCommit "github_releases"
  $head = (& git rev-parse HEAD).Trim()
  # BUILD_NUMBER is already the source commit's number (the builder skips
  # these APK commits itself), so it is used as is.
  if ($sha -ne $head) {
    Write-Host "==> HEAD only changes github_releases/; building $($sha.Substring(0, 7)) below it"
  }
  $branch = "$env:BUILD_BRANCH".Trim()
  if ($branch -eq "") { $branch = (& git rev-parse --abbrev-ref HEAD).Trim() }
  if ($branch -eq "" -or $branch -eq "HEAD") { $branch = $channel }

  Get-KeyProperties
  # Belt and braces: android/app/build.gradle.kts fails the build instead of
  # falling back to the debug key when this is set.
  $env:REQUIRE_RELEASE_KEY = "1"

  $apps = @(
    @{ Flavor = "todo"; Name = "BestToDo"; Asset = "BestToDo"; VersionFile = "pubspec.yaml"; Args = @("--flavor", "todo") },
    @{ Flavor = "music"; Name = "Best Music"; Asset = "BestMusic"; VersionFile = "MUSIC_VERSION"; Args = @("--flavor", "music", "-t", "lib/main_music.dart") }
  )
  $numberArgs = @()
  if ($buildNumber -ne "") { $numberArgs = @("--build-number", $buildNumber) }

  Write-Host "==> release: channel=$channel build=$(if ($buildNumber) { $buildNumber } else { '(version files)' }) publish=$publish"

  $todo = @()
  foreach ($app in $apps) {
    if ($publish) {
      & dart run tool/publish_apk.dart --app $app.Flavor --channel $channel @numberArgs --exists
      $status = $LASTEXITCODE
      if ($status -eq 0) {
        Write-Host "    $($app.Name): release for this build already exists -- skipping"
        continue
      }
      if ($status -ne 2) {
        throw "could not check for an existing $($app.Name) release (exit $status)"
      }
    }
    $todo += $app
  }
  if ($todo.Count -eq 0) {
    Write-Host "==> nothing to do: every app's release for this build exists"
    return
  }

  # Same preflight as every other build: newest CI test report packaged into
  # the APK + a quick smoke test.
  if ($env:SKIP_PREFLIGHT -ne "1") {
    Invoke-Checked "dart" @("run", "tool/pull_test_report.dart")
    Invoke-Checked "flutter" @("test", "test/core/build_smoke_test.dart")
  }

  $failed = @()
  $built = @()
  $keep = 2
  foreach ($app in $todo) {
    $flavor = $app.Flavor
    try {
      $apk = "build/app/outputs/flutter-apk/app-$flavor-release.apk"
      # Never pick up a previous build's leftover (see build.gradle.kts).
      if (Test-Path -LiteralPath $apk) { Remove-Item -LiteralPath $apk -Force }

      $flutterArgs = @("build", "apk", "--release") + $app.Args +
        @("--dart-define=BUILD_CHANNEL=$channel")
      if ($buildNumber -ne "") {
        $flutterArgs += @("--build-number=$buildNumber", "--dart-define=BUILD_NUMBER=$buildNumber")
      }
      Write-Host "==> flutter $($flutterArgs -join ' ')"
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      & flutter @flutterArgs
      $status = $LASTEXITCODE
      $sw.Stop()
      if ($status -ne 0) { throw "flutter build failed (exit $status)" }
      if (-not (Test-Path -LiteralPath $apk)) { throw "build produced no $apk" }
      $seconds = [int][Math]::Round($sw.Elapsed.TotalSeconds)

      # Every build lands in github_releases/<channel>/ (one folder per
      # channel, so merging dev -> staging -> main never conflicts there),
      # named like its release asset. Only the newest $keep APKs per app
      # stay; older ones remain on the GitHub releases.
      $suffix = if ($channel -eq "main") { "" } else { "-$channel" }
      $line = Select-String -Path $app.VersionFile -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)' |
        Select-Object -First 1
      $name = $line.Matches[0].Groups[1].Value
      $number = if ($buildNumber -ne "") { $buildNumber } else { $line.Matches[0].Groups[2].Value }
      $dir = Join-Path "github_releases" $channel
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      $out = Join-Path $dir "$($app.Asset)-$name+$number$suffix.apk"
      Copy-Item -LiteralPath $apk -Destination $out -Force
      Get-ChildItem (Join-Path $dir "$($app.Asset)-*.apk") |
        Sort-Object { [int]([regex]::Match($_.BaseName, '\+([0-9]+)').Groups[1].Value) } -Descending |
        Select-Object -Skip $keep |
        Remove-Item -Force
      Write-Host "    built $out in ${seconds}s"
      $built += @{ App = $app; Apk = $out; Seconds = $seconds }
    } catch {
      Write-Warning "$($app.Name): $_"
      $failed += $app.Name
    }
  }

  if (-not $publish) {
    Write-Host "    PUBLISH is not 1: nothing committed or published"
  } elseif ($built.Count -gt 0) {
    # Commit the APKs to the branch before releasing: if the push fails,
    # nothing is released and the next run of this build does both.
    Invoke-Checked "git" @("add", "-A", "--", (Join-Path "github_releases" $channel))
    if ((Test-Native "git" @("diff", "--cached", "--quiet")) -ne 0) {
      $names = ($built | ForEach-Object { $_.App.Name }) -join " + "
      Invoke-Checked "git" @("commit", "-q", "-m", "build: $names $buildNumber ($channel) [skip ci]")
      Invoke-Checked "git" @("pull", "--rebase", "--autostash", "-q", "origin", $branch)
      Invoke-Checked "git" @("push", "-q", "origin", "HEAD:refs/heads/$branch")
    }
    foreach ($b in $built) {
      try {
        Invoke-Checked "dart" (@("run", "tool/publish_apk.dart", "--app", $b.App.Flavor,
          "--channel", $channel, "--apk", $b.Apk, "--target", $sha,
          "--duration", "$($b.Seconds)") + $numberArgs)
      } catch {
        Write-Warning "$($b.App.Name): $_"
        $failed += $b.App.Name
      }
    }
  }

  if ($failed.Count -gt 0) {
    Write-Error "release failed for: $($failed -join ', ')"
    exit 1
  }
}

Set-Location (Get-RepoRoot)

if ($BuildArgs.Count -gt 0 -and $BuildArgs[0] -eq "release") {
  # The laptop builder's channel build (see Invoke-ChannelRelease).
  Invoke-ChannelRelease
} elseif ($BuildArgs.Count -gt 0 -and $BuildArgs[0] -eq "all") {
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
