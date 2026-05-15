# ============================================================================
# Telegram Bot API Complete Auto Builder for Windows Sandbox
# Downloads, installs all dependencies, and builds everything automatically
# Run this and leave it overnight
# ============================================================================

$ErrorActionPreference = "Continue"
$BUILD_DIR = "C:\Build"
$EXPORT_DIR = "C:\Export"
$TEMP_DIR = $env:TEMP

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Telegram Bot API Complete Builder" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------------------
# Function to check command success
# ----------------------------------------------------------------------------
function Test-CommandResult {
    param($LastExitCode, $ErrorMessage)
    if ($LastExitCode -ne 0) {
        Write-Host "ERROR: $ErrorMessage (exit code $LastExitCode)" -ForegroundColor Red
        exit 1
    }
}

# ----------------------------------------------------------------------------
# STEP 1: Install Git (Dynamic Version)
# ----------------------------------------------------------------------------
Write-Host "[1/12] Fetching and Installing latest Git..." -ForegroundColor Yellow
$gitInstaller = "$TEMP_DIR\git-installer.exe"

# Получаем ссылку на актуальный 64-bit exe через GitHub API
$gitRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest"
$gitDownloadUrl = ($gitRelease.assets | Where-Object { $_.name -match "64-bit.exe" -and $_.name -notmatch "pdbs" }).browser_download_url

Write-Host "  [INFO] Downloading: $gitDownloadUrl" -ForegroundColor Gray
Invoke-WebRequest -Uri $gitDownloadUrl -OutFile $gitInstaller

Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP-" -Wait
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Write-Host "  [OK] Git installed" -ForegroundColor Green

# ----------------------------------------------------------------------------
# STEP 2: Install CMake (Dynamic Version)
# ----------------------------------------------------------------------------
Write-Host "[2/12] Fetching and Installing latest CMake..." -ForegroundColor Yellow
$cmakeInstaller = "$TEMP_DIR\cmake-installer.msi"

# Получаем ссылку на актуальный windows-x86_64.msi
$cmakeRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Kitware/CMake/releases/latest"
$cmakeDownloadUrl = ($cmakeRelease.assets | Where-Object { $_.name -match "windows-x86_64.msi" }).browser_download_url

