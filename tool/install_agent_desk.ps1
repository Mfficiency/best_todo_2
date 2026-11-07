# Installs BestToDo on a Windows PC so it opens on the Agent Desk at every logon
# (SPEC 10.6s). No admin rights needed; run it again to update.
#
# On any PC, from the newest published Windows build:
#   irm https://raw.githubusercontent.com/Mfficiency/best_todo_2/dev/tool/install_agent_desk.ps1 | iex
# From a local build (run from the repo):
#   powershell -ExecutionPolicy Bypass -File tool\install_agent_desk.ps1 -Source build\windows\x64\runner\Release
param(
  [string]$Source = "",
  [switch]$NoStart
)

$ErrorActionPreference = "Stop"
$Repo = "Mfficiency/best_todo_2"
$Target = Join-Path $env:LOCALAPPDATA "Programs\BestToDo"
$Exe = Join-Path $Target "BestToDo.exe"
$Temp = $null

try {
  if (-not $Source) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ "User-Agent" = "BestToDo-installer" }
    $releases = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases?per_page=100" -Headers $headers
    $release = $releases | Where-Object { $_.tag_name -like "windows-v*" } | Select-Object -First 1
    if (-not $release) { throw "No windows-v release found in $Repo." }
    $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    if (-not $asset) { throw "Release $($release.tag_name) has no zip." }
    Write-Host "Downloading $($release.tag_name)..."
    $Temp = Join-Path $env:TEMP ("besttodo-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $Temp | Out-Null
    $zip = Join-Path $Temp $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing -Headers $headers
    Expand-Archive $zip -DestinationPath $Temp
    $found = Get-ChildItem $Temp -Recurse -Filter "BestToDo.exe" | Select-Object -First 1
    if (-not $found) { throw "The zip holds no BestToDo.exe." }
    $Source = $found.DirectoryName
  }
  $Source = (Resolve-Path $Source).Path
  if (-not (Test-Path (Join-Path $Source "BestToDo.exe"))) {
    throw "No BestToDo.exe in $Source."
  }

  # A running copy locks its files. Ask it to close first, so it can save.
  $running = Get-Process BestToDo -ErrorAction SilentlyContinue
  if ($running) {
    Write-Host "Closing the running BestToDo..."
    $running | ForEach-Object { [void]$_.CloseMainWindow() }
    $running | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    Get-Process BestToDo -ErrorAction SilentlyContinue | Stop-Process -Force
  }

  # The build folder also keeps a copy of the exe per old version; not those.
  New-Item -ItemType Directory -Path $Target -Force | Out-Null
  Get-ChildItem $Source | Where-Object { $_.Name -notlike "BestToDo-*.exe" } |
    Copy-Item -Destination $Target -Recurse -Force

  $startup = [Environment]::GetFolderPath("Startup")
  $shell = New-Object -ComObject WScript.Shell
  foreach ($folder in @($startup, [Environment]::GetFolderPath("Programs"))) {
    $link = $shell.CreateShortcut((Join-Path $folder "BestToDo Agent Desk.lnk"))
    $link.TargetPath = $Exe
    $link.Arguments = "--desk"
    $link.WorkingDirectory = $Target
    $link.Description = "BestToDo, opens on the Agent Desk"
    $link.Save()
  }

  Write-Host "Installed in $Target. It opens on the Agent Desk at every logon."
  if (-not $NoStart) {
    Start-Process -FilePath $Exe -ArgumentList "--desk" -WorkingDirectory $Target
  }
} finally {
  if ($Temp) { Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}
