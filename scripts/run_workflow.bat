@echo off
REM GitHub Actions 运行脚本 (Windows)
REM
REM 组合脚本：触发 workflow 并自动监控
REM 功能：
REM - 触发指定的 workflow
REM - 自动监控 workflow 执行状态
REM - 成功或失败时自动退出
REM
REM 使用方法：
REM   scripts\run_workflow.bat <workflow_file> [--ref <ref>] [--input <key=value>]...

setlocal enabledelayedexpansion

REM 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"

REM 触发 workflow
echo ==========================================
echo   Step 1: Trigger Workflow
echo ==========================================
echo.

call "%SCRIPT_DIR%trigger_workflow.bat" %*

if %errorlevel% neq 0 (
    echo Failed to trigger workflow, exiting
    exit /b 1
)

REM 获取 run ID
set "PROJECT_DIR=%SCRIPT_DIR%.."
set "RUN_ID_FILE=%PROJECT_DIR%\.github_run_id.txt"

if not exist "!RUN_ID_FILE!" (
    echo [ERROR] Cannot find run ID file
    exit /b 1
)

set /p RUN_ID=<"!RUN_ID_FILE!"
set "RUN_ID=!RUN_ID: =!"

if "!RUN_ID!"=="" (
    echo [ERROR] Cannot get run ID
    exit /b 1
)

echo.
echo ==========================================
echo   Step 2: Monitor Workflow
echo ==========================================
echo.

REM 监控 workflow
call "%SCRIPT_DIR%monitor_workflow.bat" !RUN_ID!

exit /b %errorlevel%

endlocal

