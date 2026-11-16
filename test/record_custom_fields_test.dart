import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';
import 'package:taref_gps/features/land_map/ui/record_custom_fields_page.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'synthetic',
  );
}

class _Workspace extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState.personal();
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('custom-fields-test');
    Hive.init(directory.path);
    await Hive.openBox('landbox');
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final allowed in [true, false]) {
    testWidgets(
      allowed
          ? 'sends values with unchanged definitions and revision'
          : 'read-only records cannot save',
      (tester) async {
        Map? saved;
        final client = MockClient((request) async {
          if (request.method == 'PUT') saved = jsonDecode(request.body) as Map;
          return http.Response(
            jsonEncode({
              'data': {
                'fields': [
                  {
                    'name': 'Inspection reference',
                    'type': 'text',
                    'value': saved == null ? 'Original' : 'Updated',
                  },
                ],
                'revision': 'a' * 64,
                'can_edit_record': allowed,
                'policy': {'editable': allowed},
              },
            }),
            200,
          );
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authSessionProvider.overrideWith(_Session.new),
              workspaceProvider.overrideWith(_Workspace.new),
            ],
            child: MaterialApp(
              home: RecordCustomFieldsPage(
                record: '1',
                company: null,
                client: client,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Inspection reference'), findsOneWidget);
        if (allowed) {
          await tester.enterText(find.byType(TextFormField), 'Updated');
          await tester.pump();
          await tester.tap(find.text('Save changes'));
          await tester.pumpAndSettle();
          expect(saved?['revision'], 'a' * 64);
          expect(saved?['fields'], [
            {
              'name': 'Inspection reference',
              'type': 'text',
              'value': 'Updated',
            },
          ]);
          expect(find.text('Custom fields saved.'), findsOneWidget);
          await tester.enterText(find.byType(TextFormField), 'Unsaved draft');
          await tester.pump();
          await tester.tap(find.byTooltip('Refresh'));
          await tester.pumpAndSettle();
          expect(find.text('Discard unsaved changes?'), findsOneWidget);
          await tester.tap(find.text('Keep editing'));
          await tester.pumpAndSettle();
          expect(find.text('Unsaved draft'), findsOneWidget);
          await tester.tap(find.byTooltip('Refresh'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Discard'));
          await tester.pumpAndSettle();
          expect(find.text('Unsaved draft'), findsNothing);
        } else {
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull,
          );
          expect(saved, isNull);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
