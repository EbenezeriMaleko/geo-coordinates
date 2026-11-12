import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taref_gps/features/workspaces/field_job_link_picker.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Company extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState(
    companies: [CompanyWorkspace(id: 1, name: 'Survey', role: 'admin')],
    activeCompanyId: 1,
  );
}

void main() {
  testWidgets('project choices support search, pagination and selection', (
    tester,
  ) async {
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith(_Company.new),
          jobLinkOptionsProvider.overrideWith(
            (ref, query) async => {
              'data': [
                {
                  'id': query.page,
                  'name': '${query.search} Project ${query.page}',
                },
              ],
              'last_page': 2,
            },
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await Navigator.of(context)
                      .push<Map<String, dynamic>>(
                        MaterialPageRoute(
                          builder: (_) => const FieldJobLinkPicker(
                            company: 1,
                            project: true,
                          ),
                        ),
                      );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Northern');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tester.tap(find.text('Northern Project 1'));
    await tester.pumpAndSettle();
    expect(selected?['id'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'record selector fits narrow enlarged text and shows empty results',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workspaceProvider.overrideWith(_Company.new),
            jobLinkOptionsProvider.overrideWith(
              (ref, query) async => {'data': [], 'last_page': 1},
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const FieldJobLinkPicker(company: 1, project: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching items.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
