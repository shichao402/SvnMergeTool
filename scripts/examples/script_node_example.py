#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Script 节点示例脚本

这是一个 Script 节点的示例脚本，展示如何编写自定义脚本。

入口函数签名:
    def main(input: dict, var: dict, job: dict) -> dict

参数说明:
    - input: 上游节点输出的数据
    - var: 流程变量（可读写）
    - job: 任务上下文（只读）
        - jobId: 任务 ID
        - sourceUrl: SVN 源 URL
        - targetWc: 目标工作副本路径
        - currentRevision: 当前正在处理的版本号
        - revisions: 待合并的版本号列表
        - completedIndex: 已完成的版本索引
        - workDir: 工作目录

返回值说明:
    返回一个字典，包含以下字段:
    - port: 输出端口名称，默认 'success'，失败时用 'failure'
    - data: 输出数据字典，传递给下游节点
    - message: 执行结果消息
    - isSuccess: 是否成功，默认 True
    - setVariables: 要设置的流程变量（可选）

示例用法:
    1. 在流程图中添加 Script 节点
    2. 配置脚本路径指向此文件
    3. 入口函数设置为 'main'（默认）
"""


def main(input: dict, var: dict, job: dict) -> dict:
    """
    示例入口函数
    
    这个示例展示如何:
    1. 读取上游输入
    2. 读取流程变量
    3. 读取任务上下文
    4. 返回结果和设置变量
    """
    # 打印调试信息（会显示在节点日志中）
    print(f"[DEBUG] 收到输入: {input}")
    print(f"[DEBUG] 流程变量: {var}")
    print(f"[DEBUG] 任务信息: jobId={job.get('jobId')}, revision={job.get('currentRevision')}")
    
    # 示例：从上游获取数据
    upstream_message = input.get('message', '无消息')
    
    # 示例：读取流程变量
    counter = var.get('counter', 0)
    
    # 示例：处理逻辑
    new_counter = counter + 1
    
    # 返回结果
    return {
        'port': 'success',  # 或 'failure'
        'data': {
            'processedMessage': f"已处理: {upstream_message}",
            'counter': new_counter,
            'revision': job.get('currentRevision'),
        },
        'message': f'脚本执行成功，计数器: {new_counter}',
        'isSuccess': True,
        # 设置流程变量（可选）
        'setVariables': {
            'counter': new_counter,
            'lastProcessedRevision': job.get('currentRevision'),
        }
    }


def check_file_exists(input: dict, var: dict, job: dict) -> dict:
    """
    示例：检查文件是否存在
    
    配置入口函数为 'check_file_exists' 来使用此功能
    """
    import os
    
    file_path = input.get('filePath') or var.get('targetFile', '')
    
    if not file_path:
        return {
            'port': 'failure',
            'message': '未指定文件路径',
            'isSuccess': False,
        }
    
    exists = os.path.exists(file_path)
    
    return {
        'port': 'exists' if exists else 'not_exists',
        'data': {
            'filePath': file_path,
            'exists': exists,
        },
        'message': f"文件{'存在' if exists else '不存在'}: {file_path}",
        'isSuccess': True,
    }


def send_notification(input: dict, var: dict, job: dict) -> dict:
    """
    示例：发送通知（HTTP 请求）
    
    配置入口函数为 'send_notification' 来使用此功能
    """
    import urllib.request
    import json
    
    webhook_url = var.get('webhookUrl', '')
    if not webhook_url:
        return {
            'port': 'failure',
            'message': '未配置 webhookUrl 流程变量',
            'isSuccess': False,
        }
    
    # 构建通知内容
    payload = {
        'jobId': job.get('jobId'),
        'revision': job.get('currentRevision'),
        'message': input.get('message', '合并完成'),
        'status': 'success' if input.get('isSuccess', True) else 'failed',
    }
    
    try:
        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(
            webhook_url,
            data=data,
            headers={'Content-Type': 'application/json'},
        )
        
        with urllib.request.urlopen(req, timeout=30) as response:
            status = response.status
            body = response.read().decode('utf-8')
        
        return {
            'port': 'success',
            'data': {
                'statusCode': status,
                'response': body,
            },
            'message': f'通知发送成功 (HTTP {status})',
            'isSuccess': True,
        }
    except Exception as e:
        return {
            'port': 'failure',
            'message': f'通知发送失败: {e}',
            'isSuccess': False,
        }


# 本地测试
if __name__ == '__main__':
    # 模拟输入数据
    test_input = {'message': '测试消息', 'isSuccess': True}
    test_var = {'counter': 5, 'webhookUrl': 'https://example.com/webhook'}
    test_job = {
        'jobId': 12345,
        'sourceUrl': 'svn://example.com/trunk',
        'targetWc': '/path/to/wc',
        'currentRevision': 1001,
        'revisions': [1001, 1002, 1003],
        'completedIndex': 0,
        'workDir': '/path/to/wc',
    }
    
    print("=== 测试 main 函数 ===")
    result = main(test_input, test_var, test_job)
    print(f"结果: {json.dumps(result, indent=2, ensure_ascii=False)}")
    
    print("\n=== 测试 check_file_exists 函数 ===")
    result = check_file_exists({'filePath': '/etc/hosts'}, {}, test_job)
    print(f"结果: {json.dumps(result, indent=2, ensure_ascii=False)}")
    
    import json
