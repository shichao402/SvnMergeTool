#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""检查所有可能的日志文件路径"""

import os
from pathlib import Path

def check_path(path: Path, description: str):
    """检查路径是否存在日志文件"""
    print(f"\n{description}")
    print(f"  路径: {path}")
    print(f"  目录存在: {path.exists()}")
    
    if path.exists():
        log_files = list(path.glob("app_*.log"))
        print(f"  日志文件数量: {len(log_files)}")
        if log_files:
            # 按修改时间排序
            log_files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
            print(f"  最新的5个日志文件:")
            for f in log_files[:5]:
                size_kb = f.stat().st_size / 1024
                mtime = f.stat().st_mtime
                from datetime import datetime
                mtime_str = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
                print(f"    - {f.name} ({size_kb:.1f} KB, {mtime_str})")
    else:
        print(f"  目录不存在")

def main():
    print("=" * 60)
    print("检查所有可能的日志文件路径")
    print("=" * 60)
    
    # 1. 项目根目录下的 logs
    project_root = Path(__file__).parent.parent
    project_logs = project_root / "logs"
    check_path(project_logs, "1. 项目根目录下的 logs 目录（开发环境）")
    
    # 2. 可执行文件所在目录下的 logs（如果直接运行exe）
    exe_path = project_root / "build" / "windows" / "x64" / "runner" / "Debug" / "SvnMergeTool.exe"
    if exe_path.exists():
        exe_dir_logs = exe_path.parent / "logs"
        check_path(exe_dir_logs, "2. 可执行文件所在目录下的 logs（直接运行exe时）")
    
    # 3. Windows 应用支持目录
    appdata = os.getenv('APPDATA')
    if appdata:
        app_support_logs = Path(appdata) / "SvnMergeTool" / "logs"
        check_path(app_support_logs, "3. Windows 应用支持目录（打包环境）")
    
    # 4. 检查当前工作目录（程序运行时的工作目录）
    # 可能的位置：
    # - 项目根目录
    # - exe所在目录
    # - 用户启动程序时的目录
    current_dir = Path.cwd()
    current_logs = current_dir / "logs"
    if current_logs != project_logs:  # 避免重复
        check_path(current_logs, f"4. 当前工作目录下的 logs（当前: {current_dir}）")
    
    # 5. 检查 exe 所在目录的父目录（可能从其他位置运行）
    if exe_path.exists():
        exe_parent_logs = exe_path.parent.parent / "logs"
        if exe_parent_logs != project_logs:
            check_path(exe_parent_logs, "5. exe 所在目录的父目录下的 logs")
    
    print("\n" + "=" * 60)
    print("检查完成")
    print("=" * 60)

if __name__ == '__main__':
    main()


