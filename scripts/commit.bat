@echo off
REM SVN Auto Merge Tool - Commit Script (Windows)
REM 
REM Commit all local changes and push to remote repository
REM Features:
REM - Add all changed files
REM - Create commit (use COMMIT_MESSAGE environment variable or default message)
REM - Push to remote repository
REM
REM Usage:
REM   scripts\commit.bat                    REM Use default commit message
REM   set COMMIT_MESSAGE=修复bug && scripts\commit.bat  REM Use custom commit message

setlocal enabledelayedexpansion

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."

echo ========================================
echo   SVN Auto Merge Tool - Commit Script
echo ========================================
echo.

REM Change to project directory
cd /d "%PROJECT_DIR%"

REM Check Git environment
echo Checking Git environment...
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Git CLI not found
    echo Please ensure Git is installed and added to PATH
    exit /b 1
)

for /f "tokens=*" %%i in ('git --version') do set GIT_VERSION=%%i
echo [OK] Git environment is ready
echo   %GIT_VERSION%

REM Check if in Git repository
git rev-parse --git-dir >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Current directory is not a Git repository
    exit /b 1
)

REM Check for changed files
echo.
echo Checking changed files...
git add -A

REM Check if there are any staged files
set "HAS_FILES=0"
for /f "tokens=*" %%i in ('git diff --cached --name-only 2^>nul') do (
    set "HAS_FILES=1"
    goto :has_files_found
)

:has_files_found
if !HAS_FILES! equ 0 (
    echo [WARNING] No files to commit
    echo Working directory is clean, no commit needed
    exit /b 0
)

echo [OK] Files to be committed:
for /f "tokens=*" %%i in ('git diff --cached --name-only 2^>nul') do (
    echo   - %%i
)

REM Generate commit message
if defined COMMIT_MESSAGE (
    set "MESSAGE=!COMMIT_MESSAGE!"
    echo.
    echo Using custom commit message: !MESSAGE!
) else (
    REM Generate default commit message with timestamp
    REM Use PowerShell to get formatted date/time
    for /f "tokens=*" %%i in ('powershell -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss\""') do set TIMESTAMP=%%i
    if not defined TIMESTAMP (
        REM Fallback if PowerShell is not available
        for /f "tokens=2 delims==" %%i in ('wmic os get localdatetime /value') do set DATETIME=%%i
        set "TIMESTAMP=!DATETIME:~0,4!-!DATETIME:~4,2!-!DATETIME:~6,2! !DATETIME:~8,2!:!DATETIME:~10,2!:!DATETIME:~12,2!"
    )
    set "MESSAGE=Auto commit: !TIMESTAMP!"
    echo.
    echo Using default commit message: !MESSAGE!
)

REM Create commit
echo.
echo Creating commit...
git commit -m "!MESSAGE!" --no-verify
if %errorlevel% neq 0 (
    echo [ERROR] Commit creation failed
    exit /b 1
)
echo [OK] Commit created successfully

REM Get current branch
for /f "tokens=*" %%i in ('git branch --show-current') do set CURRENT_BRANCH=%%i
echo.
echo Current branch: !CURRENT_BRANCH!

REM Check remote repository
echo.
echo Checking remote repository...
for /f "tokens=*" %%i in ('git remote') do (
    set REMOTE=%%i
    goto :found_remote
)
echo [WARNING] No remote repository configured
echo Skipping push operation
exit /b 0

:found_remote
for /f "tokens=*" %%i in ('git remote get-url !REMOTE! 2^>nul') do set REMOTE_URL=%%i
if not defined REMOTE_URL set REMOTE_URL=Not configured
echo [OK] Remote repository: !REMOTE! ^(!REMOTE_URL!^)

REM Push to remote repository
echo.
echo Pushing to remote repository...
git push !REMOTE! !CURRENT_BRANCH!
if %errorlevel% neq 0 (
    echo [ERROR] Push failed
    echo Please check network connection and remote repository permissions
    exit /b 1
)
echo [OK] Push completed successfully

echo.
echo ========================================
echo   Commit and push completed!
echo ========================================
echo.

endlocal

