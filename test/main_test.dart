import 'package:flutter_test/flutter_test.dart';
import 'package:svn_auto_merge/main.dart';

void main() {
  group('formatAppInitializerErrorText', () {
    test('error 非空 → "初始化失败：<error>"（全角冒号）', () {
      expect(
        formatAppInitializerErrorText('SVN 服务初始化失败'),
        '初始化失败：SVN 服务初始化失败',
      );
    });

    test('error == null → "初始化失败：未知错误"（兜底）', () {
      // 虽然 resolveAppInitializerView 已经在 null 时走 ready 路径让 formatter
      // 不会被实际渲染，但 formatter 仍然要正确（防御性，万一未来 caller 改路径）。
      expect(formatAppInitializerErrorText(null), '初始化失败：未知错误');
    });

    test('error 为空字符串 → "初始化失败：未知错误"（与 null 等价兜底）', () {
      // 同上：resolveAppInitializerView 已过滤空串走 ready，但 formatter 兜底相同。
      expect(formatAppInitializerErrorText(''), '初始化失败：未知错误');
    });

    test('使用全角冒号 "：" 而非半角 ":"（中文 UI 文案规范）', () {
      // 锁定文案规范：与对话框 / 状态栏 / 日志风格统一。
      final text = formatAppInitializerErrorText('foo');
      expect(text.contains('：'), isTrue);
      expect(text.contains('初始化失败:foo'), isFalse); // 半角冒号 + 无空格的写法
      expect(text.contains('初始化失败: foo'), isFalse); // 半角冒号 + 空格的写法
    });

    test('不对 error 做 trim：全空格保留', () {
      // 上游已经过 isNotEmpty 校验；本层不重复 trim，避免吞掉合法的边界内容。
      expect(formatAppInitializerErrorText('   '), '初始化失败：   ');
    });

    test('不追加换行 / 句号：caller 决定换行', () {
      final text = formatAppInitializerErrorText('error message');
      expect(text.endsWith('\n'), isFalse);
      expect(text.endsWith('。'), isFalse);
      expect(text.endsWith('.'), isFalse);
    });

    test('error 含特殊字符（换行 / Unicode）原样保留', () {
      expect(
        formatAppInitializerErrorText('网络错误\n请重试 🌐'),
        '初始化失败：网络错误\n请重试 🌐',
      );
    });
  });

  group('isFlutterKeyboardFrameworkBug', () {
    test('同时包含 KeyUpEvent + HardwareKeyboard → true', () {
      // 真实 Flutter 框架异常文本通常会同时包含两个关键字（一个在异常类型 / 消息里，
      // 一个在 stack trace 的 HardwareKeyboard.handleKeyEvent 帧里）。
      // 这里用同时含两词的合成示例锁定核心契约。
      const exception =
          "Assertion failed: KeyUpEvent received but HardwareKeyboard had no record of the key being pressed.";
      expect(
        isFlutterKeyboardFrameworkBug(exception),
        isTrue,
      );
    });

    test('仅包含 KeyUpEvent → false（必须双关键字）', () {
      // 只有一个关键字的异常不能匹配——避免吞掉所有键盘相关异常。
      expect(
        isFlutterKeyboardFrameworkBug('Some KeyUpEvent error in app code'),
        isFalse,
      );
    });

    test('仅包含 HardwareKeyboard → false（必须双关键字）', () {
      expect(
        isFlutterKeyboardFrameworkBug(
            'HardwareKeyboard initialization failed'),
        isFalse,
      );
    });

    test('两个关键字都不包含 → false', () {
      expect(
        isFlutterKeyboardFrameworkBug('Some unrelated Flutter exception'),
        isFalse,
      );
    });

    test('空字符串 → false', () {
      // 异常总会有内容；空串视为非匹配。
      expect(isFlutterKeyboardFrameworkBug(''), isFalse);
    });

    test('大小写敏感：keyupevent + hardwarekeyboard → false', () {
      // Flutter 异常文本大小写稳定；归一化反而会让"未来不同形式的真实异常"被静默吞掉。
      expect(
        isFlutterKeyboardFrameworkBug('keyupevent in hardwarekeyboard'),
        isFalse,
      );
    });

    test('关键字顺序无关：HardwareKeyboard 在前 + KeyUpEvent 在后 → true', () {
      // contains 不依赖顺序——这是 String.contains 的天然行为，显式锁定。
      expect(
        isFlutterKeyboardFrameworkBug('HardwareKeyboard ... KeyUpEvent'),
        isTrue,
      );
    });

    test('关键字嵌入更长的字符串 → true', () {
      expect(
        isFlutterKeyboardFrameworkBug(
            'prefix__KeyUpEvent__suffix__HardwareKeyboard__'),
        isTrue,
      );
    });
  });

  group('resolveAppInitializerView', () {
    test('isLoading == true → AppInitializerView.loading', () {
      expect(
        resolveAppInitializerView(isLoading: true, error: null),
        AppInitializerView.loading,
      );
    });

    test('isLoading == false + error == null → AppInitializerView.ready', () {
      expect(
        resolveAppInitializerView(isLoading: false, error: null),
        AppInitializerView.ready,
      );
    });

    test('isLoading == false + error 非空 → AppInitializerView.error', () {
      expect(
        resolveAppInitializerView(
            isLoading: false, error: '初始化失败：SVN 服务初始化失败'),
        AppInitializerView.error,
      );
    });

    test('isLoading == true + error 非空 → loading（loading 优先于 error）', () {
      // 关键契约：重试时 isLoading 先置 true，error 暂时还是旧值——
      // loading 优先确保用户立即看到 spinner（按钮响应感）。
      expect(
        resolveAppInitializerView(
            isLoading: true, error: '上次的错误尚未清空'),
        AppInitializerView.loading,
      );
    });

    test('isLoading == false + error 空字符串 → ready（与 null 等价）', () {
      // AppState 实际不会写空串，但作为防御性约定：空 error 走 ready 而非 error
      // 避免显示"初始化失败：" 后空白的尴尬错误页。
      expect(
        resolveAppInitializerView(isLoading: false, error: ''),
        AppInitializerView.ready,
      );
    });

    test('真值表 2×3=6 种组合：3 走 loading / 1 走 error / 2 走 ready', () {
      // 显式遍历 isLoading × error 的所有典型组合。
      // isLoading ∈ {true, false}, error ∈ {null, '', '某错误'} = 6 种。
      final loadings = [true, false];
      final errors = [null, '', '某错误'];
      var loadingCount = 0;
      var errorCount = 0;
      var readyCount = 0;
      for (final l in loadings) {
        for (final e in errors) {
          final view = resolveAppInitializerView(isLoading: l, error: e);
          switch (view) {
            case AppInitializerView.loading:
              loadingCount++;
            case AppInitializerView.error:
              errorCount++;
            case AppInitializerView.ready:
              readyCount++;
          }
        }
      }
      // isLoading=true × 任意 error → loading: 3 种
      expect(loadingCount, 3);
      // isLoading=false × error='某错误' → error: 1 种
      expect(errorCount, 1);
      // isLoading=false × error∈{null, ''} → ready: 2 种
      expect(readyCount, 2);
      expect(loadingCount + errorCount + readyCount, 6);
    });

    test('AppInitializerView 枚举有且仅有 3 个值（互斥三态）', () {
      // 锁定三态完整性——若未来添加第 4 态，本测试会强制 review。
      expect(AppInitializerView.values.length, 3);
      expect(AppInitializerView.values, contains(AppInitializerView.loading));
      expect(AppInitializerView.values, contains(AppInitializerView.error));
      expect(AppInitializerView.values, contains(AppInitializerView.ready));
    });
  });

  group('shouldAutoLoadMergeInfoOnStartup', () {
    test('两端都有合法值 → true', () {
      expect(
        shouldAutoLoadMergeInfoOnStartup(
          lastSourceUrl: 'svn://server/repo/trunk',
          lastTargetWc: '/Users/me/wc',
        ),
        isTrue,
      );
    });

    test('lastSourceUrl == null → false', () {
      expect(
        shouldAutoLoadMergeInfoOnStartup(
          lastSourceUrl: null,
          lastTargetWc: '/Users/me/wc',
        ),
        isFalse,
      );
    });

    test('lastTargetWc == null → false', () {
      expect(
        shouldAutoLoadMergeInfoOnStartup(
          lastSourceUrl: 'svn://server/repo/trunk',
          lastTargetWc: null,
        ),
        isFalse,
      );
    });

    test('lastSourceUrl 为空字符串 → false（与 null 等价对待）', () {
      // StorageService 边缘情况下可能写空串而非 null——空串与 null 等价对待。
      expect(
        shouldAutoLoadMergeInfoOnStartup(
          lastSourceUrl: '',
          lastTargetWc: '/Users/me/wc',
        ),
        isFalse,
      );
    });

    test('lastTargetWc 为空字符串 → false', () {
      expect(
        shouldAutoLoadMergeInfoOnStartup(
          lastSourceUrl: 'svn://server/repo/trunk',
          lastTargetWc: '',
        ),
        isFalse,
      );
    });

    test('两端都 null → false', () {
      expect(
        shouldAutoLoadMergeInfoOnStartup(
          lastSourceUrl: null,
          lastTargetWc: null,
        ),
        isFalse,
      );
    });

    test('两端都空字符串 → false', () {
      expect(
        shouldAutoLoadMergeInfoOnStartup(
          lastSourceUrl: '',
          lastTargetWc: '',
        ),
        isFalse,
      );
    });

    test('真值表 4 维：16 种组合中仅 1 种为 true', () {
      // 4 个布尔条件全部 AND——显式遍历真值表锁定。
      // 维度：sourceUrl ∈ {null, '', 'valid'} × targetWc ∈ {null, '', 'valid'}
      // = 9 种组合（不展开 null vs '' 内部差异，因为它们等价对待）
      // 仅 (sourceUrl='valid', targetWc='valid') 一种为 true。
      final urls = [null, '', 'svn://x'];
      final wcs = [null, '', '/wc'];
      var trueCount = 0;
      for (final u in urls) {
        for (final w in wcs) {
          if (shouldAutoLoadMergeInfoOnStartup(
              lastSourceUrl: u, lastTargetWc: w)) {
            trueCount++;
          }
        }
      }
      expect(trueCount, 1);
    });

    test('不校验 URL 合法性：非法 URL 也触发 true（合法性下游负责）', () {
      // 'invalid url' 也会触发自动加载——校验由下游 loadMergeInfo 负责。
      // 过早拒绝合法但格式特殊的 URL 反而会让用户怀疑"为什么没自动加载"。
      expect(
        shouldAutoLoadMergeInfoOnStartup(
          lastSourceUrl: 'not a url at all',
          lastTargetWc: '/wc',
        ),
        isTrue,
      );
    });

    test('不校验 working copy 路径存在性：不存在的路径也触发 true', () {
      // 用户可能没插 U 盘——配置仍然有效；强行不加载会丢失"回到环境后立即看到上次配置"的体验。
      expect(
        shouldAutoLoadMergeInfoOnStartup(
          lastSourceUrl: 'svn://x',
          lastTargetWc: '/this/path/definitely/does/not/exist/anywhere',
        ),
        isTrue,
      );
    });

    test('字符串只包含空白也算"非空"（不做 trim）', () {
      // 单测显式锁定：空白字符串 (' ') 长度非 0，走 isNotEmpty=true 路径。
      // 这是边界——如果未来需要"空白也视为空"，应当显式新增 trim 规则而非
      // 让本函数静默改变行为。
      expect(
        shouldAutoLoadMergeInfoOnStartup(
          lastSourceUrl: ' ',
          lastTargetWc: ' ',
        ),
        isTrue,
      );
    });
  });
}
