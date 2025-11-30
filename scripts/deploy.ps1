# SVN Auto Merge Tool - Deploy Script (PowerShell)
# 
# Deploy Flutter app to target platform
# Features:
# - Check Flutter environment
# - Build application
# - Install to device
# - Launch application

$ErrorActionPreference = "Stop"

# Get script directory
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = Split-Path -Parent $SCRIPT_DIR

Write-Host "========================================" -ForegroundColor Green
Write-Host "  SVN Auto Merge Tool - Deploy Script" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Change to project directory
Set-Location $PROJECT_DIR

# Check Flutter environment
Write-Host "Checking Flutter environment..." -ForegroundColor Cyan
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter CLI not found"
    }
    Write-Host "[OK] Flutter environment is ready" -ForegroundColor Green
    Write-Host "  $flutterVersion" -ForegroundColor Gray
} catch {
    Write-Host "[ERROR] Flutter CLI not found" -ForegroundColor Red
    Write-Host "Please ensure Flutter is installed and added to PATH" -ForegroundColor Yellow
    exit 1
}

# Check Flutter devices
Write-Host ""
Write-Host "Checking available devices..." -ForegroundColor Cyan
$devicesOutput = flutter devices --machine 2>&1
$deviceCount = ($devicesOutput | Select-String -Pattern '"deviceId"' | Measure-Object).Count

if ($deviceCount -eq 0) {
    Write-Host "[WARNING] No available devices detected" -ForegroundColor Yellow
    Write-Host "For Windows desktop app, we will build only (no install/run needed)" -ForegroundColor Yellow
    $BUILD_ONLY = $true
} else {
    Write-Host "[OK] Detected $deviceCount available device(s)" -ForegroundColor Green
    $BUILD_ONLY = $false
}

Write-Host ""
Write-Host "Target platform: windows" -ForegroundColor Cyan

# Clean previous build
Write-Host ""
Write-Host "Cleaning previous build..." -ForegroundColor Cyan
flutter clean 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARNING] Clean failed, continuing" -ForegroundColor Yellow
} else {
    Write-Host "[OK] Clean completed" -ForegroundColor Green
}

# Sync version number
Write-Host ""
Write-Host "Syncing version number..." -ForegroundColor Cyan
if (Test-Path "$SCRIPT_DIR\version.ps1") {
    & "$SCRIPT_DIR\version.ps1" sync app 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARNING] Version sync failed, continuing" -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Version synced" -ForegroundColor Green
    }
} elseif (Test-Path "$SCRIPT_DIR\version.bat") {
    & cmd /c "$SCRIPT_DIR\version.bat" sync app 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARNING] Version sync failed, continuing" -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Version synced" -ForegroundColor Green
    }
} else {
    Write-Host "[WARNING] Version management script not found, skipping version sync" -ForegroundColor Yellow
}

# Get dependencies
Write-Host ""
Write-Host "Getting dependencies..." -ForegroundColor Cyan
flutter pub get 2>&1 | Write-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to get dependencies" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Dependencies retrieved" -ForegroundColor Green

# Build application
Write-Host ""
Write-Host "Building application..." -ForegroundColor Cyan
flutter build windows --debug 2>&1 | Write-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Build failed" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Build completed" -ForegroundColor Green

# Copy config file to build output directory
$CONFIG_DIR = "build\windows\x64\runner\Debug\config"
if (Test-Path "$PROJECT_DIR\config\source_urls.json") {
    if (-not (Test-Path $CONFIG_DIR)) {
        New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null
    }
    Copy-Item "$PROJECT_DIR\config\source_urls.json" "$CONFIG_DIR\" -Force
    Write-Host "[OK] Config file copied to build output" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Config file not found: $PROJECT_DIR\config\source_urls.json" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Application location:" -ForegroundColor Cyan
Write-Host "  build\windows\x64\runner\Debug\SvnMergeTool.exe" -ForegroundColor Gray
Write-Host "Config file location:" -ForegroundColor Cyan
Write-Host "  $CONFIG_DIR\source_urls.json" -ForegroundColor Gray

# Exit if build only
if ($BUILD_ONLY) {
    Write-Host ""
    Write-Host "[OK] Build completed!" -ForegroundColor Green
    exit 0
}

# Install to device
Write-Host ""
Write-Host "Installing to device..." -ForegroundColor Cyan
flutter install 2>&1 | Write-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARNING] Install failed, but continuing" -ForegroundColor Yellow
} else {
    Write-Host "[OK] Install completed" -ForegroundColor Green
}

# Launch application
Write-Host ""
Write-Host "Launching application..." -ForegroundColor Cyan
flutter run 2>&1 | Write-Host
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARNING] Application launch failed" -ForegroundColor Yellow
    exit 1
}
Write-Host "[OK] Application launched" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Deployment completed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""



