# Builds the Windows app and publishes it as a windows-v<version>-<build> GitHub
# release, which tool\install_agent_desk.ps1 installs on the PCs (SPEC 10.6s).
# The app's updater never offers these: no APK, and another tag prefix.
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $Root

$line = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
$version = $line.Matches[0].Groups[1].Value
$parts = $version -split '\+'
$tag = "windows-v$($parts[0])-$($parts[1])"

& gh release view $tag *> $null
if ($LASTEXITCODE -eq 0) {
  Write-Host "$tag is published already."
  exit 0
}

& flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed." }

$release = "build\windows\x64\runner\Release"
$stage = "build\windows\BestToDo-$($parts[0])-win64"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
# The build folder also keeps a copy of the exe per old version; not those.
Get-ChildItem $release | Where-Object { $_.Name -notlike "BestToDo-*.exe" } |
  Copy-Item -Destination $stage -Recurse
$zip = "$stage.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip

$notes = "Windows build of BestToDo $($parts[0]). Install or update with: irm https://raw.githubusercontent.com/Mfficiency/best_todo_2/dev/tool/install_agent_desk.ps1 | iex"
& gh release create $tag $zip --title "BestToDo Windows $($parts[0])" --notes $notes --latest=false --target (git rev-parse HEAD)
if ($LASTEXITCODE -ne 0) { throw "gh release create failed." }
Write-Host "Published $tag."
