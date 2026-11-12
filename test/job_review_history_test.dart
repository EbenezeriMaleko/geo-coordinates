import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/workspaces/job_review_history.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Company extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState(
    companies: [CompanyWorkspace(id: 1, name: 'Survey', role: 'viewer')],
    activeCompanyId: 1,
  );
}

Widget history({bool fail = false, bool empty = false}) => ProviderScope(
  overrides: [
    workspaceProvider.overrideWith(_Company.new),
    reviewHistoryProvider.overrideWith((ref, query) async {
      if (fail) throw Exception('Unavailable');
      return {
        'data': empty
            ? []
            : [
                {
                  'actor': 'Survey reviewer',
                  'action': query.page == 1 ? 'changes_requested' : 'submit',
                  'created_at': '2026-10-30T08:30:00Z',
                  'note': query.page == 1
                      ? 'Check the northern boundary before resubmitting.'
                      : null,
                },
              ],
        'last_page': empty ? 1 : 2,
      };
    }),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ),
    home: const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: JobReviewHistory(company: 1, job: 2),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'history expands and paginates with retained notes on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(history());
      await tester.pumpAndSettle();
      expect(find.text('Changes requested'), findsNothing);
      await tester.tap(find.text('Review history'));
      await tester.pumpAndSettle();
      expect(find.text('Changes requested'), findsOneWidget);
      expect(
        find.text('Check the northern boundary before resubmitting.'),
        findsOneWidget,
      );
      expect(find.text('Survey reviewer'), findsOneWidget);
      await tester.tap(find.byTooltip('Next history page'));
      await tester.pumpAndSettle();
      expect(find.text('Submitted for review'), findsOneWidget);
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history failure offers retry without fabricating empty history',
    (tester) async {
      await tester.pumpWidget(history(fail: true));
      await tester.tap(find.text('Review history'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to load history. Retry'), findsOneWidget);
      expect(find.text('No review history yet.'), findsNothing);
    },
  );

  testWidgets('empty history has an explicit state', (tester) async {
    await tester.pumpWidget(history(empty: true));
    await tester.tap(find.text('Review history'));
    await tester.pumpAndSettle();
    expect(find.text('No review history yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
