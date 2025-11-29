@echo off
REM SVN 自动合并工具 - 日志收集脚本 (Windows)
REM
REM 收集所有相关日志文件到统一目录
REM 包括：
REM - 应用日志文件（logs/app_*.log）
REM - Flutter 输出日志
REM - 配置文件

setlocal enabledelayedexpansion

REM 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."

REM 生成时间戳
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set "dt=%%I"
set "TIMESTAMP=%dt:~0,8%_%dt:~8,6%"
set "LOG_DIR=%PROJECT_DIR%\logs\app_%TIMESTAMP%"

echo ========================================
echo   日志收集脚本
echo ========================================
echo.

REM 创建日志目录
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
echo [OK] 创建日志目录: %LOG_DIR%

REM 收集应用日志文件
echo.
echo 收集应用日志文件...
if exist "%PROJECT_DIR%\logs" (
    set COUNT=0
    for %%F in ("%PROJECT_DIR%\logs\app_*.log") do (
        set /a COUNT+=1
        if !COUNT! leq 20 (
            copy /Y "%%F" "%LOG_DIR%\" >nul 2>&1
            echo   [OK] %%~nxF
        )
    )
    if !COUNT! equ 0 (
        echo   [警告] 未找到应用日志文件
    )
) else (
    echo   [警告] 日志目录不存在
)

REM 收集配置文件
echo.
echo 收集配置文件...
if exist "%PROJECT_DIR%\assets\config\source_urls.json" (
    copy /Y "%PROJECT_DIR%\assets\config\source_urls.json" "%LOG_DIR%\config.json" >nul 2>&1
    echo   [OK] config.json (来自 assets/config/)
)

if exist "%PROJECT_DIR%\config\source_urls.json" (
    copy /Y "%PROJECT_DIR%\config\source_urls.json" "%LOG_DIR%\config_runtime.json" >nul 2>&1
    echo   [OK] config_runtime.json (来自 config/)
)

REM 收集系统信息
echo.
echo 收集系统信息...
(
    echo === 系统信息 ===
    echo 时间: %date% %time%
    echo 操作系统: %OS%
    echo 计算机名: %COMPUTERNAME%
    echo 用户名: %USERNAME%
    echo.
    echo === Flutter 信息 ===
    flutter --version 2>nul || echo Flutter 未安装或不在 PATH
    echo.
    echo === Dart 信息 ===
    dart --version 2>nul || echo Dart 未安装或不在 PATH
) > "%LOG_DIR%\system_info.txt"
echo   [OK] system_info.txt

REM 生成日志摘要
echo.
echo 生成日志摘要...
(
    echo === 日志收集摘要 ===
    echo 收集时间: %date% %time%
    echo 日志目录: %LOG_DIR%
    echo.
    echo === 收集的文件 ===
    dir /b "%LOG_DIR%" | findstr /v "SUMMARY.txt"
    echo.
    echo === 日志文件统计 ===
    for /f %%A in ('dir /b "%LOG_DIR%\*.log" 2^>nul ^| find /c /v ""') do set LOG_COUNT=%%A
    echo 日志文件数量: !LOG_COUNT!
    for /f "tokens=3" %%A in ('dir "%LOG_DIR%" ^| find "bytes"') do set TOTAL_SIZE=%%A
    echo 总大小: !TOTAL_SIZE! 字节
) > "%LOG_DIR%\SUMMARY.txt"
echo   [OK] SUMMARY.txt

echo.
echo ========================================
echo   日志收集完成！
echo ========================================
echo.
echo 日志目录: %LOG_DIR%
echo.
echo 查看日志：
echo   type %LOG_DIR%\SUMMARY.txt
echo   type %LOG_DIR%\app_*.log

endlocal

