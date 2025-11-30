@echo off
REM GitHub Actions 监控脚本 (Windows)
REM
REM 用于监控 GitHub Actions workflow 运行状态
REM 功能：
REM - 持续监控 workflow 状态
REM - 每5秒查询一次状态
REM - 成功时退出
REM - 失败时获取错误日志
REM
REM 使用方法：
REM   scripts\monitor_workflow.bat [run_id]
REM
REM 如果不提供 run_id，将从 .github_run_id.txt 文件读取

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

REM 获取 run ID
set "RUN_ID=%~1"
if "!RUN_ID!"=="" (
    set "RUN_ID_FILE=%PROJECT_DIR%\.github_run_id.txt"
    if exist "!RUN_ID_FILE!" (
        set /p RUN_ID=<"!RUN_ID_FILE!"
        REM 移除换行符和空格
        set "RUN_ID=!RUN_ID: =!"
        set "RUN_ID=!RUN_ID: =!"
    )
)

if "!RUN_ID!"=="" (
    echo [ERROR] Run ID must be provided
    echo.
    echo Usage:
    echo   %0 [run_id]
    echo.
    echo If run_id is not provided, it will be read from .github_run_id.txt
    exit /b 1
)

REM 创建日志目录
set "LOG_DIR=%PROJECT_DIR%\workflow_logs"
if not exist "!LOG_DIR!" mkdir "!LOG_DIR!"

echo ========================================
echo   Monitor GitHub Actions Workflow
echo ========================================
echo.
echo Run ID: !RUN_ID!
echo Log directory: !LOG_DIR!
echo.

REM 获取 run 信息
echo Getting run information...
for /f "tokens=*" %%i in ('gh run view !RUN_ID! --json status,conclusion,url,workflowName,headBranch,event,createdAt 2^>nul') do set "RUN_INFO=%%i"

if "!RUN_INFO!"=="" (
    echo [ERROR] Cannot get run information
    echo Please check if run ID is correct: !RUN_ID!
    exit /b 1
)

REM 解析 run 信息（简化版本，Windows 批处理解析 JSON 较复杂）
echo Workflow information retrieved
echo.

REM 监控循环
set "POLL_INTERVAL=5"
set "ITERATION=0"

echo Starting to monitor workflow status (polling every !POLL_INTERVAL! seconds)...
echo Press Ctrl+C to stop monitoring (this will not cancel the workflow)
echo.

:monitor_loop
set /a ITERATION+=1

REM 获取当前状态
for /f "tokens=*" %%i in ('gh run view !RUN_ID! --json status,conclusion,updatedAt 2^>nul') do set "STATUS_INFO=%%i"

if "!STATUS_INFO!"=="" (
    echo [!ITERATION!] Cannot get status information
    timeout /t !POLL_INTERVAL! /nobreak >nul
    goto monitor_loop
)

REM 提取状态（简化版本）
echo !STATUS_INFO! | findstr /C:"queued" >nul
if %errorlevel% equ 0 (
    echo [%date% %time%] [!ITERATION!] Status: Queued...
    timeout /t !POLL_INTERVAL! /nobreak >nul
    goto monitor_loop
)

echo !STATUS_INFO! | findstr /C:"in_progress" >nul
if %errorlevel% equ 0 (
    echo [%date% %time%] [!ITERATION!] Status: In progress...
    timeout /t !POLL_INTERVAL! /nobreak >nul
    goto monitor_loop
)

echo !STATUS_INFO! | findstr /C:"completed" >nul
if %errorlevel% equ 0 (
    echo !STATUS_INFO! | findstr /C:"success" >nul
    if %errorlevel% equ 0 (
        echo [%date% %time%] [!ITERATION!] Status: Completed - Success!
        echo.
        echo ========================================
        echo   Workflow completed successfully!
        echo ========================================
        echo.
        exit /b 0
    ) else (
        echo [%date% %time%] [!ITERATION!] Status: Completed - Failed!
        echo.
        echo ========================================
        echo   Workflow execution failed!
        echo ========================================
        echo.
        
        REM 获取失败日志
        echo Getting error logs...
        set "LOG_FILE=!LOG_DIR!\workflow_!RUN_ID!_error.log"
        
        REM 获取所有失败的 jobs
        echo Failed Jobs: > "!LOG_FILE!"
        gh run view !RUN_ID! --json jobs --jq ".jobs[] | select(.conclusion == \"failure\" or .conclusion == \"cancelled\") | .name" 2>nul >> "!LOG_FILE!"
        echo. >> "!LOG_FILE!"
        echo ======================================== >> "!LOG_FILE!"
        echo. >> "!LOG_FILE!"
        
        REM 获取每个失败 job 的日志
        for /f "tokens=*" %%j in ('gh run view !RUN_ID! --json jobs --jq ".jobs[] | select(.conclusion == \"failure\" or .conclusion == \"cancelled\") | .name" 2^>nul') do (
            set "JOB_NAME=%%j"
            if not "!JOB_NAME!"=="" (
                echo Getting logs for Job '!JOB_NAME!'...
                echo. >> "!LOG_FILE!"
                echo ======================================== >> "!LOG_FILE!"
                echo Job: !JOB_NAME! >> "!LOG_FILE!"
                echo ======================================== >> "!LOG_FILE!"
                echo. >> "!LOG_FILE!"
                
                REM 获取 job 的日志
                gh run view !RUN_ID! --log-failed --job "!JOB_NAME!" >> "!LOG_FILE!" 2>&1
                if %errorlevel% neq 0 (
                    echo Cannot get logs for Job '!JOB_NAME!' >> "!LOG_FILE!"
                )
                echo. >> "!LOG_FILE!"
            )
        )
        
        REM 如果没有找到失败的 jobs，尝试获取所有日志
        if not exist "!LOG_FILE!" (
            echo No failed jobs found, trying to get full logs... > "!LOG_FILE!"
            gh run view !RUN_ID! --log >> "!LOG_FILE!" 2>&1
            if %errorlevel% neq 0 (
                echo Cannot get full logs >> "!LOG_FILE!"
            )
        )
        
        echo [OK] Error logs saved to: !LOG_FILE!
        echo.
        
        REM 显示简要错误信息
        echo Brief error information:
        gh run view !RUN_ID! --json jobs --jq ".jobs[] | select(.conclusion == \"failure\" or .conclusion == \"cancelled\") | \"  - \(.name): \(.conclusion)\"" 2>nul
        
        exit /b 1
    )
)

REM 其他状态
echo [%date% %time%] [!ITERATION!] Status: Unknown
timeout /t !POLL_INTERVAL! /nobreak >nul
goto monitor_loop

endlocal

