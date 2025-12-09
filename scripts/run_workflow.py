#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN Auto Merge Tool - Run Workflow Script (跨平台 Python 实现)

组合脚本：触发 workflow 并自动监控

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
    parser = argparse.ArgumentParser(description="触发并监控 GitHub Actions workflow")
    parser.add_argument("workflow_file", help="workflow 文件路径")
    parser.add_argument("--ref", help="Git 引用（分支、标签或提交 SHA）")
    parser.add_argument("--input", "-f", action="append", metavar="KEY=VALUE",
                        help="workflow 输入参数（可多次使用）")
    parser.add_argument("--interval", type=int, default=5, help="监控查询间隔（秒，默认5）")
    
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
    print("==========================================")
    print("  步骤 1: 触发 Workflow")
    print("==========================================")
    print()
    
    success, run_id, message = manager.trigger_workflow(
        args.workflow_file,
        ref=args.ref,
        inputs=inputs if inputs else None
    )
    
    if not success:
        print(message, file=sys.stderr)
        return 1
    
    print(message)
    print()
    
    # 监控 workflow
    print("==========================================")
    print("  步骤 2: 监控 Workflow")
    print("==========================================")
    print()
    
    return manager.monitor_workflow(run_id=run_id, poll_interval=args.interval)


if __name__ == '__main__':
    sys.exit(main())



