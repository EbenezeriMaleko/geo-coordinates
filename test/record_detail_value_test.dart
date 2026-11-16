import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/widget/record_detail_value.dart';

void main() {
  for (final width in [240.0, 380.0]) {
    testWidgets('record details fit width $width with enlarged text', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Center(
                child: SizedBox(
                  width: width,
                  child: const RecordDetailValue(
                    label: 'Owner / claimant',
                    value:
                        'A customer with a long name and detailed parcel information',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Owner / claimant'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
