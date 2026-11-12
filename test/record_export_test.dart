import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/land_map/models/land_api_models.dart';
import 'package:taref_gps/features/land_map/services/land_cloud_service.dart';
import 'package:taref_gps/features/land_map/services/record_export_service.dart';
import 'package:taref_gps/features/land_map/ui/record_export_page.dart';
import 'package:taref_gps/features/subscriptions/entitlement_provider.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Cloud extends LandCloudService {
  @override
  Future<LandDetail> getLand(String bearerToken, String landId) async =>
      LandDetail.fromJson({'id': 7, 'name': '../North Plot', 'type': 'point'});
}

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

class _Export extends RecordExportService {
  int downloads = 0;
  int shares = 0;
  bool edits = false;
  Rect? origin;
  @override
  bool pending(String record) => edits;
  @override
  Future<RecordExportFile> download(
    String token,
    String record,
    RecordExportFormat format, {
    bool Function()? isCurrent,
  }) async {
    downloads++;
    return RecordExportFile(
      bytes: Uint8List.fromList(utf8.encode('Latitude,Longitude\n-6,39')),
      name: 'land_7.csv',
      format: format,
    );
  }

  @override
  Future<ShareResultStatus> share(RecordExportFile file, Rect origin) async {
    shares++;
    this.origin = origin;
    return ShareResultStatus.dismissed;
  }
}

Widget page(RecordExportService service) => ProviderScope(
  overrides: [
    authSessionProvider.overrideWith(_Session.new),
    workspaceProvider.overrideWith(_Workspace.new),
    workspaceAccessSnapshotProvider.overrideWith(
      (ref) async => {
        'features': [
          {'key': 'land.export', 'allowed': false},
        ],
      },
    ),
    recordExportServiceProvider.overrideWithValue(service),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ),
    home: const RecordExportPage(
      company: null,
      record: '7',
      name: 'North Plot',
    ),
  ),
);

void main() {
  test(
    'CSV stays available when format access is unavailable or forbidden',
    () {
      for (final access in <AsyncValue<Map<String, dynamic>>>[
        const AsyncLoading(),
        AsyncError(Exception('offline'), StackTrace.empty),
        const AsyncData({'features': []}),
      ]) {
        expect(recordExportBlock(RecordExportFormat.csv, access), isNull);
        expect(recordExportBlock(RecordExportFormat.kml, access), isNotNull);
      }
      const permitted = AsyncData<Map<String, dynamic>>({
        'features': [
          {'key': 'land.export', 'allowed': true},
        ],
        'transfer_limits': {
          'export_formats': ['kml'],
        },
      });
      expect(recordExportBlock(RecordExportFormat.kml, permitted), isNull);
      expect(
        recordExportBlock(RecordExportFormat.geojson, permitted),
        isNotNull,
      );
    },
  );

  test('geometry validation rejects old polygon-only point exports', () {
    Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));
    validateRecordExport(
      bytes(
        '{"type":"Feature","geometry":{"type":"Point","coordinates":[39,-6]}}',
      ),
      RecordExportFormat.geojson,
      'point',
    );
    validateRecordExport(
      bytes(
        '<kml xmlns="http://www.opengis.net/kml/2.2"><Placemark><Point><coordinates>39,-6</coordinates></Point></Placemark></kml>',
      ),
      RecordExportFormat.kml,
      'point',
    );
    expect(
      () => validateRecordExport(
        bytes('<kml><Polygon/></kml>'),
        RecordExportFormat.kml,
        'point',
      ),
      throwsException,
    );
    expect(
      () => validateRecordExport(
        bytes('{"message":"denied"}'),
        RecordExportFormat.geojson,
        'point',
      ),
      throwsException,
    );
  });

  test('download uses safe names and accepts correct GeoJSON MIME', () async {
    final result = await http.runWithClient(
      () => RecordExportService(
        cloud: _Cloud(),
      ).download('synthetic', '7', RecordExportFormat.geojson),
      () => MockClient((request) async {
        expect(request.url.path, endsWith('/lands/7/export'));
        expect(request.url.queryParameters['type'], 'geojson');
        expect(request.headers['authorization'], 'Bearer synthetic');
        return http.Response(
          '{"type":"Feature","geometry":{"type":"Point","coordinates":[39,-6]}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    expect(result.name, 'land_7__North_Plot.geojson');
  });

  test(
    'download rejects JSON errors, oversized files and changed scope',
    () async {
      final service = RecordExportService(cloud: _Cloud());
      for (final response in [
        http.Response('{"errors":{"record":["Read only."]}}', 403),
        http.Response(
          '{"message":"error"}',
          200,
          headers: {'content-type': 'application/json'},
        ),
        http.Response(
          'x',
          200,
          headers: {'content-length': '${RecordExportService.maxBytes + 1}'},
        ),
      ]) {
        await expectLater(
          http.runWithClient(
            () => service.download('synthetic', '7', RecordExportFormat.csv),
            () => MockClient((_) async => response),
          ),
          throwsException,
        );
      }
      await expectLater(
        http.runWithClient(
          () => service.download(
            'synthetic',
            '7',
            RecordExportFormat.csv,
            isCurrent: () => false,
          ),
          () => MockClient((_) async => throw StateError('Must not dispatch')),
        ),
        throwsException,
      );
    },
  );

  testWidgets('cancelled sharing reuses download on narrow enlarged layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _Export();
    await tester.pumpWidget(page(service));
    await tester.pumpAndSettle();
    final export = find.widgetWithText(FilledButton, 'Export file');
    await tester.scrollUntilVisible(export, 150);
    await tester.tap(export);
    await tester.pumpAndSettle();
    final share = find.widgetWithText(FilledButton, 'Share file');
    await tester.scrollUntilVisible(share, 100);
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(service.downloads, 1);
    expect(service.shares, 2);
    expect(service.origin!.isEmpty, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending local edits prevent download and sharing', (
    tester,
  ) async {
    final service = _Export()..edits = true;
    await tester.pumpWidget(page(service));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Export file');
    await tester.scrollUntilVisible(button, 150);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(service.downloads, 0);
    expect(service.shares, 0);
    expect(
      find.textContaining('Sync or resolve pending local edits'),
      findsOneWidget,
    );
  });
}