Write-Host "  [INFO] Downloading: $cmakeDownloadUrl" -ForegroundColor Gray
Invoke-WebRequest -Uri $cmakeDownloadUrl -OutFile $cmakeInstaller

Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$cmakeInstaller`" /quiet /norestart ADD_CMAKE_TO_PATH=System" -Wait
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Write-Host "  [OK] CMake installed" -ForegroundColor Green

# ----------------------------------------------------------------------------
# STEP 3: Install Visual Studio Build Tools
# ----------------------------------------------------------------------------
Write-Host "[3/12] Installing Visual Studio Build Tools (15-25 min)..." -ForegroundColor Yellow
$vsInstaller = "$TEMP_DIR\vs_buildtools.exe"
Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_buildtools.exe" -OutFile $vsInstaller
Start-Process -FilePath $vsInstaller -ArgumentList "--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows10SDK.19041" -Wait
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Write-Host "  [OK] VS Build Tools installed" -ForegroundColor Green

# ----------------------------------------------------------------------------
# STEP 4: Setup MSVC PATH
# ----------------------------------------------------------------------------
Write-Host "[4/12] Setting up MSVC compiler PATH..." -ForegroundColor Yellow
$vsPath = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
if ($vsPath) {
    $vcPath = "$vsPath\VC\Tools\MSVC"
    $clPath = Get-ChildItem -Path $vcPath -Directory | Select-Object -First 1 -ExpandProperty FullName
    $clBinPath = "$clPath\bin\Hostx64\x64"
    $env:Path = "$clBinPath;" + $env:Path
    Write-Host "  [OK] MSVC configured" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] VS Build Tools not found" -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------------------------------
# STEP 5: Create directories
# ----------------------------------------------------------------------------
Write-Host "[5/12] Creating directories..." -ForegroundColor Yellow
if (!(Test-Path $BUILD_DIR)) { mkdir $BUILD_DIR }
if (!(Test-Path $EXPORT_DIR)) { mkdir $EXPORT_DIR }
Write-Host "  [OK] Directories created" -ForegroundColor Green

# ----------------------------------------------------------------------------
# STEP 6: Clone telegram-bot-api
# ----------------------------------------------------------------------------
Write-Host "[6/12] Cloning telegram-bot-api..." -ForegroundColor Yellow
Set-Location $BUILD_DIR
if (!(Test-Path "telegram-bot-api")) {
    git clone --recursive https://github.com/tdlib/telegram-bot-api.git
    Test-CommandResult $LASTEXITCODE "Git clone telegram-bot-api failed"
} else {
    Write-Host "  [OK] Already cloned" -ForegroundColor Green
}
Set-Location telegram-bot-api

# ----------------------------------------------------------------------------
# STEP 7: Clone vcpkg
# ----------------------------------------------------------------------------
Write-Host "[7/12] Cloning vcpkg..." -ForegroundColor Yellow
if (!(Test-Path "vcpkg")) {
    git clone https://github.com/Microsoft/vcpkg.git
    Test-CommandResult $LASTEXITCODE "Git clone vcpkg failed"
} else {
    Write-Host "  [OK] Already cloned" -ForegroundColor Green
}
Set-Location vcpkg

# ----------------------------------------------------------------------------
# STEP 8: Bootstrap vcpkg
# ----------------------------------------------------------------------------
Write-Host "[8/12] Bootstrapping vcpkg..." -ForegroundColor Yellow
.\bootstrap-vcpkg.bat -disableMetrics
Test-CommandResult $LASTEXITCODE "vcpkg bootstrap failed"
Write-Host "  [OK] vcpkg ready" -ForegroundColor Green

# ----------------------------------------------------------------------------
# STEP 9: Create static linkage triplet
# ----------------------------------------------------------------------------
Write-Host "[9/12] Creating x64-windows-static triplet..." -ForegroundColor Yellow
if (!(Test-Path "triplets\community")) { mkdir triplets\community }
@"
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE static)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Windows)
"@ | Out-File -FilePath "triplets\community\x64-windows-static.cmake" -Encoding UTF8
Write-Host "  [OK] Triplet created" -ForegroundColor Green

# ----------------------------------------------------------------------------
# STEP 10: Install dependencies (LONGEST STEP - 30-60 min)
# ----------------------------------------------------------------------------
Write-Host "[10/12] Installing dependencies via vcpkg (30-60 min)..." -ForegroundColor Yellow
Write-Host "  [INFO] This will take a while, you can sleep now..." -ForegroundColor Cyan
.\vcpkg.exe install gperf:x64-windows-static openssl:x64-windows-static zlib:x64-windows-static --recurse
Test-CommandResult $LASTEXITCODE "vcpkg install failed"
Write-Host "  [OK] Dependencies installed" -ForegroundColor Green

# ----------------------------------------------------------------------------
# STEP 11: CMake configuration and Build
# ----------------------------------------------------------------------------
Write-Host "[11/12] Configuring CMake and building (40-60 min)..." -ForegroundColor Yellow
Set-Location ..
if (Test-Path "build") { Remove-Item build -Force -Recurse }
mkdir build
Set-Location build

cmake -A x64 `
  -DCMAKE_INSTALL_PREFIX:PATH=.. `
  -DCMAKE_TOOLCHAIN_FILE:FILEPATH=../vcpkg/scripts/buildsystems/vcpkg.cmake `
  -DVCPKG_TARGET_TRIPLET:STRING=x64-windows-static `
  -DCMAKE_BUILD_TYPE:STRING=Release `
  ..
Test-CommandResult $LASTEXITCODE "CMake configuration failed"

cmake --build . --target install --config Release -- /m:1
Test-CommandResult $LASTEXITCODE "Build failed"
Write-Host "  [OK] Build completed" -ForegroundColor Green

# ----------------------------------------------------------------------------
# STEP 12: Export result
# ----------------------------------------------------------------------------
Write-Host "[12/12] Exporting result..." -ForegroundColor Yellow
if (Test-Path "..\bin\telegram-bot-api.exe") {
    Copy-Item "..\bin\telegram-bot-api.exe" $EXPORT_DIR\
    Write-Host "  [OK] File exported to $EXPORT_DIR" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] File not found!" -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------------------------------
# Completion
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "BUILD SUCCESSFULLY COMPLETED!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Result: $EXPORT_DIR\telegram-bot-api.exe" -ForegroundColor Cyan
Write-Host ""
Write-Host "To run on host machine:" -ForegroundColor Yellow
Write-Host "  telegram-bot-api.exe --api-id=YOUR_ID --api-hash=YOUR_HASH --local" -ForegroundColor White
Write-Host ""
Write-Host "Drag the file from Sandbox to your host machine!" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total time: approximately 2-3 hours" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press any key to close..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")