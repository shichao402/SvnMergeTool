#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""列出所有已检查的日志路径。"""

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


def main():
    project_root = Path(__file__).parent.parent

    print("=" * 70)
    print("所有已检查的日志文件路径")
    print("=" * 70)

    paths = [
        ('1. 项目根目录下的 logs', project_root / 'logs'),
        ('2. exe 所在目录下的 logs', project_root / 'build' / 'windows' / 'x64' / 'runner' / 'Debug' / 'logs'),
        ('3. exe 所在目录（直接）', project_root / 'build' / 'windows' / 'x64' / 'runner' / 'Debug'),
    ]

    runtime_paths = get_runtime_log_paths()
    for index, path in enumerate(runtime_paths, start=4):
        paths.append((f'{index}. 应用支持目录', path))

    for name, path in paths:
        print(f"\n{name}:")
        print(f"  完整路径: {path}")
        print(f"  目录存在: {path.exists()}")
        if path.exists():
            log_files = list_log_files(path)
            print(f"  日志文件数: {len(log_files)}")
            if log_files:
                print('  日志文件列表:')
                for file in log_files[:5]:
                    size = file.stat().st_size
                    mtime = datetime.fromtimestamp(file.stat().st_mtime)
                    print(f"    - {file.name} ({size} bytes, {mtime})")
        else:
            parent = path.parent
            if parent.exists():
                children = [item.name for item in parent.iterdir()][:10]
                print(f"  父目录存在: {parent}")
                print(f"  父目录内容: {children}")

    print("\n" + "=" * 70)
    print("根据当前代码逻辑分析:")
    print("=" * 70)
    print("运行时使用 getApplicationSupportDirectory() 根目录下的 logs/")
    print("日志文件包括当前 latest.log 和归档的 app_*.log")


if __name__ == '__main__':
    main()
