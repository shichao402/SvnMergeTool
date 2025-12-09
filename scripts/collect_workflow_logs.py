#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN Auto Merge Tool - Collect Workflow Logs Script (跨平台 Python 实现)

收集 GitHub Actions workflow 的详细日志

路径处理规则：
- 必须使用 pathlib.Path 处理所有路径
"""

import sys
from pathlib import Path

# 添加 lib 目录到路径
script_dir = Path(__file__).parent.resolve()
lib_dir = script_dir / 'lib'
sys.path.insert(0, str(lib_dir))

from workflow_manager import WorkflowManager
import argparse


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="收集 GitHub Actions workflow 日志")
    parser.add_argument("run_id", nargs="?", type=int, help="run ID（可选，从文件读取）")
    
    args = parser.parse_args()
    
    # 获取项目根目录
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    
    manager = WorkflowManager(project_root)
    
    # 获取 run ID
    run_id = args.run_id
    if run_id is None:
        if manager.run_id_file.exists():
            try:
                run_id = int(manager.run_id_file.read_text().strip())
            except (ValueError, IOError):
                print("错误：无法从文件读取 run ID", file=sys.stderr)
                print("请提供 run ID: ./scripts/collect_workflow_logs.sh <run_id>", file=sys.stderr)
                return 1
        else:
            print("错误：必须提供 run ID", file=sys.stderr)
            print("用法: ./scripts/collect_workflow_logs.sh <run_id>", file=sys.stderr)
            return 1
    
    log_file = manager.collect_workflow_logs(run_id)
    if log_file:
        print(f"✓ 日志已保存到: {log_file}")
        return 0
    else:
        print("错误：无法收集日志", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())



