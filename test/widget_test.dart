import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_learning/main.dart';

void main() {
  testWidgets('home page shows personal lab portal', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('我的实验应用'), findsOneWidget);
    expect(find.text('所有功能入口都平铺在这里'), findsOneWidget);
    expect(find.text('待办清单'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('实验开关'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('实验开关'), findsOneWidget);
  });
}
