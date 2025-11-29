@echo off
REM GitHub Actions Workflow Trigger Script
REM Trigger a workflow and optionally monitor its execution

setlocal enabledelayedexpansion

set WORKFLOW=%~1
if "%WORKFLOW%"=="" set WORKFLOW=build.yml
set VERSION=%~2
set MONITOR=%~3

echo ==========================================
echo Triggering workflow: %WORKFLOW%
echo ==========================================
echo.

if not "%VERSION%"=="" (
    echo Using version: %VERSION%
    gh workflow run %WORKFLOW% -f version=%VERSION%
) else (
    gh workflow run %WORKFLOW%
)

if %errorlevel% neq 0 (
    echo Failed to trigger workflow
    exit /b 1
)

echo Workflow triggered successfully
echo.

if "%MONITOR%"=="true" (
    echo Waiting for workflow to start...
    timeout /t 5 /nobreak >nul
    
    REM Get latest run ID
    for /f "tokens=*" %%i in ('gh run list --workflow=%WORKFLOW% --limit=1 --json databaseId --jq ".[0].databaseId"') do set RUN_ID=%%i
    
    if "!RUN_ID!"=="" (
        echo Failed to get run ID
        exit /b 1
    )
    
    echo Monitoring run: !RUN_ID!
    echo URL: https://github.com/shichao402/SvnMergeTool/actions/runs/!RUN_ID!
    echo.
    
    REM Monitor until completion
    set MAX_WAIT=600
    set ELAPSED=0
    set INTERVAL=15
    
    :monitor_loop
    if !ELAPSED! geq !MAX_WAIT! (
        echo Timeout: workflow execution exceeded !MAX_WAIT! seconds
        exit /b 1
    )
    
    timeout /t !INTERVAL! /nobreak >nul
    set /a ELAPSED+=!INTERVAL!
    
    for /f "tokens=*" %%i in ('gh api repos/shichao402/SvnMergeTool/actions/runs/!RUN_ID! --jq -r ".status"') do set STATUS=%%i
    for /f "tokens=*" %%i in ('gh api repos/shichao402/SvnMergeTool/actions/runs/!RUN_ID! --jq -r ".conclusion // \"running\""') do set CONCLUSION=%%i
    
    echo [!ELAPSED!s] Status: !STATUS!, Conclusion: !CONCLUSION!
    
    if "!STATUS!"=="completed" (
        echo.
        if "!CONCLUSION!"=="success" (
            echo Workflow completed successfully!
            exit /b 0
        ) else (
            echo Workflow failed: !CONCLUSION!
            echo View logs: gh run view !RUN_ID! --log-failed
            exit /b 1
        )
    )
    
    goto monitor_loop
)


