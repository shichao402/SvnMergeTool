#!/usr/bin/env python3
"""
GitHub Actions Workflow 验证脚本

验证 workflow 文件的语法和逻辑
"""

import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("错误: 需要安装 PyYAML 库")
    print("请运行: pip install pyyaml")
    sys.exit(1)


def validate_yaml(file_path):
    """验证 YAML 文件语法"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
        return True, None
    except yaml.YAMLError as e:
        return False, str(e)
    except Exception as e:
        return False, str(e)


def validate_workflow_structure(data):
    """验证 workflow 结构"""
    errors = []
    
    # 检查必需字段
    if 'name' not in data:
        errors.append("缺少 'name' 字段")
    
    if 'on' not in data:
        errors.append("缺少 'on' 字段")
    
    if 'jobs' not in data:
        errors.append("缺少 'jobs' 字段")
    
    # 检查 jobs
    if 'jobs' in data:
        for job_name, job in data['jobs'].items():
            if 'runs-on' not in job:
                errors.append(f"Job '{job_name}' 缺少 'runs-on' 字段")
            
            if 'steps' not in job:
                errors.append(f"Job '{job_name}' 缺少 'steps' 字段")
            else:
                for i, step in enumerate(job['steps']):
                    if 'name' not in step and 'uses' not in step and 'run' not in step:
                        errors.append(f"Job '{job_name}' 的步骤 {i+1} 缺少 'name', 'uses' 或 'run' 字段")
    
    return errors


def main():
    workflows_dir = Path('.github/workflows')
    
    if not workflows_dir.exists():
        print("❌ .github/workflows 目录不存在")
        sys.exit(1)
    
    workflow_files = list(workflows_dir.glob('*.yml')) + list(workflows_dir.glob('*.yaml'))
    
    if not workflow_files:
        print("❌ 未找到 workflow 文件")
        sys.exit(1)
    
    all_valid = True
    
    for workflow_file in workflow_files:
        print(f"\n验证: {workflow_file}")
        
        # 验证 YAML 语法
        valid, error = validate_yaml(workflow_file)
        if not valid:
            print(f"❌ YAML 语法错误: {error}")
            all_valid = False
            continue
        
        # 验证结构
        with open(workflow_file, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
        
        errors = validate_workflow_structure(data)
        if errors:
            print(f"❌ 结构错误:")
            for error in errors:
                print(f"  - {error}")
            all_valid = False
        else:
            print("✅ 验证通过")
    
    if all_valid:
        print("\n✅ 所有 workflow 文件验证通过")
        sys.exit(0)
    else:
        print("\n❌ 部分 workflow 文件验证失败")
        sys.exit(1)


if __name__ == '__main__':
    main()

