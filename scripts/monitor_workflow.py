#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SVN Auto Merge Tool - Monitor Workflow Script (跨平台 Python 实现)

监控 GitHub Actions workflow 运行状态

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
    parser = argparse.ArgumentParser(description="监控 GitHub Actions workflow")
    parser.add_argument("run_id", nargs="?", type=int, help="run ID（可选，从文件读取）")
    parser.add_argument("--interval", type=int, default=5, help="查询间隔（秒，默认5）")
    
    args = parser.parse_args()
    
    # 获取项目根目录
    script_dir = Path(__file__).parent.resolve()
    project_root = script_dir.parent
    
    manager = WorkflowManager(project_root)
    
    # 监控 workflow
    return manager.monitor_workflow(run_id=args.run_id, poll_interval=args.interval)


if __name__ == '__main__':
    sys.exit(main())




