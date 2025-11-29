#!/usr/bin/env python3
"""
GitHub Actions Workflow 触发和监控脚本

用于触发 GitHub Actions workflow 并监控执行状态
"""

import argparse
import json
import sys
import time
import requests
from pathlib import Path

try:
    import yaml
except ImportError:
    print("错误: 需要安装 PyYAML 库")
    print("请运行: pip install pyyaml")
    sys.exit(1)


def load_version():
    """从 VERSION.yaml 加载版本号"""
    version_file = Path("VERSION.yaml")
    if not version_file.exists():
        raise FileNotFoundError("VERSION.yaml 不存在")
    
    with open(version_file, 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)
        return data['app']['version']


def trigger_workflow(owner, repo, workflow_id, token, ref="main", inputs=None):
    """触发 GitHub Actions workflow"""
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches"
    
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "Authorization": f"token {token}",
    }
    
    data = {
        "ref": ref,
    }
    
    if inputs:
        data["inputs"] = inputs
    
    response = requests.post(url, headers=headers, json=data)
    
    if response.status_code == 204:
        print(f"✅ 成功触发 workflow: {workflow_id}")
        return True
    else:
        print(f"❌ 触发失败: {response.status_code}")
        print(f"响应: {response.text}")
        return False


def get_workflow_runs(owner, repo, workflow_id, token, per_page=5):
    """获取 workflow 运行列表"""
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs"
    
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "Authorization": f"token {token}",
    }
    
    params = {
        "per_page": per_page,
    }
    
    response = requests.get(url, headers=headers, params=params)
    
    if response.status_code == 200:
        return response.json()
    else:
        print(f"❌ 获取运行列表失败: {response.status_code}")
        return None


def monitor_workflow(owner, repo, run_id, token, timeout=3600):
    """监控 workflow 运行状态"""
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/runs/{run_id}"
    
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "Authorization": f"token {token}",
    }
    
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        response = requests.get(url, headers=headers)
        
        if response.status_code == 200:
            run = response.json()
            status = run['status']
            conclusion = run.get('conclusion')
            
            print(f"状态: {status}, 结论: {conclusion or '运行中'}")
            
            if status == 'completed':
                if conclusion == 'success':
                    print("✅ Workflow 执行成功!")
                    return True
                else:
                    print(f"❌ Workflow 执行失败: {conclusion}")
                    return False
        else:
            print(f"❌ 获取运行状态失败: {response.status_code}")
            return False
        
        time.sleep(10)  # 每 10 秒检查一次
    
    print("⏱️ 超时: workflow 执行时间超过限制")
    return False


def main():
    parser = argparse.ArgumentParser(description="触发和监控 GitHub Actions workflow")
    parser.add_argument('workflow', choices=['build', 'release'], help='要触发的 workflow')
    parser.add_argument('--owner', default='shichao402', help='仓库所有者')
    parser.add_argument('--repo', default='SvnMergeTool', help='仓库名称')
    parser.add_argument('--token', help='GitHub Personal Access Token (需要 workflow 权限)')
    parser.add_argument('--ref', default='main', help='分支或标签')
    parser.add_argument('--version', help='版本号（用于 release workflow）')
    parser.add_argument('--monitor', action='store_true', help='监控 workflow 执行')
    parser.add_argument('--timeout', type=int, default=3600, help='监控超时时间（秒）')
    
    args = parser.parse_args()
    
    if not args.token:
        print("错误: 需要提供 GitHub Personal Access Token")
        print("使用 --token 参数或设置 GITHUB_TOKEN 环境变量")
        sys.exit(1)
    
    workflow_map = {
        'build': 'build.yml',
        'release': 'release.yml',
    }
    
    workflow_id = workflow_map[args.workflow]
    inputs = None
    
    if args.workflow == 'release':
        if args.version:
            inputs = {'version': args.version}
        else:
            # 从 VERSION.yaml 读取
            try:
                version = load_version()
                version_number = version.split('+')[0]
                inputs = {'version': version_number}
                print(f"从 VERSION.yaml 读取版本号: {version_number}")
            except Exception as e:
                print(f"警告: 无法读取版本号: {e}")
    
    # 触发 workflow
    success = trigger_workflow(
        args.owner,
        args.repo,
        workflow_id,
        args.token,
        args.ref,
        inputs
    )
    
    if not success:
        sys.exit(1)
    
    if args.monitor:
        print("\n等待 workflow 启动...")
        time.sleep(5)
        
        # 获取最新的运行
        runs = get_workflow_runs(args.owner, args.repo, workflow_id, args.token, per_page=1)
        
        if runs and runs.get('workflow_runs'):
            latest_run = runs['workflow_runs'][0]
            run_id = latest_run['id']
            
            print(f"\n监控 workflow 运行: {run_id}")
            print(f"运行 URL: {latest_run['html_url']}")
            
            monitor_workflow(args.owner, args.repo, run_id, args.token, args.timeout)
        else:
            print("❌ 无法获取 workflow 运行信息")


if __name__ == '__main__':
    main()



