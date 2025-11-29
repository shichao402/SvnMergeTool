/// SVN 自动合并工具 - Flutter 版本
/// 
/// 主应用入口

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'providers/merge_state.dart';
import 'services/svn_service.dart';
import 'services/storage_service.dart';
import 'services/logger_service.dart';
import 'screens/main_screen.dart';

void main() async {
  // 捕获所有未处理的异步异常
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    AppLogger.app.info('===== SVN 自动合并工具启动 =====');
    AppLogger.app.info('时间: ${DateTime.now()}');
    AppLogger.app.info('Flutter 绑定已初始化');

    // 捕获 Flutter 框架异常
    FlutterError.onError = (FlutterErrorDetails details) {
      // 过滤掉已知的 Flutter 框架键盘事件异常（这些是框架 bug，不影响功能）
      final exceptionString = details.exceptionAsString();
      if (exceptionString.contains('KeyUpEvent') && 
          exceptionString.contains('HardwareKeyboard')) {
        // 这是 Flutter 框架的已知问题，只记录警告，不显示错误界面
        AppLogger.app.warn('Flutter 键盘事件异常（框架问题，已忽略）: ${details.exceptionAsString()}');
        return;
      }
      
      AppLogger.app.error(
        'Flutter 框架异常: ${details.exceptionAsString()}',
        details.exception,
        details.stack,
      );
      // 在调试模式下也显示原始错误
      FlutterError.presentError(details);
    };

    // 初始化服务
    try {
      await SvnService().init();
      AppLogger.app.info('SVN 服务初始化成功');
    } catch (e, stackTrace) {
      AppLogger.app.error('SVN 服务初始化失败', e, stackTrace);
    }

    try {
      await StorageService().init();
      AppLogger.app.info('存储服务初始化成功');
    } catch (e, stackTrace) {
      AppLogger.app.error('存储服务初始化失败', e, stackTrace);
    }

    runApp(const SvnMergeToolApp());
    
    // 记录应用启动完成
    AppLogger.app.info('应用已启动（runApp 完成）');
  }, (error, stackTrace) {
    // 捕获所有未被 try-catch 捕获的异步异常
    AppLogger.app.error('未处理的异步异常（可能导致应用退出）', error, stackTrace);
    // 注意：这里不应该调用 exit()，让 Flutter 框架处理异常
  });
}

class SvnMergeToolApp extends StatelessWidget {
  const SvnMergeToolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => MergeState()),
      ],
      child: MaterialApp(
        title: 'SVN 自动合并工具',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const AppInitializer(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

/// 应用初始化器
/// 
/// 在显示主界面前初始化应用状态
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final mergeState = Provider.of<MergeState>(context, listen: false);

    await appState.init();
    await mergeState.init();
    
    // 初始化完成后，从 MergeState 加载所有已完成的合并记录
    // 只记录本程序合并过的记录（不再通过 mergeinfo 检查）
    final mergedRevisions = mergeState.getMergedRevisions();
    if (mergedRevisions.isNotEmpty) {
      appState.updateMergedStatusFromMergeState(mergeState);
      AppLogger.app.info('已加载 ${mergedRevisions.length} 个本程序合并过的 revision');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        if (appState.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (appState.error != null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('初始化失败：${appState.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _init,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }

        return const MainScreen();
      },
    );
  }
}

