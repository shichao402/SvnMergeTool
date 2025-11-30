@echo off
REM SVN Auto Merge Tool - Deploy Script (Windows)
REM 
REM Deploy Flutter app to target platform
REM Features:
REM - Check Flutter environment
REM - Build application
REM - Install to device
REM - Launch application

setlocal enabledelayedexpansion

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."

echo ========================================
echo   SVN Auto Merge Tool - Deploy Script
echo ========================================
echo.

REM Change to project directory
cd /d "%PROJECT_DIR%"

REM Check Flutter environment
echo Checking Flutter environment...
where flutter >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Flutter CLI not found
    echo Please ensure Flutter is installed and added to PATH
    exit /b 1
)

for /f "tokens=*" %%i in ('flutter --version ^| findstr /r "^Flutter"') do set FLUTTER_VERSION=%%i
echo [OK] Flutter environment is ready
echo   %FLUTTER_VERSION%

REM Check Flutter devices
echo.
echo Checking available devices...
for /f %%i in ('flutter devices --machine 2^>nul ^| findstr /c:"deviceId"') do set /a DEVICES+=1
if not defined DEVICES set DEVICES=0

if %DEVICES% equ 0 (
    echo [WARNING] No available devices detected
    echo For Windows desktop app, we will build only (no install/run needed)
    set BUILD_ONLY=true
) else (
    echo [OK] Detected %DEVICES% available device(s)
    set BUILD_ONLY=false
)

echo.
echo Target platform: windows

REM Clean previous build
echo.
echo Cleaning previous build...
flutter clean 2>&1
set CLEAN_ERROR=%errorlevel%
if %CLEAN_ERROR% neq 0 (
    echo [WARNING] Clean failed, continuing
) else (
    echo [OK] Clean completed
)

REM Sync version number
echo.
echo Syncing version number...
if exist "%SCRIPT_DIR%version.bat" (
    call "%SCRIPT_DIR%version.bat" sync app 2>nul
    if %errorlevel% neq 0 (
        echo [WARNING] Version sync failed, continuing
    ) else (
        echo [OK] Version synced
    )
) else (
    echo [WARNING] Version management script not found, skipping version sync
)

REM Get dependencies
echo.
echo Getting dependencies...
flutter pub get 2>&1
set DEPS_ERROR=%errorlevel%
if %DEPS_ERROR% neq 0 (
    echo [ERROR] Failed to get dependencies
    exit /b 1
)
echo [OK] Dependencies retrieved

REM Build application
echo.
echo Building application...
flutter build windows --debug 2>&1
set BUILD_ERROR=%errorlevel%
if %BUILD_ERROR% neq 0 (
    echo [ERROR] Build failed
    exit /b 1
)
echo [OK] Build completed

REM Copy config file to build output directory
set "CONFIG_DIR=build\windows\x64\runner\Debug\config"
if exist "%PROJECT_DIR%\config\source_urls.json" (
    if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
    copy /Y "%PROJECT_DIR%\config\source_urls.json" "%CONFIG_DIR%\" >nul
    echo [OK] Config file copied to build output
) else (
    echo [WARNING] Config file not found: %PROJECT_DIR%\config\source_urls.json
)

echo.
echo Application location:
echo   build\windows\x64\runner\Debug\SvnMergeTool.exe
echo Config file location:
echo   %CONFIG_DIR%\source_urls.json

REM Exit if build only
if "%BUILD_ONLY%"=="true" (
    echo.
    echo [OK] Build completed!
    exit /b 0
)

REM Install to device
echo.
echo Installing to device...
flutter install
if %errorlevel% neq 0 (
    echo [WARNING] Install failed, but continuing
)
echo [OK] Install completed

REM Launch application
echo.
echo Launching application...
flutter run
if %errorlevel% neq 0 (
    echo [WARNING] Application launch failed
    exit /b 1
)
echo [OK] Application launched

echo.
echo ========================================
echo   Deployment completed!
echo ========================================
echo.

endlocal
