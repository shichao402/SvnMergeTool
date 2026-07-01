import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:svn_auto_merge/providers/app_state.dart';
import 'package:svn_auto_merge/providers/merge_execution_state.dart';
import 'package:svn_auto_merge/screens/main_screen_v3.dart';
import 'package:svn_auto_merge/services/app_paths_service.dart';
import 'package:svn_auto_merge/services/log_cache_service.dart';

class _SvnFixture {
  final Directory root;
  final Directory seedWorkingCopy;
  final String sourceUrl;

  const _SvnFixture({
    required this.root,
    required this.seedWorkingCopy,
    required this.sourceUrl,
  });

  Future<void> commit(String message) async {
    final notes = File(p.join(seedWorkingCopy.path, 'trunk', 'notes.txt'));
    await notes.writeAsString('$message\n', mode: FileMode.append);
    await _runSvn(['commit', '-m', message],
        workingDirectory: seedWorkingCopy.path);
  }

  Future<void> dispose() async {
    await root.delete(recursive: true);
  }
}

Future<void> _runSvn(List<String> args, {String? workingDirectory}) async {
  final result = await Process.run(
    'svn',
    ['--non-interactive', ...args],
    workingDirectory: workingDirectory,
  );

  if (result.exitCode != 0) {
    fail(
        'svn ${args.join(' ')} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}');
  }
}

Future<void> _runSvnAdmin(List<String> args) async {
  final result = await Process.run('svnadmin', args);

  if (result.exitCode != 0) {
    fail(
        'svnadmin ${args.join(' ')} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}');
  }
}

Future<_SvnFixture> _createSvnFixture() async {
  final root = await Directory.systemTemp.createTemp('svn_auto_merge_e2e_');
  final repo = Directory(p.join(root.path, 'repo'));
  final seedWorkingCopy = Directory(p.join(root.path, 'seed_wc'));

  await _runSvnAdmin(['create', repo.path]);
  final repoUrl = repo.uri.toString();

  await _runSvn(['checkout', repoUrl, seedWorkingCopy.path]);
  await Directory(p.join(seedWorkingCopy.path, 'trunk')).create();
  await File(p.join(seedWorkingCopy.path, 'trunk', 'notes.txt'))
      .writeAsString('create trunk\n');
  await _runSvn(['add', 'trunk'], workingDirectory: seedWorkingCopy.path);
  await _runSvn(
    ['commit', '-m', 'create trunk'],
    workingDirectory: seedWorkingCopy.path,
  );

  final fixture = _SvnFixture(
    root: root,
    seedWorkingCopy: seedWorkingCopy,
    sourceUrl: '${repoUrl}trunk',
  );

  await fixture.commit('old svn commit r2');
  return fixture;
}

Future<void> _pumpApp(WidgetTester tester) async {
  final appState = AppState();
  final mergeState = MergeExecutionState();
  await tester.runAsync(() async {
    await appState.init();
    await mergeState.init();
    await LogCacheService().init();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: appState),
        ChangeNotifierProvider<MergeExecutionState>.value(value: mergeState),
      ],
      child: MaterialApp(
        title: 'SVN 合并助手',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const MainScreenV3(),
      ),
    ),
  );
  await _pumpUntilFound(tester, find.byType(MainScreenV3));
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 100),
  int maxPumps = 100,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  final visibleTexts = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .where((text) => text.isNotEmpty)
      .join(' | ');
  fail('等待 UI 元素超时：$finder。当前页面文本：$visibleTexts');
}

Future<void> _pumpUntilText(
  WidgetTester tester,
  String text, {
  Duration step = const Duration(milliseconds: 100),
  int maxPumps = 200,
}) async {
  await _pumpUntilFound(tester, find.text(text),
      step: step, maxPumps: maxPumps);
}

Future<void> _configureSourceFromUi(
  WidgetTester tester,
  _SvnFixture fixture,
) async {
  await tester.tap(find.text('未设置').first);
  await _pumpUntilFound(tester, find.text('源 URL'));

  await tester.enterText(
    find.widgetWithText(TextField, '源 URL'),
    fixture.sourceUrl,
  );
  await tester.tap(find.text('确定'));
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(seconds: 1)),
  );
  await tester.pump();
}

Future<void> _syncLatestFromUi(WidgetTester tester) async {
  await tester.runAsync(
    () async {
      await tester.tap(find.text('同步最新'));
      await Future<void>.delayed(const Duration(seconds: 5));
    },
  );
  await tester.pump();
}

Future<void> _applyFilterFromUi(WidgetTester tester) async {
  await tester.tap(find.text('过滤'));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(seconds: 1)),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('端到端 UI：重启后通过同步最新补出 SVN 新 revision', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'preload_enabled': false,
    });
    await tester.binding.setSurfaceSize(const Size(1400, 900));

    final appDataDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('svn_auto_merge_app_data_'),
    );
    final fixture = await tester.runAsync(_createSvnFixture);
    if (appDataDir == null || fixture == null) {
      fail('创建端到端测试临时目录或 SVN fixture 失败');
    }
    final appData = appDataDir;
    final svnFixture = fixture;
    AppPathsService().setAppSupportDirForTesting(appData.path);

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await LogCacheService().close();
      AppPathsService().setAppSupportDirForTesting(null);
      await svnFixture.dispose();
      await appData.delete(recursive: true);
    });

    await _pumpApp(tester);
    await _configureSourceFromUi(tester, svnFixture);
    await _syncLatestFromUi(tester);
    await _pumpUntilText(tester, 'r2');
    expect(find.text('old svn commit r2'), findsOneWidget);
    expect(find.text('r3'), findsNothing);

    await tester.runAsync(() => svnFixture.commit('new svn commit r3'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await LogCacheService().close();

    await _pumpApp(tester);
    await _applyFilterFromUi(tester);
    await _pumpUntilText(tester, 'r2');
    expect(find.text('new svn commit r3'), findsNothing);

    await _syncLatestFromUi(tester);
    await _pumpUntilText(tester, 'r3');
    expect(find.text('new svn commit r3'), findsOneWidget);
    expect(find.text('old svn commit r2'), findsOneWidget);
    expect(find.text('r2'), findsOneWidget);
  });
}
