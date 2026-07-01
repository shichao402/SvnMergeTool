#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""检查所有可能的日志文件路径。"""

import os
import platform
from datetime import datetime
from pathlib import Path
from typing import List

LOG_PATTERNS = ("latest.log", "app_*.log")


def get_runtime_log_paths() -> List[Path]:
    system = platform.system()
    if system == 'Windows':
        appdata = os.getenv('APPDATA')
        return [Path(appdata) / 'SvnAutoMerge' / 'logs'] if appdata else []
    if system == 'Darwin':
        return [
            Path.home()
            / 'Library'
            / 'Application Support'
            / 'com.example.svnautomerge'
            / 'logs'
        ]
    if system == 'Linux':
        return [Path.home() / '.local' / 'share' / 'SvnAutoMerge' / 'logs']
    return []


def list_log_files(path: Path) -> List[Path]:
    files: List[Path] = []
    for pattern in LOG_PATTERNS:
        files.extend(path.glob(pattern))
    files.sort(key=lambda file: file.stat().st_mtime, reverse=True)
    return files


def check_path(path: Path, description: str):
    print(f"\n{description}")
    print(f"  路径: {path}")
    print(f"  目录存在: {path.exists()}")

    if path.exists():
        log_files = list_log_files(path)
        print(f"  日志文件数量: {len(log_files)}")
        if log_files:
            print("  最新的5个日志文件:")
            for file in log_files[:5]:
                size_kb = file.stat().st_size / 1024
                mtime = datetime.fromtimestamp(file.stat().st_mtime)
                print(f"    - {file.name} ({size_kb:.1f} KB, {mtime:%Y-%m-%d %H:%M:%S})")
    else:
        print("  目录不存在")


def main():
    print("=" * 60)
    print("检查所有可能的日志文件路径")
    print("=" * 60)

    project_root = Path(__file__).parent.parent
    project_logs = project_root / 'logs'
    check_path(project_logs, '1. 项目根目录下的 logs 目录（开发环境）')

    exe_path = project_root / 'build' / 'windows' / 'x64' / 'runner' / 'Debug' / 'SvnAutoMerge.exe'
    if exe_path.exists():
        exe_dir_logs = exe_path.parent / 'logs'
        check_path(exe_dir_logs, '2. 可执行文件所在目录下的 logs（直接运行 exe 时）')
        check_path(exe_path.parent, '3. 可执行文件所在目录（直接）')

    runtime_log_paths = get_runtime_log_paths()
    for index, runtime_path in enumerate(runtime_log_paths, start=4):
        check_path(runtime_path, f'{index}. 应用支持目录')

    current_dir = Path.cwd()
    current_logs = current_dir / 'logs'
    if current_logs != project_logs:
        check_path(current_logs, f'{len(runtime_log_paths) + 4}. 当前工作目录下的 logs（当前: {current_dir}）')

    print("\n" + "=" * 60)
    print("检查完成")
    print("=" * 60)


if __name__ == '__main__':
    main()
