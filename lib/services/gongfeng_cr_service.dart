import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/process_output_decoder.dart';

typedef GongfengProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  if (!Platform.isWindows) {
    final command = buildShellCommand(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
    );
    return Process.run(
      '/bin/zsh',
      ['-lc', command],
      stdoutEncoding: latin1,
      stderrEncoding: latin1,
    );
  }
  return Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    stdoutEncoding: latin1,
    stderrEncoding: latin1,
  );
}

@visibleForTesting
String shellSingleQuoteForGf(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

@visibleForTesting
String buildShellCommand({
  required String executable,
  required List<String> arguments,
  String? workingDirectory,
}) {
  final parts = <String>[
    executable,
    ...arguments.map(shellSingleQuoteForGf),
  ];
  final command = parts.join(' ');
  final dir = workingDirectory?.trim();
  if (dir == null || dir.isEmpty) {
    return command;
  }
  return 'cd ${shellSingleQuoteForGf(dir)} && $command';
}

@visibleForTesting
List<String> buildGfCrCreateArgs({
  required String targetWc,
  required String title,
  required String description,
}) {
  final args = <String>['cr', 'create', targetWc, '--quick'];
  final trimmedTitle = title.trim();
  if (trimmedTitle.isNotEmpty) {
    args.addAll(['--title', trimmedTitle]);
  }
  final trimmedDescription = description.trim();
  if (trimmedDescription.isNotEmpty) {
    args.addAll(['--description', trimmedDescription]);
  }
  return args;
}

@visibleForTesting
String? extractCrIdFromGfOutput(String output) {
  final patterns = <RegExp>[
    RegExp(r'\bCRID\b\s*[:：#]?\s*(\d+)', caseSensitive: false),
    RegExp(r'\bIID\b\s*[:：#]?\s*(\d+)', caseSensitive: false),
    RegExp(r'\breview\s*id\b\s*[:：#]?\s*(\d+)', caseSensitive: false),
    RegExp(r'代码评审(?:\s*ID)?\s*[:：#]?\s*(\d+)', caseSensitive: false),
    RegExp(r'/(?:code_reviews|merge_requests|reviews)/(\d+)(?:\b|[/?#])',
        caseSensitive: false),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(output);
    if (match != null) return match.group(1);
  }
  return null;
}

@visibleForTesting
String? extractCodeReviewUrlFromGfOutput(String output) {
  final match = RegExp(
    r'https?://[^\s"<>]*(?:code_reviews|merge_requests|reviews)/\d+[^\s"<>]*',
    caseSensitive: false,
  ).firstMatch(output);
  return match?.group(0);
}

@visibleForTesting
String formatCrCommitSupplement(String crId, {String? title}) {
  final id = crId.trim();
  final trimmedTitle = title?.trim();
  if (trimmedTitle == null || trimmedTitle.isEmpty) {
    return '--crid=$id';
  }
  return '--crid=$id $trimmedTitle';
}

@visibleForTesting
bool isGfLoginRequiredOutput(String output) {
  final lower = output.toLowerCase();
  return lower.contains('please login first') ||
      lower.contains('not logged in') ||
      lower.contains('请先登录') ||
      lower.contains('未登录');
}

@visibleForTesting
String compactGfOutput(String stdout, String stderr) {
  final parts = <String>[
    if (stdout.trim().isNotEmpty) stdout.trim(),
    if (stderr.trim().isNotEmpty) stderr.trim(),
  ];
  return parts.join('\n').trim();
}

class GongfengCrCreateResult {
  final String crId;
  final String commitSupplement;
  final String? reviewUrl;
  final String stdout;
  final String stderr;

  const GongfengCrCreateResult({
    required this.crId,
    required this.commitSupplement,
    this.reviewUrl,
    required this.stdout,
    required this.stderr,
  });
}

class GongfengCrException implements Exception {
  final String message;
  final int? exitCode;
  final String output;
  final bool loginRequired;

  const GongfengCrException(
    this.message, {
    this.exitCode,
    this.output = '',
    this.loginRequired = false,
  });

  @override
  String toString() => message;
}

class GongfengCrService {
  static final GongfengCrService _instance = GongfengCrService._internal();

  factory GongfengCrService() => _instance;

  GongfengCrService._internal() : _runner = _defaultProcessRunner;

  @visibleForTesting
  GongfengCrService.forTesting({required GongfengProcessRunner runner})
      : _runner = runner;

  final GongfengProcessRunner _runner;

  Future<GongfengCrCreateResult> createCodeReview({
    required String targetWc,
    required String title,
    required String description,
  }) async {
    final args = buildGfCrCreateArgs(
      targetWc: targetWc,
      title: title,
      description: description,
    );
    final result = await _runner(
      'gf',
      args,
      workingDirectory: targetWc,
    );
    final stdout = decodeProcessOutput(result.stdout.toString());
    final stderr = decodeProcessOutput(result.stderr.toString());
    final output = compactGfOutput(stdout, stderr);

    if (result.exitCode != 0) {
      if (isGfLoginRequiredOutput(output)) {
        throw GongfengCrException(
          '工蜂 CLI 未登录，请先在终端执行 gf auth login 后重试',
          exitCode: result.exitCode,
          output: output,
          loginRequired: true,
        );
      }
      throw GongfengCrException(
        output.isEmpty ? 'gf cr create 执行失败' : output,
        exitCode: result.exitCode,
        output: output,
      );
    }

    final crId = extractCrIdFromGfOutput(output);
    if (crId == null || crId.isEmpty) {
      throw GongfengCrException(
        'Code Review 已发起，但未能从 gf 输出解析 CRID',
        exitCode: result.exitCode,
        output: output,
      );
    }

    return GongfengCrCreateResult(
      crId: crId,
      commitSupplement: formatCrCommitSupplement(crId, title: title),
      reviewUrl: extractCodeReviewUrlFromGfOutput(output),
      stdout: stdout,
      stderr: stderr,
    );
  }
}
