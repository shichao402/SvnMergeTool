#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""列出所有已检查的日志路径"""

import os
from pathlib import Path

def main():
    project_root = Path(__file__).parent.parent
    
    print("=" * 70)
    print("所有已检查的日志文件路径（双击exe执行时）")
    print("=" * 70)
    
    paths = [
        ("1. 项目根目录下的logs", project_root / "logs"),
        ("2. exe所在目录下的logs", project_root / "build" / "windows" / "x64" / "runner" / "Debug" / "logs"),
        ("3. exe所在目录（直接）", project_root / "build" / "windows" / "x64" / "runner" / "Debug"),
        ("4. Windows应用支持目录", Path(os.getenv('APPDATA', '')) / "SvnMergeTool" / "logs" if os.getenv('APPDATA') else None),
    ]
    
    for name, path in paths:
        if path is None:
            print(f"\n{name}: (无法确定路径)")
            continue
        print(f"\n{name}:")
        print(f"  完整路径: {path}")
        print(f"  目录存在: {path.exists()}")
        if path.exists():
            log_files = list(path.glob("app_*.log"))
            print(f"  日志文件数: {len(log_files)}")
            if log_files:
                log_files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
                print(f"  日志文件列表:")
                for f in log_files[:5]:
                    size = f.stat().st_size
                    from datetime import datetime
                    mtime = datetime.fromtimestamp(f.stat().st_mtime)
                    print(f"    - {f.name} ({size} bytes, {mtime})")
        else:
            # 检查父目录是否存在
            parent = path.parent
            if parent.exists():
                print(f"  父目录存在: {parent}")
                print(f"  父目录内容: {[f.name for f in parent.iterdir()][:10]}")
    
    print("\n" + "=" * 70)
    print("根据代码逻辑分析:")
    print("=" * 70)
    print("当双击exe执行时:")
    print("  1. Directory.current = exe所在目录")
    print("  2. 检查是否有 logs 目录或 pubspec.yaml")
    print("  3. 如果没有，使用应用支持目录")
    print("\n可能的原因:")
    print("  1. 日志服务初始化失败（检查是否有错误输出）")
    print("  2. 日志文件还未创建（程序刚启动）")
    print("  3. 日志文件在其他位置（需要用户确认）")

if __name__ == '__main__':
    main()

