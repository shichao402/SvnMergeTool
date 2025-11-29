@echo off
REM GitHub Actions Workflow 触发和监控脚本 (Windows)

setlocal enabledelayedexpansion

set WORKFLOW=%1
set VERSION=%2

if "%WORKFLOW%"=="" (
    echo [ERROR] 用法: %0 ^<build^|release^> [version]
    exit /b 1
)

REM 检查 GitHub CLI
where gh >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] 未找到 GitHub CLI (gh)
    echo 请安装: https://cli.github.com/
    exit /b 1
)

REM 检查登录状态
gh auth status >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARNING] GitHub CLI 未登录，请先登录:
    echo 运行: gh auth login
    exit /b 1
)

echo ========================================
echo   触发 GitHub Actions Workflow
echo ========================================
echo.

if "%WORKFLOW%"=="build" (
    echo 触发构建 workflow...
    
    if not "%VERSION%"=="" (
        gh workflow run build.yml -f version="%VERSION%"
    ) else (
        gh workflow run build.yml
    )
    
    echo [OK] 构建 workflow 已触发
    
) else if "%WORKFLOW%"=="release" (
    echo 触发发布 workflow...
    
    if not "%VERSION%"=="" (
        gh workflow run release.yml -f version="%VERSION%"
    ) else (
        REM 尝试从 VERSION.yaml 读取版本号
        if exist "VERSION.yaml" (
            for /f "delims=" %%i in ('python scripts\lib\version_manager.py extract app 2^>nul') do set VERSION_FULL=%%i
            for /f "tokens=1 delims=+" %%i in ("!VERSION_FULL!") do set VERSION=%%i
            if not "!VERSION!"=="" (
                echo [INFO] 从 VERSION.yaml 读取版本号: !VERSION!
                gh workflow run release.yml -f version="!VERSION!"
            ) else (
                gh workflow run release.yml
            )
        ) else (
            gh workflow run release.yml
        )
    )
    
    echo [OK] 发布 workflow 已触发
) else (
    echo [ERROR] 未知的 workflow: %WORKFLOW%
    echo 支持: build, release
    exit /b 1
)

REM 等待 workflow 启动
echo.
echo 等待 workflow 启动...
timeout /t 3 /nobreak >nul

REM 获取最新的运行
echo.
echo 获取 workflow 运行信息...

if "%WORKFLOW%"=="build" (
    for /f "tokens=*" %%i in ('gh run list --workflow=build.yml --limit=1 --json databaseId,status,conclusion,url --jq ".[0].databaseId"') do set RUN_ID=%%i
    for /f "tokens=*" %%i in ('gh run list --workflow=build.yml --limit=1 --json databaseId,status,conclusion,url --jq ".[0].url"') do set URL=%%i
) else (
    for /f "tokens=*" %%i in ('gh run list --workflow=release.yml --limit=1 --json databaseId,status,conclusion,url --jq ".[0].databaseId"') do set RUN_ID=%%i
    for /f "tokens=*" %%i in ('gh run list --workflow=release.yml --limit=1 --json databaseId,status,conclusion,url --jq ".[0].url"') do set URL=%%i
)

if "!RUN_ID!"=="" (
    echo [ERROR] 无法获取 workflow 运行信息
    exit /b 1
)

echo [OK] Workflow 运行 ID: !RUN_ID!
echo [OK] URL: !URL!

REM 监控 workflow
echo.
echo 监控 workflow 执行...
echo 按 Ctrl+C 停止监控
echo.

:monitor_loop
if "%WORKFLOW%"=="build" (
    for /f "tokens=*" %%i in ('gh run view !RUN_ID! --workflow=build.yml --json status,conclusion --jq ".status"') do set STATUS=%%i
    for /f "tokens=*" %%i in ('gh run view !RUN_ID! --workflow=build.yml --json status,conclusion --jq ".conclusion // \"运行中\""') do set CONCLUSION=%%i
) else (
    for /f "tokens=*" %%i in ('gh run view !RUN_ID! --workflow=release.yml --json status,conclusion --jq ".status"') do set STATUS=%%i
    for /f "tokens=*" %%i in ('gh run view !RUN_ID! --workflow=release.yml --json status,conclusion --jq ".conclusion // \"运行中\""') do set CONCLUSION=%%i
)

echo 状态: !STATUS! ^| 结论: !CONCLUSION!

if "!STATUS!"=="completed" (
    if "!CONCLUSION!"=="success" (
        echo.
        echo [OK] Workflow 执行成功!
        echo [OK] 查看详情: !URL!
        exit /b 0
    ) else (
        echo.
        echo [ERROR] Workflow 执行失败: !CONCLUSION!
        echo [ERROR] 查看详情: !URL!
        exit /b 1
    )
)

timeout /t 10 /nobreak >nul
goto monitor_loop


