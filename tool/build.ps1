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

function Get-PubspecVersion {
  $versionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:" | Select-Object -First 1
  if ($null -eq $versionLine) {
    throw "Could not find version: in pubspec.yaml"
  }
  return (($versionLine.Line -split "\s+", 2)[1]).Trim()
}

function Test-IsCacheableReleaseBuild {
  param([string[]]$ArgsForFlutter)

  if ($ArgsForFlutter.Count -eq 0) {
    return $false
  }

  if ($ArgsForFlutter.Count -gt 1) {
    foreach ($arg in $ArgsForFlutter[1..($ArgsForFlutter.Count - 1)]) {
      if ($arg -ne "--release") {
        return $false
      }
    }
  }
  return $true
}

function Get-ExistingBuildArtifact {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string[]]$ArgsForFlutter = @()
  )

  if ($env:FORCE_BUILD -eq "1" -or -not (Test-IsCacheableReleaseBuild $ArgsForFlutter)) {
    return $null
  }

  $target = if ($ArgsForFlutter.Count -gt 0) { $ArgsForFlutter[0] } else { "" }
  $candidates = switch ($target) {
    "apk" {
      @(
        "github_releases/best_todo_$Version.apk",
        "build/app/outputs/flutter-apk/best_todo_$Version.apk"
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

  $version = Get-PubspecVersion
  $existingArtifact = Get-ExistingBuildArtifact -Version $version -ArgsForFlutter $ArgsForFlutter
  if ($null -ne $existingArtifact) {
    Write-Host "==> existing release build found: $existingArtifact"
    Write-Host "    skipping flutter build (set FORCE_BUILD=1 to rebuild)"

    if ($ArgsForFlutter.Count -gt 0 -and $ArgsForFlutter[0] -eq "apk" -and
        $existingArtifact -like "build/app/outputs/flutter-apk/*") {
      Invoke-Checked "dart" @("run", "tool/stage_local_release.dart", "--apk", $existingArtifact)
    }
    return
  }

  if ($env:SKIP_PREFLIGHT -ne "1") {
    Invoke-Checked "dart" @("run", "tool/pull_test_report.dart")
    Invoke-Checked "flutter" @("test", "test/core/build_smoke_test.dart")
  }

  & flutter @("build") @ArgsForFlutter
  $buildStatus = $LASTEXITCODE

  if ($buildStatus -eq 0) {
    Invoke-Checked "dart" @("run", "tool/append_build_time.dart")
  } else {
    Write-Error "flutter build $($ArgsForFlutter -join ' ') failed (status $buildStatus)"
    exit $buildStatus
  }

  Rename-IfExists `
    "build/app/outputs/flutter-apk/app-release.apk" `
    "build/app/outputs/flutter-apk/best_todo_$version.apk"

  $apkPath = "build/app/outputs/flutter-apk/best_todo_$version.apk"
  if (Test-Path -LiteralPath $apkPath) {
    Invoke-Checked "dart" @("run", "tool/stage_local_release.dart", "--apk", $apkPath)
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
}

function Invoke-BuildAll {
  param([string[]]$ArgsForTargets)

  if ($ArgsForTargets.Count -eq 0) {
    $ArgsForTargets = @("--release")
  }

  $windowsStatus = "skipped"
  $androidStatus = "skipped"

  if ($env:ANDROID -ne "0") {
    Write-Host "==> flutter build apk $($ArgsForTargets -join ' ')"
    Invoke-SingleBuild (@("apk") + $ArgsForTargets)
    $androidStatus = "ok"
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

    Write-Host "==> syncing github_releases/ + CHANGELOG.md on $branch"
    Invoke-Checked "git" @("add", "github_releases", "CHANGELOG.md")

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
} else {
  Invoke-SingleBuild $BuildArgs
}
