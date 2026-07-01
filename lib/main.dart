/// SVN 合并助手
///
/// 主应用入口
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'providers/merge_execution_state.dart';
import 'services/svn_service.dart';
import 'services/storage_service.dart';
import 'services/logger_service.dart';
import 'services/window_state_service.dart';
import 'screens/main_screen_v3.dart';

/// 应用初始化阶段的三态视图标签——决定 [AppInitializer] 渲染哪个 widget 子树。
///
/// **核心契约 — 互斥三态**：
/// - [loading]：正在初始化（显示 spinner）
/// - [error]：初始化失败（显示错误 + 重试按钮）
/// - [ready]：初始化成功（渲染 MainScreenV3）
///
/// 任意时刻只会处于其中一种状态——这是 [resolveAppInitializerView] 的承诺。
enum AppInitializerView {
  loading,
  error,
  ready,
}

/// 把 `(isLoading, error)` 二元组映射成 [AppInitializerView] 三态。
///
/// **核心契约 — 优先级顺序（loading 优先于 error）**：
/// - `isLoading == true` → [AppInitializerView.loading]（**即使 error 也非 null
///   也优先显示 loading**——理由见下）；
/// - `isLoading == false` 且 `error != null` 且 `error!.isNotEmpty` →
///   [AppInitializerView.error]；
/// - 否则 → [AppInitializerView.ready]。
///
/// **为什么 loading 优先于 error**：
/// 初始化过程是异步的：上一次 `_init()` 失败后，用户点"重试"会先把 `isLoading`
/// 置 true、`error` 暂时仍保留旧值（在新一次 init 完成前不会被清空）。如果
/// error 优先，重试按下的瞬间用户会看到错误页**没变**——错觉以为按钮没响应；
/// loading 优先则立即看到 spinner，明确"我点击的操作生效了"。这条优先级是
/// **可见的用户体验承诺**，不是任意选择。
///
/// **为什么空字符串 `error == ''` 走 ready 而非 error**：
/// `AppState.error` 是 `String?`——某些初始化路径会把 error 显式置成空串而不是
/// null（例如清空旧错误的浅复位）。视空串为"无错误"避免让用户看到没有具体内容
/// 的错误页（"初始化失败：" 后面什么都没有，体验更差）。**注意这与
/// [formatAppInitializerErrorText] 的 fallback 是配套的**——后者对 null/空串
/// 返回相同占位符，但本函数会在 ready 路径就避开错误页，让 fallback 永远不被
/// 触发。两层保护：本函数过滤掉空串、formatter 兜底真出现的极端 null。
@visibleForTesting
AppInitializerView resolveAppInitializerView({
  required bool isLoading,
  required String? error,
}) {
  if (isLoading) return AppInitializerView.loading;
  if (error != null && error.isNotEmpty) return AppInitializerView.error;
  return AppInitializerView.ready;
}

/// 渲染初始化失败页面上的错误文案：`'初始化失败：${error ?? "未知错误"}'`。
///
/// **核心契约**：
/// - `error` 非空 → `'初始化失败：$error'`（**全角冒号 `：`，不是半角 `:`**——
///   中文 UI 字符串规范，与对话框 / 状态栏 / 日志中的全角冒号风格统一。这是
///   Round 47 字符串风格分层之外的另一条文案规范——单测显式断言不含半角 `:`）；
/// - `error == null` 或 `error.isEmpty` → `'初始化失败：未知错误'`。**注意**：
///   由于 [resolveAppInitializerView] 已经在 null/空串 时走 ready 路径，本
///   formatter 的 null/空串 兜底**理论上不会被实际渲染**——但仍然要正确（防御
///   性，万一未来 caller 路径改变）。
/// - **不**对 `error` 做 trim：上游已经过 [resolveAppInitializerView] 的
///   isNotEmpty 校验，进入这里的 error **已经至少有一个字符**——重复 trim
///   反而会吞掉合法的全空格错误（虽然罕见，但 trim 不是本层职责）。
/// - **不**追加换行 / 句号：caller 自己决定换行（错误页可能横向也可能竖向）。
@visibleForTesting
String formatAppInitializerErrorText(String? error) {
  if (error == null || error.isEmpty) return '初始化失败：未知错误';
  return '初始化失败：$error';
}

