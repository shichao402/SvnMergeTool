@echo off
REM SVN 合并助手 - 构建脚本入口 (Windows)
REM
REM 入口脚本：仅调用 Python 核心脚本

setlocal

set "SCRIPT_DIR=%~dp0"

if exist "%SCRIPT_DIR%..\.venv\Scripts\python.exe" (
    set "PYTHON=%SCRIPT_DIR%..\.venv\Scripts\python.exe"
) else if exist "%SCRIPT_DIR%..\.venv\Scripts\pythonw.exe" (
    set "PYTHON=%SCRIPT_DIR%..\.venv\Scripts\pythonw.exe"
) else (
    where python >nul 2>&1
    if %errorlevel% equ 0 (
        set "PYTHON=python"
    ) else (
        echo 错误: 未找到 Python 解释器
        exit /b 1
    )
)

"%PYTHON%" "%SCRIPT_DIR%build.py" %*

endlocal
