import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'logger_service.dart';

/// 工蜂 OAuth2 认证服务
///
/// 提供工蜂 Git 的 OAuth2 认证功能，包括：
/// - 获取授权（打开浏览器让用户授权）
/// - 自动刷新 Token
/// - 安全存储 Token
///
/// 使用方法：
/// ```dart
/// final auth = GongfengAuthService.instance;
/// final token = await auth.getAccessToken();
/// // 使用 token 调用 API
/// ```
class GongfengAuthService {
  GongfengAuthService._();
  static final GongfengAuthService instance = GongfengAuthService._();

  static const String _baseUrl = 'https://git.woa.com';
  
  // OAuth2 应用配置
  static const String _clientId = 'a8e6b05ee35f4aed956ed66df3c493fe';
  static const String _clientSecret = '16e99d24ce504dcb814e59c13a191ef8';
  static const String _redirectUri = 'http://localhost:18080/oauth/callback';
  
  // 授权范围
  static const List<String> _scopes = [
    'api',  // API 访问权限
  ];

  /// Token 存储文件路径
  String get _tokenFilePath {
    final home = Platform.environment['HOME'] ?? 
                 Platform.environment['USERPROFILE'] ?? 
                 '.';
    return '$home/.svn_flow/gongfeng_token.json';
  }

  /// 缓存的 Token
  _TokenInfo? _cachedToken;

  /// 获取有效的 Access Token
  ///
  /// 优先使用缓存，过期则自动刷新，无 Token 则引导用户授权
  Future<String> getAccessToken() async {
    // 1. 尝试从缓存获取
    if (_cachedToken != null && !_cachedToken!.isExpired) {
      return _cachedToken!.accessToken;
    }

    // 2. 尝试从文件加载
    _cachedToken = await _loadToken();
    if (_cachedToken != null) {
      // 检查是否过期
      if (!_cachedToken!.isExpired) {
        return _cachedToken!.accessToken;
      }
      
      // 尝试刷新
      if (_cachedToken!.canRefresh) {
        try {
          await _refreshToken();
          return _cachedToken!.accessToken;
        } catch (e) {
          AppLogger.app.warning('Token 刷新失败，需要重新授权: $e');
        }
      }
    }

    // 3. 需要用户授权
    await _authorize();
    return _cachedToken!.accessToken;
  }

  /// 检查是否已授权
  Future<bool> isAuthorized() async {
    if (_cachedToken != null && !_cachedToken!.isExpired) {
      return true;
    }
    
    _cachedToken = await _loadToken();
    if (_cachedToken != null && !_cachedToken!.isExpired) {
      return true;
    }
    
    // 尝试刷新
    if (_cachedToken != null && _cachedToken!.canRefresh) {
      try {
        await _refreshToken();
        return true;
      } catch (_) {
        return false;
      }
    }
    
    return false;
  }

  /// 清除授权
  Future<void> clearAuthorization() async {
    _cachedToken = null;
    final file = File(_tokenFilePath);
    if (await file.exists()) {
      await file.delete();
    }
    AppLogger.app.info('已清除工蜂授权');
  }

  /// 引导用户进行授权
  Future<void> _authorize() async {
    if (_clientId.isEmpty || _clientSecret.isEmpty) {
      throw Exception('OAuth 应用未配置，请先在工蜂创建 OAuth 应用并配置 clientId 和 clientSecret');
    }

    AppLogger.app.info('开始工蜂 OAuth2 授权流程...');

    // 生成随机 state 用于 CSRF 防护
    final state = _generateRandomString(32);

    // 构建授权 URL
    final authUrl = Uri.parse('$_baseUrl/oauth/authorize').replace(
      queryParameters: {
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'response_type': 'code',
        'state': state,
        'scope': _scopes.join(' '),
      },
    );

    // 启动本地服务器接收回调
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 18080);
    AppLogger.app.info('本地回调服务器启动在: http://localhost:18080');

    // 打开浏览器
    await _openBrowser(authUrl.toString());
    AppLogger.app.info('已打开浏览器，请在浏览器中完成授权...');

    // 等待回调
    final completer = Completer<String>();
    
    server.listen((request) async {
      if (request.uri.path == '/oauth/callback') {
        final code = request.uri.queryParameters['code'];
        final returnedState = request.uri.queryParameters['state'];
        final error = request.uri.queryParameters['error'];

        if (error != null) {
          // 返回错误页面
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(_buildHtmlResponse('授权失败', '错误: $error', false));
          await request.response.close();
          completer.completeError(Exception('授权失败: $error'));
        } else if (code != null && returnedState == state) {
          // 返回成功页面
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write(_buildHtmlResponse('授权成功', '您可以关闭此页面了', true));
          await request.response.close();
          completer.complete(code);
        } else {
          request.response
            ..statusCode = 400
            ..write('无效的请求');
          await request.response.close();
        }
      } else {
        request.response
          ..statusCode = 404
          ..write('Not Found');
        await request.response.close();
      }
    });