/// 判定一条 Flutter 框架异常是否是"已知的键盘事件 bug"——已知 bug 走 warn
/// 不走 error，**不**呈现红屏。
///
/// **核心契约**：
/// - **同时**包含字符串 `'KeyUpEvent'` 与 `'HardwareKeyboard'` → `true`；
/// - 仅包含其中一个 → `false`（**故意要求两个都在**：单 `'KeyUpEvent'` 匹配会
///   把所有键盘相关异常都吞掉，太宽；单 `'HardwareKeyboard'` 同理）；
/// - 大小写敏感：`'keyupevent'` → `false`。Flutter 框架的异常文本大小写稳定，
///   按字面匹配；归一化反而会让"未来不同形式的真实异常"被静默吞掉。
/// - 空字符串 → `false`（异常总会有内容；空串视为非匹配）。
/// - **为什么这条逻辑必须 testable**：这个过滤是"用户看到红屏 / 看到 warn 日志"
///   的分水岭。如果未来有人想"优化"逻辑（比如改成单条件），用户体验会急剧变化——
///   单测显式断言 `'仅 KeyUpEvent'` 与 `'仅 HardwareKeyboard'` 都不匹配，锁定
///   "必须双关键字"的契约。
/// - **不**用正则——`String.contains` 已足够；引入正则会让"未来精确匹配某个
///   stack frame 路径"的需求更难实现（应该新增独立函数而非复用本函数）。
@visibleForTesting
bool isFlutterKeyboardFrameworkBug(String exceptionString) =>
    exceptionString.contains('KeyUpEvent') &&
    exceptionString.contains('HardwareKeyboard');

/// 判定应用启动后是否应该自动加载 mergeinfo 缓存。
///
/// **核心契约**（4 个条件全部 AND）：
/// - `lastSourceUrl != null` **且** `lastSourceUrl.isNotEmpty`
/// - `lastTargetWc != null` **且** `lastTargetWc.isNotEmpty`
/// - 任意一条 false → 整体 false（**不做"有一个就先加载"的部分启动**——
///   mergeinfo 必须 source + target 两端都齐才有意义，部分加载会让用户看到
///   错误的、过期的合并图）；
/// - **空字符串与 null 等价对待**：StorageService 在某些边缘情况下可能写回
///   空串而非 null（例如用户清空表单后保存），两者都视为"无值"——4 个 ANDs
///   覆盖完整真值表（4 维布尔 = 16 种组合，仅一种返回 true）。
/// - **不**校验 URL 是否合法（`'invalid url'` 也会触发自动加载）：合法性校验
///   由下游 `appState.loadMergeInfo()` 负责，本函数只是"是否要尝试"的门控。
///   过早拒绝合法但格式特殊的 URL 反而会让用户怀疑"为什么没自动加载"。
/// - **不**校验 working copy 路径是否存在：可能用户当前没插 U 盘，本次启动
///   不能用，但配置仍然有效；强行不加载会丢失"用户回到环境后立即看到上次配置"
///   的体验。
@visibleForTesting
bool shouldAutoLoadMergeInfoOnStartup({
  required String? lastSourceUrl,
  required String? lastTargetWc,
}) =>
    lastSourceUrl != null &&
    lastSourceUrl.isNotEmpty &&
    lastTargetWc != null &&
    lastTargetWc.isNotEmpty;

