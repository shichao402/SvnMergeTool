#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GitHub Actions Workflow 管理工具
用于触发和监控 GitHub Actions workflow
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class WorkflowManager:
    """GitHub Actions Workflow 管理器"""
    
    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.run_id_file = project_root / ".github_run_id.txt"
        self.log_dir = project_root / "workflow_logs"
        self.log_dir.mkdir(exist_ok=True)
    
    def check_gh_cli(self) -> bool:
        """检查 GitHub CLI 是否安装"""
        try:
            subprocess.run(
                ["gh", "--version"],
                capture_output=True,
                check=True
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False
    
    def check_gh_auth(self) -> bool:
        """检查 GitHub CLI 是否已登录"""
        try:
            result = subprocess.run(
                ["gh", "auth", "status"],
                capture_output=True,
                check=True
            )
            return True
        except subprocess.CalledProcessError:
            return False
    
    def get_repo_info(self) -> Optional[str]:
        """获取仓库信息"""
        try:
            result = subprocess.run(
                ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            return None
    
    def trigger_workflow(
        self,
        workflow_file: str,
        ref: Optional[str] = None,
        inputs: Optional[Dict[str, str]] = None
    ) -> Tuple[bool, Optional[int], str]:
        """
        触发 GitHub Actions workflow
        
        Args:
            workflow_file: workflow 文件路径
            ref: Git 引用（分支、标签或提交 SHA）
            inputs: workflow 输入参数
            
        Returns:
            (success, run_id, message)
        """
        # 检查 GitHub CLI
        if not self.check_gh_cli():
            return False, None, "错误：未找到 GitHub CLI (gh)\n请安装 GitHub CLI: https://cli.github.com/"
        
        if not self.check_gh_auth():
            return False, None, "错误：GitHub CLI 未登录\n请运行: gh auth login"
        
        # 检查 workflow 文件
        workflow_path = self.project_root / workflow_file
        if not workflow_path.exists():
            return False, None, f"错误：workflow 文件不存在: {workflow_file}"
        
        # 获取 workflow ID（使用文件名，GitHub CLI 会自动匹配）
        workflow_id = workflow_path.name
        
        # 获取仓库信息
        repo = self.get_repo_info()
        if not repo:
            return False, None, "错误：无法获取仓库信息\n请确保当前目录是一个 Git 仓库，并且已配置 GitHub remote"
        
        # 如果没有指定 ref，使用当前分支
        if not ref:
            try:
                result = subprocess.run(
                    ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                    capture_output=True,
                    text=True,
                    check=True,
                    cwd=self.project_root
                )
                ref = result.stdout.strip() or "main"
            except subprocess.CalledProcessError:
                ref = "main"
        
        # 构建 gh workflow run 命令
        cmd = ["gh", "workflow", "run", workflow_id, "--ref", ref]
        
        # 添加输入参数（使用 -f 参数）
        if inputs:
            for key, value in inputs.items():
                cmd.extend(["-f", f"{key}={value}"])
        
        # 触发 workflow
        try:
            subprocess.run(cmd, check=True, cwd=self.project_root)
        except subprocess.CalledProcessError as e:
            return False, None, f"错误：触发 workflow 失败\n{e}"
        
        # 等待几秒让 workflow 启动
        time.sleep(3)
        
        # 获取最新的 run ID
        max_attempts = 10
        for attempt in range(max_attempts):
            try:
                result = subprocess.run(
                    ["gh", "run", "list", "--workflow", workflow_id, "--limit", "1",
                     "--json", "databaseId", "-q", ".[0].databaseId"],
                    capture_output=True,
                    text=True,
                    check=True,
                    cwd=self.project_root
                )
                run_id_str = result.stdout.strip()
                if run_id_str and run_id_str != "null":
                    run_id = int(run_id_str)
                    # 保存 run ID 到文件
                    self.run_id_file.write_text(str(run_id))
                    return True, run_id, f"✓ Workflow 已触发\nRun ID: {run_id}"
            except (subprocess.CalledProcessError, ValueError, IndexError):
                pass
            
            if attempt < max_attempts - 1:
                time.sleep(2)
        
        return False, None, "警告：无法获取 run ID\n请手动查看 GitHub Actions 页面获取 run ID"
    
    def monitor_workflow(self, run_id: Optional[int] = None, poll_interval: int = 5) -> int:
        """
        监控 GitHub Actions workflow 执行状态
        
        Args:
            run_id: GitHub Actions run ID，如果为 None 则从文件读取
            poll_interval: 查询间隔（秒）
            
        Returns:
            退出码（0=成功，1=失败）
        """
        # 检查 GitHub CLI
        if not self.check_gh_cli():
            print("错误：未找到 GitHub CLI (gh)", file=sys.stderr)
            return 1
        
        if not self.check_gh_auth():
            print("错误：GitHub CLI 未登录", file=sys.stderr)
            return 1
        
        # 获取 run ID
        if run_id is None:
            if self.run_id_file.exists():
                try:
                    run_id = int(self.run_id_file.read_text().strip())
                except (ValueError, IOError):
                    print("错误：无法从文件读取 run ID", file=sys.stderr)
                    return 1
            else:
                print("错误：必须提供 run ID", file=sys.stderr)
                return 1
        
        # 获取 run 信息
        try:
            result = subprocess.run(
                ["gh", "run", "view", str(run_id), "--json",
                 "status,conclusion,url,workflowName,headBranch,event,createdAt"],
                capture_output=True,
                text=True,
                check=True
            )
            run_info = json.loads(result.stdout)
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            print(f"错误：无法获取 run 信息\n请检查 run ID 是否正确: {run_id}", file=sys.stderr)
            return 1
        
        workflow_name = run_info.get("workflowName", "Unknown")
        head_branch = run_info.get("headBranch", "Unknown")
        event = run_info.get("event", "Unknown")
        url = run_info.get("url", "")
        
        print(f"Workflow: {workflow_name}")
        print(f"分支: {head_branch}")
        print(f"事件: {event}")
        if url:
            print(f"URL: {url}")
        print()
        
        # 监控循环
        iteration = 0
        print(f"开始监控 workflow 状态（每 {poll_interval} 秒查询一次）...")
        print("按 Ctrl+C 可以停止监控（不会取消 workflow）")
        print()
        
        while True:
            iteration += 1
            
            # 获取当前状态
            try:
                result = subprocess.run(
                    ["gh", "run", "view", str(run_id), "--json", "status,conclusion,updatedAt"],
                    capture_output=True,
                    text=True,
                    check=True
                )
                status_info = json.loads(result.stdout)
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
                print(f"[{timestamp}] [{iteration}] 无法获取状态信息")
                time.sleep(poll_interval)
                continue
            
            status = status_info.get("status", "unknown")
            conclusion = status_info.get("conclusion")
            updated_at = status_info.get("updatedAt", "")
            
            # 显示状态
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
            
            if status == "queued":
                print(f"[{timestamp}] [{iteration}] 状态: 排队中...")
            elif status == "in_progress":
                print(f"[{timestamp}] [{iteration}] 状态: 运行中...")
            elif status == "completed":
                if conclusion == "success":
                    print(f"[{timestamp}] [{iteration}] 状态: 完成 - 成功！")
                    print()
                    print("========================================")
                    print("  Workflow 执行成功！")
                    print("========================================")
                    print()
                    return 0
                else:
                    print(f"[{timestamp}] [{iteration}] 状态: 完成 - 失败！")
                    print()
                    print("========================================")
                    print("  Workflow 执行失败！")
                    print("========================================")
                    print()
                    
                    # 获取失败日志（只保存到文件，不在这里显示）
                    log_file = self.collect_workflow_logs(run_id)
                    if log_file:
                        print(f"✓ 错误日志已保存到: {log_file}")
                        print("使用以下命令查看详细日志：")
                        print(f"  ./scripts/collect_workflow_logs.sh {run_id}")
                    print()
                    return 1
            else:
                print(f"[{timestamp}] [{iteration}] 状态: {status}")
            
            # 等待下一次查询
            time.sleep(poll_interval)
    
    def collect_workflow_logs(self, run_id: int) -> Optional[Path]:
        """
        收集 GitHub Actions workflow 的日志
        
        Args:
            run_id: GitHub Actions run ID
            
        Returns:
            日志文件路径，如果失败则返回 None
        """
        print("正在收集 workflow 日志...")
        log_file = self.log_dir / f"workflow_{run_id}_error.log"
        
        try:
            # 获取 run 的详细信息
            result = subprocess.run(
                ["gh", "run", "view", str(run_id), "--json", "jobs,status,conclusion,workflowName,headBranch,event"],
                capture_output=True,
                text=True,
                check=True
            )
            run_data = json.loads(result.stdout)
        except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
            print(f"错误：无法获取 run 信息: {e}", file=sys.stderr)
            return None
        
        with open(log_file, "w", encoding="utf-8") as f:
            # 写入 run 基本信息
            f.write("=" * 80 + "\n")
            f.write("GitHub Actions Workflow 错误日志\n")
            f.write("=" * 80 + "\n\n")
            f.write(f"Run ID: {run_id}\n")
            f.write(f"Workflow: {run_data.get('workflowName', 'Unknown')}\n")
            f.write(f"分支: {run_data.get('headBranch', 'Unknown')}\n")
            f.write(f"事件: {run_data.get('event', 'Unknown')}\n")
            f.write(f"状态: {run_data.get('status', 'Unknown')}\n")
            f.write(f"结论: {run_data.get('conclusion', 'Unknown')}\n")
            f.write(f"收集时间: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("\n" + "=" * 80 + "\n\n")
            
            # 获取所有 jobs
            jobs = run_data.get("jobs", [])
            if not jobs:
                f.write("未找到 jobs 信息\n")
                return log_file
            
            # 写入 jobs 摘要
            f.write("Jobs 摘要:\n")
            f.write("-" * 80 + "\n")
            for job in jobs:
                job_name = job.get("name", "Unknown")
                job_status = job.get("status", "Unknown")
                job_conclusion = job.get("conclusion", "Unknown")
                job_id = job.get("databaseId", "")
                f.write(f"  {job_name}: {job_status} / {job_conclusion} (ID: {job_id})\n")
            f.write("\n" + "=" * 80 + "\n\n")
            
            # 获取失败的 jobs
            failed_jobs = [job for job in jobs if job.get("conclusion") in ["failure", "cancelled"]]
            
            if failed_jobs:
                f.write(f"失败的 Jobs ({len(failed_jobs)} 个):\n")
                f.write("-" * 80 + "\n")
                for job in failed_jobs:
                    job_name = job.get("name", "Unknown")
                    job_id = job.get("databaseId", "")
                    f.write(f"  - {job_name} (ID: {job_id})\n")
                f.write("\n" + "=" * 80 + "\n\n")
                
                # 获取每个失败 job 的日志
                for job in failed_jobs:
                    job_name = job.get("name", "Unknown")
                    job_id = job.get("databaseId", "")
                    
                    print(f"正在获取 Job '{job_name}' (ID: {job_id}) 的日志...")
                    
                    f.write("\n" + "=" * 80 + "\n")
                    f.write(f"Job: {job_name} (ID: {job_id})\n")
                    f.write("=" * 80 + "\n\n")
                    
                    # 尝试多种方式获取日志
                    log_obtained = False
                    
                    # 方式1: 使用 job ID 获取日志
                    if job_id:
                        try:
                            result = subprocess.run(
                                ["gh", "run", "view", str(run_id), "--log", "--job", str(job_id)],
                                capture_output=True,
                                text=True,
                                encoding="utf-8",
                                errors="replace",
                                check=True,
                                timeout=60
                            )
                            if result.stdout and result.stdout.strip():
                                f.write(result.stdout)
                                log_obtained = True
                        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                            pass
                    
                    # 方式2: 使用 job 名称获取失败日志
                    if not log_obtained:
                        try:
                            result = subprocess.run(
                                ["gh", "run", "view", str(run_id), "--log-failed"],
                                capture_output=True,
                                text=True,
                                encoding="utf-8",
                                errors="replace",
                                check=True,
                                timeout=60
                            )
                            if result.stdout and result.stdout.strip():
                                f.write("完整失败日志:\n")
                                f.write("-" * 80 + "\n")
                                f.write(result.stdout)
                                log_obtained = True
                        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                            pass
                    
                    # 方式3: 获取完整日志
                    if not log_obtained:
                        try:
                            result = subprocess.run(
                                ["gh", "run", "view", str(run_id), "--log"],
                                capture_output=True,
                                text=True,
                                encoding="utf-8",
                                errors="replace",
                                check=True,
                                timeout=60
                            )
                            if result.stdout and result.stdout.strip():
                                f.write("完整日志:\n")
                                f.write("-" * 80 + "\n")
                                f.write(result.stdout)
                                log_obtained = True
                        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                            pass
                    
                    if not log_obtained:
                        f.write(f"无法获取 Job '{job_name}' 的日志\n")
                        f.write("请访问以下 URL 查看详细日志:\n")
                        f.write(f"  {run_data.get('url', '')}\n")
                    
                    f.write("\n")
            else:
                # 如果没有失败的 jobs，尝试获取完整日志
                f.write("未找到失败的 Jobs，获取完整日志...\n")
                f.write("-" * 80 + "\n\n")
                try:
                    result = subprocess.run(
                        ["gh", "run", "view", str(run_id), "--log"],
                        capture_output=True,
                        text=True,
                        encoding="utf-8",
                        errors="replace",
                        check=True,
                        timeout=120
                    )
                    if result.stdout and result.stdout.strip():
                        f.write(result.stdout)
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                    f.write(f"无法获取完整日志: {e}\n")
                    f.write("请访问以下 URL 查看详细日志:\n")
                    f.write(f"  {run_data.get('url', '')}\n")
        
        return log_file


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="GitHub Actions Workflow 管理工具")
    subparsers = parser.add_subparsers(dest="command", help="命令")
    
    # trigger 命令
    trigger_parser = subparsers.add_parser("trigger", help="触发 workflow")
    trigger_parser.add_argument("workflow_file", help="workflow 文件路径")
    trigger_parser.add_argument("--ref", help="Git 引用（分支、标签或提交 SHA）")
    trigger_parser.add_argument("--input", "-f", action="append", metavar="KEY=VALUE",
                                help="workflow 输入参数（可多次使用，使用 -f 或 --input）")
    
    # monitor 命令
    monitor_parser = subparsers.add_parser("monitor", help="监控 workflow")
    monitor_parser.add_argument("run_id", nargs="?", type=int, help="run ID（可选，从文件读取）")
    monitor_parser.add_argument("--interval", type=int, default=5, help="查询间隔（秒，默认5）")
    
    # collect-logs 命令
    collect_parser = subparsers.add_parser("collect-logs", help="收集 workflow 日志")
    collect_parser.add_argument("run_id", nargs="?", type=int, help="run ID（可选，从文件读取）")
    
    # run 命令（组合命令）
    run_parser = subparsers.add_parser("run", help="触发并监控 workflow")
    run_parser.add_argument("workflow_file", help="workflow 文件路径")
    run_parser.add_argument("--ref", help="Git 引用（分支、标签或提交 SHA）")
    run_parser.add_argument("--input", "-f", action="append", metavar="KEY=VALUE",
                            help="workflow 输入参数（可多次使用，使用 -f 或 --input）")
    run_parser.add_argument("--interval", type=int, default=5, help="监控查询间隔（秒，默认5）")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    # 获取项目根目录
    script_dir = Path(__file__).parent.parent.resolve()
    project_root = script_dir.parent
    
    manager = WorkflowManager(project_root)
    
    if args.command == "trigger":
        # 解析输入参数
        inputs = {}
        if args.input:
            for inp in args.input:
                if "=" in inp:
                    key, value = inp.split("=", 1)
                    inputs[key] = value
        
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
            # 显示 run 信息
            if run_id:
                try:
                    result = subprocess.run(
                        ["gh", "run", "view", str(run_id), "--json", "status,conclusion,url",
                         "-q", '"状态: \\(.status)\\n结论: \\(.conclusion // \\"运行中\\")\\nURL: \\(.url)"'],
                        capture_output=True,
                        text=True,
                        check=True
                    )
                    print("Run 信息:")
                    print(result.stdout.strip())
                except subprocess.CalledProcessError:
                    pass
            print()
            print("使用以下命令监控 workflow:")
            print(f"  ./scripts/monitor_workflow.sh {run_id}")
            return 0
        else:
            print(message, file=sys.stderr)
            return 1
    
    elif args.command == "monitor":
        return manager.monitor_workflow(run_id=args.run_id, poll_interval=args.interval)
    
    elif args.command == "collect-logs":
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
    
    elif args.command == "run":
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
    
    return 0


if __name__ == "__main__":
    sys.exit(main())

