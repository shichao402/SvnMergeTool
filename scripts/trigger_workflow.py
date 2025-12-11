#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN Auto Merge Tool - Trigger Workflow Script (跨平台 Python 实现)

触发 GitHub Actions workflow 并获取 run ID

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
    parser = argparse.ArgumentParser(description="触发 GitHub Actions workflow")
    parser.add_argument("workflow_file", help="workflow 文件路径")
    parser.add_argument("--ref", help="Git 引用（分支、标签或提交 SHA）")
    parser.add_argument("--input", "-f", action="append", metavar="KEY=VALUE",
                        help="workflow 输入参数（可多次使用）")
    
    args = parser.parse_args()
    
    # 获取项目根目录
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    
    manager = WorkflowManager(project_root)
    
    # 解析输入参数
    inputs = {}
    if args.input:
        for inp in args.input:
            if "=" in inp:
                key, value = inp.split("=", 1)
                inputs[key] = value
    
    # 触发 workflow
    success, run_id, message = manager.trigger_workflow(
        args.workflow_file,
        ref=args.ref,
        inputs=inputs if inputs else None
    )
    
    if success:
        print("========================================")
        print("  触发 GitHub Actions Workflow")
        print("========================================")
        print()
        print(message)
        print(f"Run ID 文件: {manager.run_id_file}")
        print()
        if run_id:
            print("使用以下命令监控 workflow:")
            print(f"  ./scripts/monitor_workflow.sh {run_id}")
        return 0
    else:
        print(message, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())




