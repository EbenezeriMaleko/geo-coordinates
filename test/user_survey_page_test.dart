import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/land_map/ui/user_survey_page.dart';

void main() {
  testWidgets('survey stays usable on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF001F3F)),
        ),
        home: const UserSurveyPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Share your experience'), findsOneWidget);
    expect(find.text('Save response'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