    try {
      // 等待授权码，超时 5 分钟
      final code = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException('授权超时'),
      );

      // 用授权码换取 Token
      await _exchangeCodeForToken(code);
      AppLogger.app.info('工蜂授权成功！');
    } finally {
      await server.close();
    }
  }

  /// 用授权码换取 Token
  Future<void> _exchangeCodeForToken(String code) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/oauth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
        'redirect_uri': _redirectUri,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('获取 Token 失败: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _cachedToken = _TokenInfo.fromJson(data);
    await _saveToken();
  }

  /// 刷新 Token
  Future<void> _refreshToken() async {
    if (_cachedToken?.refreshToken == null) {
      throw Exception('没有可用的 refresh token');
    }

    AppLogger.app.info('正在刷新工蜂 Token...');

    final response = await http.post(
      Uri.parse('$_baseUrl/oauth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'refresh_token': _cachedToken!.refreshToken,
        'grant_type': 'refresh_token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('刷新 Token 失败: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _cachedToken = _TokenInfo.fromJson(data);
    await _saveToken();
    
    AppLogger.app.info('Token 刷新成功');
  }

  /// 保存 Token 到文件
  Future<void> _saveToken() async {
    if (_cachedToken == null) return;

    final file = File(_tokenFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_cachedToken!.toJson()));
  }

  /// 从文件加载 Token
  Future<_TokenInfo?> _loadToken() async {
    final file = File(_tokenFilePath);
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return _TokenInfo.fromJson(data);
    } catch (e) {
      AppLogger.app.warning('加载 Token 失败: $e');
      return null;
    }
  }

  /// 打开浏览器
  Future<void> _openBrowser(String url) async {
    final String command;
    final List<String> args;

    if (Platform.isMacOS) {
      command = 'open';
      args = [url];
    } else if (Platform.isWindows) {
      command = 'start';
      args = ['', url];
    } else {
      command = 'xdg-open';
      args = [url];
    }

    await Process.run(command, args);
  }

  /// 生成随机字符串
  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    return List.generate(length, (i) => chars[(random + i * 7) % chars.length]).join();
  }

  /// 构建 HTML 响应页面
  String _buildHtmlResponse(String title, String message, bool success) {
    final color = success ? '#4CAF50' : '#f44336';
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>$title</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      margin: 0;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    }
    .container {
      text-align: center;
      background: white;
      padding: 40px 60px;
      border-radius: 16px;
      box-shadow: 0 10px 40px rgba(0,0,0,0.2);
    }
    .icon {
      font-size: 64px;
      margin-bottom: 20px;
    }
    h1 {
      color: $color;
      margin: 0 0 10px 0;
    }
    p {
      color: #666;
      margin: 0;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">${success ? '✓' : '✗'}</div>
    <h1>$title</h1>
    <p>$message</p>
  </div>
</body>
</html>
''';
  }
}

/// Token 信息
class _TokenInfo {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final DateTime? refreshExpiresAt;

  _TokenInfo({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    this.refreshExpiresAt,
  });

  /// 是否过期（提前 5 分钟认为过期）
  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  /// 是否可以刷新（refresh token 未过期）
  bool get canRefresh {
    if (refreshToken == null) return false;
    if (refreshExpiresAt == null) return true;  // 如果没有过期时间，假设可以刷新
    return DateTime.now().isBefore(refreshExpiresAt!);
  }

  factory _TokenInfo.fromJson(Map<String, dynamic> json) {
    final expiresIn = json['expires_in'] as int? ?? 7200;
    final createdAt = json['created_at'] as int? ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    
    return _TokenInfo(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.fromMillisecondsSinceEpoch((createdAt + expiresIn) * 1000),
      // refresh token 默认 30 天过期
      refreshExpiresAt: json['refresh_token'] != null
          ? DateTime.fromMillisecondsSinceEpoch((createdAt + 30 * 24 * 3600) * 1000)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.millisecondsSinceEpoch,
    'refresh_expires_at': refreshExpiresAt?.millisecondsSinceEpoch,
  };

  factory _TokenInfo.fromStoredJson(Map<String, dynamic> json) {
    return _TokenInfo(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expires_at'] as int),
      refreshExpiresAt: json['refresh_expires_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['refresh_expires_at'] as int)
          : null,
    );
  }
}
