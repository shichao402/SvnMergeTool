@echo off
REM GitHub Actions 触发脚本 (Windows)
REM
REM 用于触发 GitHub Actions workflow 并获取 run ID
REM 功能：
REM - 触发指定的 workflow
REM - 传递输入参数
REM - 获取并保存 run ID
REM
REM 使用方法：
REM   scripts\trigger_workflow.bat <workflow_file> [--ref <ref>] [--input <key=value>]...
REM
REM 示例：
REM   scripts\trigger_workflow.bat .github\workflows\build.yml --ref main --input version=1.0.7

setlocal enabledelayedexpansion

REM 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."

REM 切换到项目目录
cd /d "%PROJECT_DIR%"

REM 检查 GitHub CLI
where gh >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] GitHub CLI (gh) not found
    echo Please install GitHub CLI: https://cli.github.com/
    exit /b 1
)

REM 检查是否已登录
gh auth status >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] GitHub CLI not authenticated
    echo Please run: gh auth login
    exit /b 1
)

REM 解析参数
set "WORKFLOW_FILE="
set "REF="
set "INPUT_ARGS="
set "PARSE_INPUT=0"

:parse_args
if "%~1"=="" goto args_done
if "%~1"=="--ref" (
    set "REF=%~2"
    shift
    shift
    goto parse_args
)
if "%~1"=="--input" (
    set "INPUT_ARGS=%INPUT_ARGS% --input %~2"
    shift
    shift
    goto parse_args
)
if "!WORKFLOW_FILE!"=="" (
    set "WORKFLOW_FILE=%~1"
)
shift
goto parse_args

:args_done

REM 检查必需参数
if "!WORKFLOW_FILE!"=="" (
    echo [ERROR] Workflow file must be specified
    echo.
    echo Usage:
    echo   %0 ^<workflow_file^> [--ref ^<ref^>] [--input ^<key=value^>]...
    echo.
    echo Example:
    echo   %0 .github\workflows\build.yml --ref main --input version=1.0.7
    exit /b 1
)

REM 检查 workflow 文件是否存在
if not exist "!WORKFLOW_FILE!" (
    echo [ERROR] Workflow file not found: !WORKFLOW_FILE!
    exit /b 1
)

REM 获取仓库信息
for /f "tokens=*" %%i in ('gh repo view --json nameWithOwner -q .nameWithOwner 2^>nul') do set "REPO=%%i"
if "!REPO!"=="" (
    echo [ERROR] Cannot get repository information
    echo Please ensure current directory is a Git repository with GitHub remote configured
    exit /b 1
)

REM 获取 workflow ID（从文件名提取）
for %%F in ("!WORKFLOW_FILE!") do set "WORKFLOW_ID=%%~nF"

REM 如果没有指定 ref，使用当前分支
if "!REF!"=="" (
    for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "REF=%%i"
    if "!REF!"=="" set "REF=main"
)

echo ========================================
echo   Trigger GitHub Actions Workflow
echo ========================================
echo.
echo Repository: !REPO!
echo Workflow: !WORKFLOW_FILE!
echo Workflow ID: !WORKFLOW_ID!
echo Ref: !REF!
if not "!INPUT_ARGS!"=="" (
    echo Input parameters: !INPUT_ARGS!
)
echo.

REM 构建 gh workflow run 命令
set "CMD=gh workflow run "!WORKFLOW_ID!" --ref "!REF!"!INPUT_ARGS!"

REM 触发 workflow
echo Triggering workflow...
!CMD!
if %errorlevel% neq 0 (
    echo [ERROR] Failed to trigger workflow
    exit /b 1
)
echo [OK] Workflow triggered

REM 等待几秒让 workflow 启动
echo Waiting for workflow to start...
timeout /t 3 /nobreak >nul

REM 获取最新的 run ID
echo Getting run ID...
set "MAX_ATTEMPTS=10"
set "ATTEMPT=0"
set "RUN_ID="

:get_run_id
set /a ATTEMPT+=1
if !ATTEMPT! gtr !MAX_ATTEMPTS! goto run_id_failed

for /f "tokens=*" %%i in ('gh run list --workflow="!WORKFLOW_ID!" --limit 1 --json databaseId -q ".[0].databaseId" 2^>nul') do set "RUN_ID=%%i"

if not "!RUN_ID!"=="" if not "!RUN_ID!"=="null" goto run_id_success

echo   Attempt !ATTEMPT!/!MAX_ATTEMPTS!...
timeout /t 2 /nobreak >nul
goto get_run_id

:run_id_failed
echo [WARNING] Cannot get run ID
echo Please check GitHub Actions page manually to get run ID
exit /b 1

:run_id_success
REM 保存 run ID 到文件
set "RUN_ID_FILE=%PROJECT_DIR%\.github_run_id.txt"
echo !RUN_ID! > "!RUN_ID_FILE!"
echo [OK] Run ID saved: !RUN_ID!
echo Run ID file: !RUN_ID_FILE!

REM 显示 run 信息
echo.
echo Run information:
gh run view !RUN_ID! --json status,conclusion,url -q "状态: {.status}\n结论: {.conclusion // \"运行中\"}\nURL: {.url}" 2>nul

echo.
echo ========================================
echo   Trigger completed!
echo ========================================
echo.
echo Use the following command to monitor workflow:
echo   scripts\monitor_workflow.bat !RUN_ID!
echo.

endlocal

