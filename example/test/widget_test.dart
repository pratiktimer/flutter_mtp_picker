import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_mtp_picker_example/main.dart';

void main() {
  testWidgets('shows MTP picker entry point', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('MTP devices'), findsOneWidget);
    expect(find.text('Pick MTP folder'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_outlined), findsOneWidget);
  });
}