void main() async {
  // 捕获所有未处理的异步异常
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    AppLogger.app.info('===== SVN 合并助手启动 =====');
    AppLogger.app.info('时间: ${DateTime.now()}');
    AppLogger.app.info('Flutter 绑定已初始化');

    // 捕获 Flutter 框架异常
    FlutterError.onError = (FlutterErrorDetails details) {
      // 过滤掉已知的 Flutter 框架键盘事件异常（这些是框架 bug，不影响功能）
      final exceptionString = details.exceptionAsString();
      if (isFlutterKeyboardFrameworkBug(exceptionString)) {
        // 这是 Flutter 框架的已知问题，只记录警告，不显示错误界面
        AppLogger.app
            .warn('Flutter 键盘事件异常（框架问题，已忽略）: ${details.exceptionAsString()}');
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

    await WindowStateService().initAndRestore();

    runApp(const SvnMergeAssistantApp());

    // 记录应用启动完成
    AppLogger.app.info('应用已启动（runApp 完成）');
  }, (error, stackTrace) {
    // 捕获所有未被 try-catch 捕获的异步异常
    AppLogger.app.error('未处理的异步异常（可能导致应用退出）', error, stackTrace);
    // 注意：这里不应该调用 exit()，让 Flutter 框架处理异常
  });
}

