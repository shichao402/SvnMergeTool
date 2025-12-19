// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:SvnMergeTool/providers/app_state.dart';
import 'package:SvnMergeTool/providers/pipeline_merge_state.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
          ChangeNotifierProvider(create: (_) => PipelineMergeState()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('SVN Auto Merge')),
          ),
        ),
      ),
    );

    // Verify that the app launches
    expect(find.text('SVN Auto Merge'), findsOneWidget);
  });
}
