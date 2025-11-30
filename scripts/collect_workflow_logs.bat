@echo off
REM GitHub Actions Workflow 日志收集脚本 (Windows)
REM
REM 收集 GitHub Actions workflow 的详细日志
REM 功能：
REM - 收集 workflow run 的详细信息
REM - 收集所有 jobs 的日志
REM - 保存到统一的日志文件
REM
REM 使用方法：
REM   scripts\collect_workflow_logs.bat [run_id]
REM
REM 如果不提供 run_id，将从 .github_run_id.txt 文件读取

REM 获取脚本所在目录
set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."

REM 确定 Python 解释器
if exist "%PROJECT_DIR%\.venv\Scripts\python.exe" (
    set "PYTHON=%PROJECT_DIR%\.venv\Scripts\python.exe"
) else (
    REM 尝试使用系统 Python
    python --version >nul 2>&1
    if %errorlevel% equ 0 (
        set "PYTHON=python"
    ) else (
        echo [ERROR] Python interpreter not found
        echo Please install Python 3 or create virtual environment: python -m venv .venv
        exit /b 1
    )
)

REM 使用 Python 运行核心脚本
"%PYTHON%" "%SCRIPT_DIR%lib\workflow_manager.py" collect-logs %*