/// **R130 cross-provider 通信反模式审计 — 应用根 MultiProvider 平行注册**：
///
/// 全 lib 内 cross-provider 通信链路按 4 档分类（首次形式化的 4 档框架，扩展自 R128/R129 的 3 档模板）：
///
/// **档 1 = 直接持有引用（provider/service 字段）**：
///   - lib 内 0 处 provider → provider 直接持有（**两个 provider 互不引用**）。
///   - lib 内 8 处 provider → service 直接持有（AppState 持有 4 service / MergeExecutionState 持有 4 service）；
///     service 是 stateless 单例，**不参与 ChangeNotifier 通信链**——视为档 1 service-持有子型。
///
/// **档 2 = Provider.of(context, listen: false) / context.read**：
///   - 仅在事件回调（按钮点击、表单提交、翻页等）+ `_AppInitializerState._init()` 启动期内使用。
///   - 一次性读取、不订阅、不触发 rebuild。
///   - lib 内 ~24 处调用，集中在 main.dart:227-228 + main_screen_v3.dart 操作回调。
///
/// **档 3 = Consumer / context.watch / Selector（订阅式 rebuild）**：
///   - lib 内**仅 2 处** Consumer 站点：(a) main.dart:259 `Consumer<AppState>`（启动期 loading/error 视图）；
///     (b) main_screen_v3.dart:1594 `Consumer2<AppState, MergeExecutionState>`（主屏幕双 provider 协调）。
///   - 0 处 `context.watch` / 0 处 `Selector` —— 全部走 Consumer 显式 builder pattern。
///
/// **档 4 = ChangeNotifier addListener / removeListener（命令式订阅）**：
///   - lib 内 **0 处**（widget 不订阅 provider、provider 不订阅 provider、provider 不订阅 service）。
///   - 这是设计选择：所有 ChangeNotifier 订阅都走 framework 接管的 Consumer 路径，避免手工 listener 配对的
///     dispose 责任泄漏。R129 widget lifecycle 维度未发现 addListener/removeListener pair，
///     是 R130 档 4 = 0 的反向证据；两轮互证。
///
/// **跨档 4 不变量 I1/I2/I3/I4（与 R128/R129 同模板）**：
///   - (I1) **provider → provider 反模式 = 0**：任一 provider 不持有另一 provider 的引用，
///     避免 ChangeNotifier 双向通知 → 循环 rebuild → stack overflow。
///     验证：grep `final \w+State \w+ =` × `extends ChangeNotifier`，0 处命中。
///   - (I2) **档 2 必带 `listen: false`**：事件回调内 read 不可触发 rebuild。
///     未来若有人改成 `listen: true` 等价于 `context.watch`，会让回调内 read 引发 rebuild
///     → setState during build assertion。doc-as-test 锁所有档 2 站点带 `listen: false`。
///   - (I3) **档 3 订阅必由 widget 主动声明**：所有 Consumer/Consumer2 出现位置必为 build() 内
///     而非 provider 类内（provider 内出现 Consumer 即跨界 + framework 误用）。
///   - (I4) **档 4 = 0 是设计契约不是巧合**：lib 内引入 addListener/removeListener
///     必须先升档 R130 重新评估、加 dispose 配对锁——保持 0 是 widget lifecycle dispose 责任最小化。
///
/// **与 R128/R129 的接合面**：
///   - R128 锁 provider **生产端**（mutator → notify 的触发协议）；R129 锁 widget **消费端**生命周期
///     （dispose owned Disposable）；R130 锁 **生产-消费链路本身**（哪些 widget/provider 通过哪种 channel
///     连到哪个 provider）。三者互补：R128 答"何时 notify"、R129 答"消费方何时释放"、R130 答"链路怎么连"。
///
/// **三档框架第 10 次复用（升级到 4 档框架）**：R98 异常 / R119 异步错误 / R120 等待 / R121 release fn /
///   R125 release step / R126 init step / R127 init step + 嵌套 / R128 trigger / R129 lifecycle /
///   **R130 cross-provider 通信** —— 首次扩展为 4 档（增加档 4 命令式 listener），证明三档框架可
///   按需升档但保持 N-tuple invariance 模板（4 不变量与档位正交）。
///
/// **注册结构契约**：本 MultiProvider 用**平行注册**（两 provider 顺序无依赖）。
/// 若未来需要派生 provider（B 依赖 A），改为 `ChangeNotifierProxyProvider2` 而非
/// 在 B 内 `final A _a` 直接持有——后者破坏 I1。
class SvnMergeAssistantApp extends StatelessWidget {
  const SvnMergeAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => MergeExecutionState()),
      ],
      child: MaterialApp(
        title: 'SVN 合并助手',
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
    final mergeState = Provider.of<MergeExecutionState>(context, listen: false);

    await appState.init();
    await mergeState.init();

    // 如果有上次使用的 sourceUrl 和 targetWc，自动加载 mergeinfo 缓存
    if (shouldAutoLoadMergeInfoOnStartup(
      lastSourceUrl: appState.lastSourceUrl,
      lastTargetWc: appState.lastTargetWc,
    )) {
      AppLogger.app.info('正在加载 mergeinfo 缓存...');
      // 先加载缓存（快速显示），然后后台静默刷新
      // R119 档 1（fire-and-forget then 链）：故意不 await——本函数 _init 还
      // 要继续 build UI、不能被慢 I/O 阻塞。错误处理由 [AppState.loadMergeInfo]
      // 内部 try-catch 完成（lib/providers/app_state.dart:559 catch 已落
      // AppLogger.app.error 日志），所以 then 链只负责串"加载完 → 后台静默
      // 刷新"的顺序。**不**用 helper [silentlyDiscardAsyncError] 包：那是
      // 档 2（"故意丢"），档 1 不丢——错误已在 callee 内部 sidechannel 化。
      appState.loadMergeInfo().then((_) {
        AppLogger.app.info('MergeInfo 缓存加载完成');
        // 后台静默刷新 mergeinfo（检测程序外的合并操作）
        AppLogger.app.info('后台静默刷新 mergeinfo...');
        appState.loadMergeInfo(forceRefresh: true).then((_) {
          AppLogger.app.info('MergeInfo 后台刷新完成');
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final view = resolveAppInitializerView(
          isLoading: appState.isLoading,
          error: appState.error,
        );
        switch (view) {
          case AppInitializerView.loading:
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          case AppInitializerView.error:
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(formatAppInitializerErrorText(appState.error)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _init,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          case AppInitializerView.ready:
            return const MainScreenV3();
        }
      },
    );
  }
}
