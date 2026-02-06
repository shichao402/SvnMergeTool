import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../services/gongfeng_auth_service.dart';
import '../../../services/logger_service.dart';
import '../../engine/execution_context.dart';
import '../../engine/node_output.dart';
import '../../registry/registry.dart';

/// 工蜂 Code Review 执行器
///
/// 功能：
/// 1. 获取当前工作目录的 SVN 变更
/// 2. 创建工蜂 Code Review 评审
/// 3. 轮询等待评审通过
/// 4. 输出 crid 参数供提交使用
///
/// API 说明：
/// - SVN 本地评审使用 /api/web/v1 接口（代码在本地模式）
/// - 认证头: Authorization: Bearer ${token}
class GongfengCrExecutor {
  /// 工蜂 API 基础地址
  static const String _baseUrl = 'https://git.woa.com';
  static const String _apiWebV1 = '$_baseUrl/api/web/v1';

  /// 评审状态常量
  static const String _statusApproved = 'approved';
  // ignore: unused_field - 保留供未来使用
  static const String _statusApproving = 'approving';
  static const String _statusChangeDenied = 'change_denied';
  // ignore: unused_field - 保留供未来使用
  static const String _statusChangeRequired = 'change_required';
  static const String _statusClosed = 'closed';

  /// 执行工蜂 CR 节点
  static Future<NodeOutput> execute({
    required Map<String, dynamic> input,
    required Map<String, dynamic> config,
    required ExecutionContext context,
  }) async {
    final targetWc = context.job.targetWc;
    final sourceUrl = context.job.sourceUrl;

    if (targetWc.isEmpty) {
      return NodeOutput.failure(message: '缺少目标工作副本路径');
    }

    context.info('开始工蜂 CR 流程...');
    context.info('工作目录: $targetWc');
    context.info('源分支 URL: $sourceUrl');

    try {
      // Step 1: 获取认证 Token
      context.info('正在获取工蜂认证...');
      final token = await GongfengAuthService.instance.getAccessToken();
      context.info('认证成功');

      // Step 2: 获取 SVN 信息
      context.info('正在获取 SVN 信息...');
      final svnInfo = await _getSvnInfo(targetWc);
      final svnUrl = svnInfo['URL'] ?? '';
      final repoRoot = svnInfo['Repository Root'] ?? '';

      if (svnUrl.isEmpty) {
        return NodeOutput.failure(message: '无法获取 SVN URL');
      }

      context.info('SVN URL: $svnUrl');
      context.info('Repository Root: $repoRoot');

      // Step 3: 获取工蜂项目信息
      context.info('正在获取工蜂项目信息...');
      final project = await _getSvnProject(token, repoRoot.isNotEmpty ? repoRoot : svnUrl);

      if (project == null) {
        return NodeOutput.failure(
          message: '无法找到对应的工蜂项目。请确保 SVN 仓库已关联到工蜂。\nSVN URL: $svnUrl',
        );
      }

      final projectId = project['id'] as int;
      final projectPath = project['fullPath'] as String;
      context.info('工蜂项目 ID: $projectId');
      context.info('工蜂项目路径: $projectPath');

      // Step 4: 获取本地 diff
      context.info('正在获取本地变更...');
      final rawDiff = await _getSvnDiff(targetWc);

      if (rawDiff.trim().isEmpty) {
        return NodeOutput.failure(message: '没有发现本地变更。请确保工作副本有未提交的修改。');
      }

      context.info('原始 diff 大小: ${rawDiff.length} 字节');

      // Step 5: 过滤 diff
      context.info('正在处理 diff 内容...');
      final (diffContent, changedFiles) = _filterSvnDiff(targetWc, rawDiff);

      if (diffContent.isEmpty) {
        return NodeOutput.failure(message: '处理 diff 后内容为空');
      }

      context.info('处理后 diff 大小: ${diffContent.length} 字节');
      context.info('变更文件数: ${changedFiles.length}');
      for (final f in changedFiles.take(10)) {
        context.info('  - $f');
      }
      if (changedFiles.length > 10) {
        context.info('  ... 还有 ${changedFiles.length - 10} 个文件');
      }

      // Step 6: 获取预设评审人（可选）
      String reviewerIds = config['reviewerIds'] as String? ?? '';
      if (reviewerIds.isEmpty) {
        context.info('正在获取预设评审人...');
        final fileUrls = changedFiles.map((f) => '$svnUrl/$f').toList();
        final preset = await _getPresetReviewers(token, projectId, fileUrls);

        if (preset != null && preset['reviewers'] != null) {
          final reviewers = preset['reviewers'] as List;
          reviewerIds = reviewers.map((r) => r['id'].toString()).join(',');
          context.info('预设评审人: ${reviewers.map((r) => r['username']).toList()}');
        } else {
          context.info('未找到预设评审人');
        }
      }

      // Step 7: 构建标题和描述
      final revision = context.job.currentRevision;
      final jobId = context.job.jobId;

      final title = revision != null && revision > 0
          ? '[自动合并] r$revision'
          : '[自动合并] Job $jobId';

      final descriptionLines = [
        '自动合并任务创建的代码评审',
        '',
        '变更文件列表:',
        ...changedFiles.take(20).map((f) => '- $f'),
        if (changedFiles.length > 20) '... 还有 ${changedFiles.length - 20} 个文件',
        '',
        '---',
        'Job ID: $jobId',
        '版本号: $revision',
        '工作目录: $targetWc',
      ];
      final description = descriptionLines.join('\n');

      context.info('评审标题: $title');

      // Step 8: 创建评审
      context.info('正在创建代码评审...');
      final review = await _createSvnReview(
        token: token,
        projectId: projectId,
        svnUrl: svnUrl,
        diffContent: diffContent,
        title: title,
        description: description,
        reviewerIds: reviewerIds,
      );

      if (review == null) {
        return NodeOutput.failure(message: '创建评审失败');
      }

      final reviewId = review['id'] as int;
      final reviewIid = review['iid'] as int;
      final reviewUrl = '$_baseUrl/$projectPath/reviews/$reviewIid';

      context.info('评审创建成功!');
      context.info('Review ID: $reviewId, IID: $reviewIid');
      context.info('Review URL: $reviewUrl');

      // 保存到上下文变量
      context.setVariable('crid', reviewId);
      context.setVariable('cridArg', '--crid=$reviewId');
      context.setVariable('reviewUrl', reviewUrl);
      context.setVariable('reviewIid', reviewIid);

      // Step 9: 轮询等待评审通过
      final pollInterval = (config['pollInterval'] as int?) ?? 30;
      final timeout = (config['timeout'] as int?) ?? 3600;
      final waitForApproval = (config['waitForApproval'] as bool?) ?? true;

      if (!waitForApproval) {
        context.info('已配置不等待评审通过，直接返回成功');
        return NodeOutput.success(
          data: {
            'crid': reviewId,
            'cridArg': '--crid=$reviewId',
            'reviewIid': reviewIid,
            'reviewUrl': reviewUrl,
            'state': 'approving',
          },
          message: '评审已创建 (CR ID: $reviewId)',
        );
      }

      context.info('开始轮询评审状态，间隔 $pollInterval 秒，超时 $timeout 秒');
      final startTime = DateTime.now();
      String? lastState;

      while (true) {
        // 检查取消
        context.checkCancelled();
        await context.checkPause();

        final elapsed = DateTime.now().difference(startTime).inSeconds;

        // 检查超时
        if (elapsed >= timeout) {
          return NodeOutput.port(
            'timeout',
            data: {
              'crid': reviewId,
              'reviewIid': reviewIid,
              'reviewUrl': reviewUrl,
              'state': lastState,
            },
            message: '评审等待超时 ($timeout 秒)',
            isSuccess: false,
          );
        }

        // 查询评审状态
        try {
          final reviewInfo = await _getSvnReview(token, projectId, reviewIid);
          if (reviewInfo != null) {
            final currentState = reviewInfo['state'] as String?;

            if (currentState != lastState) {
              context.info('[${DateTime.now().toString().substring(11, 19)}] 评审状态: $currentState');
              lastState = currentState;
            }

            // 检查是否通过
            if (currentState == _statusApproved) {
              context.info('评审已通过!');
              return NodeOutput.success(
                data: {
                  'crid': reviewId,
                  'cridArg': '--crid=$reviewId',
                  'reviewIid': reviewIid,
                  'reviewUrl': reviewUrl,
                  'state': currentState,
                },
                message: '评审已通过 (CR ID: $reviewId)',
              );
            }

            // 检查是否被拒绝
            if (currentState == _statusChangeDenied || currentState == _statusClosed) {
              context.info('评审被拒绝或关闭');
              return NodeOutput.port(
                'rejected',
                data: {
                  'crid': reviewId,
                  'reviewIid': reviewIid,
                  'reviewUrl': reviewUrl,
                  'state': currentState,
                },
                message: '评审被拒绝 (状态: $currentState)',
                isSuccess: false,
              );
            }
          }
        } catch (e) {
          context.warning('查询评审状态失败: $e');
        }

        // 等待下次轮询
        final remaining = timeout - elapsed;
        final waitTime = remaining < pollInterval ? remaining : pollInterval;
        if (waitTime > 0) {
          context.debug('等待 $waitTime 秒后再次查询... (已等待 $elapsed/$timeout 秒)');
          await Future.delayed(Duration(seconds: waitTime));
        }
      }
    } catch (e, stackTrace) {
      AppLogger.app.error('工蜂 CR 执行失败: $e\n$stackTrace');
      return NodeOutput.failure(message: '工蜂 CR 执行失败: $e');
    }
  }

