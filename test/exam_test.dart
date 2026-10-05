import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app/exam_page.dart';
import 'package:my_app/grade_service.dart';
import 'package:my_app/main.dart';

class FakeGrades extends GradeService {
  int requests = 0;
  bool expired = false;
  @override
  bool get hasSession => true;
  @override
  Future<Map<String, dynamic>> fetchGrades() async {
    requests++;
    if (expired) throw LoginRequired();
    return {
      'data': [
        {'kc_mc': '刷新后的课程', 'zcjstr': '良'},
      ],
    };
  }
}

void main() {
  testWidgets(
    'large grade history builds only nearby rows and scrolls to end',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        gradeCacheKey: jsonEncode({
          'data': List.generate(
            1000,
            (i) => {
              'kc_mc': '课程$i',
              'zcjstr': '良',
              'xnxqid': i < 500 ? '2025-2026-2' : '2024-2025-1',
            },
          ),
        }),
      });
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ExamPage())),
      );
      await tester.pumpAndSettle();
      expect(find.text('2025-2026-2 · 500 门'), findsOneWidget);
      expect(find.text('课程999'), findsNothing);
      expect(find.text('良').evaluate().length, lessThan(25));
      final list = tester.widget<ListView>(find.byType(ListView));
      list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('课程999'), findsOneWidget);
      expect(find.text('良').evaluate().length, lessThan(25));
      await tester.tap(find.byTooltip('放大'));
      await tester.pumpAndSettle();
      expect(find.text('课程999'), findsOneWidget);
      final horizontal = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .firstWhere((view) => view.scrollDirection == Axis.horizontal);
      horizontal.controller!.jumpTo(
        horizontal.controller!.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  test('login encoding matches Python interleaving and exhausted key', () {
    expect(
      GradeService.encodeLogin('a', 'b', 'abcdefgh', '120'),
      'aa%bc%%b%%% ',
    );
    expect(GradeService.encodeLogin('a', 'b', '', '999'), 'a%%%b%%% ');
  });
  testWidgets('cached grades scroll, expand and refresh explicitly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      gradeCacheKey: jsonEncode({
        'data': List.generate(
          17,
          (i) => {
            'kc_mc': '习近平新时代中国特色社会主义思想概论$i',
            'zcjstr': '良',
            'zcj': 85,
            'xf': 2,
            'jd': 3.5,
          },
        ),
      }),
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeGrades();
    final key = GlobalKey<ExamPageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExamPage(key: key, service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.requests, 0);
    expect(find.text('考试时间'), findsOneWidget);
    expect(find.text('良'), findsWidgets);
    expect(find.text('良').evaluate().length, lessThan(17));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('放大'));
    await tester.pumpAndSettle();
    expect(find.text('考试时间'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('缩小'));
    await tester.pumpAndSettle();
    expect(find.text('考试时间'), findsOneWidget);
    await key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(service.requests, 1);
    expect(find.text('刷新后的课程'), findsOneWidget);
    service.expired = true;
    final refresh = key.currentState!.refresh();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('登录教务系统'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await refresh;
    expect(find.text('刷新后的课程'), findsOneWidget);
  });
  testWidgets('first visit asks for login and tabs preserve page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('考试信息'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('登录教务系统'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('切换课表'), findsNothing);
    await tester.tap(find.text('课程表'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('切换课表'), findsOneWidget);
    await tester.tap(find.text('考试信息'));
    await tester.pumpAndSettle();
    expect(find.text('登录教务系统'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
