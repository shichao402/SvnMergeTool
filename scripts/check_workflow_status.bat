@echo off
REM GitHub Actions Workflow Status Checker
REM Check the status of the latest workflow run

setlocal enabledelayedexpansion

set WORKFLOW=%~1
if "%WORKFLOW%"=="" set WORKFLOW=build.yml
set LIMIT=%~2
if "%LIMIT%"=="" set LIMIT=1

echo ==========================================
echo Checking workflow: %WORKFLOW%
echo ==========================================
echo.

REM Get latest run
for /f "tokens=*" %%i in ('gh run list --workflow=%WORKFLOW% --limit=%LIMIT% --json databaseId,status,conclusion,url,createdAt --jq ".[0].databaseId"') do set RUN_ID=%%i

if "!RUN_ID!"=="" (
    echo No runs found for workflow: %WORKFLOW%
    exit /b 1
)

echo Run ID: !RUN_ID!
gh run list --workflow=%WORKFLOW% --limit=%LIMIT% --json status,conclusion,url,createdAt --jq ".[0] | \"Status: \(.status)\nConclusion: \(.conclusion // \\\"in_progress\\\")\nURL: \(.url)\nCreated: \(.createdAt)\""

echo.
echo ==========================================
echo Job Details:
echo ==========================================
gh run view !RUN_ID! --json jobs --jq ".jobs[] | \"\(.name): \(.status) - \(.conclusion // \\\"running\\\")\""