  /// 获取 SVN 信息
  static Future<Map<String, String>> _getSvnInfo(String workDir) async {
    final result = await Process.run('svn', ['info', workDir]);
    if (result.exitCode != 0) {
      throw Exception('svn info 失败: ${result.stderr}');
    }

    final info = <String, String>{};
    for (final line in (result.stdout as String).split('\n')) {
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        info[key] = value;
      }
    }
    return info;
  }

  /// 获取 SVN diff
  static Future<String> _getSvnDiff(String workDir) async {
    final result = await Process.run(
      'svn',
      ['diff', workDir],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw Exception('svn diff 失败: ${result.stderr}');
    }
    return result.stdout as String;
  }

  /// 过滤和处理 SVN diff 内容
  static (String, List<String>) _filterSvnDiff(String workDir, String diff) {
    final lines = diff.split('\n');
    final filtered = <String>[];
    final files = <String>[];
    var keep = false;
    var lastLine = '';
    var isHead = false;

    final normalizedWorkDir = workDir.replaceAll('\\', '/');

    for (var line in lines) {
      if (line.startsWith('Index:')) {
        var filepath = line.split(':')[1].trim().replaceAll('\\', '/');

        // Convert absolute path to relative
        if (filepath.startsWith(normalizedWorkDir)) {
          filepath = filepath.substring(normalizedWorkDir.length).replaceFirst(RegExp(r'^/'), '');
        } else {
          filepath = filepath.split('/').last;
        }

        if (filepath.isNotEmpty && !files.contains(filepath)) {
          files.add(filepath);
          line = 'Index: $filepath';
          keep = true;
        } else {
          keep = false;
        }
      }

      if (keep) {
        // Fix --- and +++ lines
        if (line.startsWith('--- ') && lastLine.trim() == '=' * 67) {
          final parts = line.substring(4).replaceAll('\\', '/').replaceAll(normalizedWorkDir, '');
          line = '--- ${parts.replaceFirst(RegExp(r'^/'), '')}';
          isHead = true;
        }
        if (line.startsWith('+++ ') && isHead) {
          final parts = line.substring(4).replaceAll('\\', '/').replaceAll(normalizedWorkDir, '');
          line = '+++ ${parts.replaceFirst(RegExp(r'^/'), '')}';
          isHead = false;
        }

        filtered.add(line);
      }

      lastLine = line;
    }

    // Use CRLF line endings (required by Gongfeng API)
    return (filtered.join('\r\n'), files);
  }

  /// 获取工蜂项目信息
  static Future<Map<String, dynamic>?> _getSvnProject(String token, String svnUrl) async {
    try {
      final encodedUrl = Uri.encodeComponent(svnUrl);
      final response = await http.get(
        Uri.parse('$_apiWebV1/svn/project/cli/analyze_project?fullPath=$encodedUrl'),
        headers: {
          'Authorization': 'Bearer $token',
          'User-Agent': 'SvnFlow/1.0',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      AppLogger.app.warn('获取工蜂项目信息失败: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      AppLogger.app.warn('获取工蜂项目信息异常: $e');
      return null;
    }
  }

  /// 获取预设评审人
  static Future<Map<String, dynamic>?> _getPresetReviewers(
    String token,
    int projectId,
    List<String> filePaths,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiWebV1/svn/projects/$projectId/path_rules/code_review/preset_config'),
        headers: {
          'Authorization': 'Bearer $token',
          'User-Agent': 'SvnFlow/1.0',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'filePaths': filePaths},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      AppLogger.app.warn('获取预设评审人异常: $e');
      return null;
    }
  }

  /// 创建 SVN 本地评审
  static Future<Map<String, dynamic>?> _createSvnReview({
    required String token,
    required int projectId,
    required String svnUrl,
    required String diffContent,
    required String title,
    required String description,
    required String reviewerIds,
  }) async {
    try {
      final body = <String, String>{
        'targetProjectId': projectId.toString(),
        'sourceProjectId': projectId.toString(),
        'diffContent': diffContent,
        'diffOnlyFileName': 'false',
        'targetPath': svnUrl,
        'sourcePath': svnUrl,
        'title': title,
        'description': description,
      };

      if (reviewerIds.isNotEmpty) {
        body['reviewerIds'] = reviewerIds;
      }

      final response = await http.post(
        Uri.parse('$_apiWebV1/svn/projects/$projectId/merge_requests'),
        headers: {
          'Authorization': 'Bearer $token',
          'User-Agent': 'SvnFlow/1.0',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      ).timeout(const Duration(seconds: 125));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      AppLogger.app.error('创建评审失败: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      AppLogger.app.error('创建评审异常: $e');
      return null;
    }
  }

  /// 获取 SVN 评审详情
  static Future<Map<String, dynamic>?> _getSvnReview(
    String token,
    int projectId,
    int reviewIid,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiWebV1/projects/$projectId/reviews/$reviewIid'),
        headers: {
          'Authorization': 'Bearer $token',
          'User-Agent': 'SvnFlow/1.0',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      AppLogger.app.warn('获取评审详情异常: $e');
      return null;
    }
  }

  /// 获取节点类型定义
  static NodeTypeDefinition get definition => NodeTypeDefinition(
        typeId: 'gongfeng_cr',
        name: '工蜂 CR',
        description: '创建工蜂代码评审，等待审批通过后继续',
        icon: Icons.rate_review,
        color: Colors.orange,
        category: '工蜂',
        inputs: const [PortSpec.defaultInput],
        outputs: const [
          PortSpec.success,
          PortSpec(id: 'rejected', name: '被拒绝', role: PortRole.error),
          PortSpec(id: 'timeout', name: '超时', role: PortRole.error),
          PortSpec.failure,
        ],
        params: const [
          ParamSpec(
            key: 'reviewerIds',
            label: '评审人 ID',
            type: ParamType.string,
            description: '评审人的工蜂用户 ID，多个用逗号分隔。留空则使用预设评审人。',
          ),
          ParamSpec(
            key: 'waitForApproval',
            label: '等待审批通过',
            type: ParamType.bool,
            defaultValue: true,
            description: '是否等待评审通过后再继续。如果关闭，创建评审后立即返回成功。',
          ),
          ParamSpec(
            key: 'pollInterval',
            label: '轮询间隔（秒）',
            type: ParamType.int,
            defaultValue: 30,
            description: '检查评审状态的间隔时间',
          ),
          ParamSpec(
            key: 'timeout',
            label: '超时时间（秒）',
            type: ParamType.int,
            defaultValue: 3600,
            description: '等待评审通过的最长时间。超时后从"超时"端口输出。',
          ),
        ],
        executor: execute,
      );
}
