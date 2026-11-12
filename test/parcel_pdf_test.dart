import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:taref_gps/core/network/api_client.dart';
import 'package:taref_gps/features/auth/models/auth_models.dart';
import 'package:taref_gps/features/auth/providers/auth_provider.dart';
import 'package:taref_gps/features/land_map/services/parcel_pdf_service.dart';
import 'package:taref_gps/features/land_map/ui/parcel_pdf_page.dart';
import 'package:taref_gps/features/workspaces/workspace_provider.dart';

class _Session extends AuthSessionNotifier {
  @override
  AuthSession build() => AuthSession(
    user: AuthUser.fromJson({'id': 1, 'is_verified': true}),
    token: 'synthetic',
  );
  void replace() => state = AuthSession(
    user: AuthUser.fromJson({'id': 2, 'is_verified': true}),
    token: 'other',
  );
}

class _Workspace extends WorkspaceNotifier {
  @override
  WorkspaceState build() => const WorkspaceState.personal();
  void replace() => state = const WorkspaceState(
    companies: [CompanyWorkspace(id: 42, name: 'Other company', role: 'owner')],
    activeCompanyId: 42,
  );
}

class _Pdf extends ParcelPdfService {
  bool exists = true;
  bool edits = false;
  bool stale = false;
  int downloads = 0;
  int shares = 0;
  int generations = 0;
  Rect? origin;
  Completer<ParcelPdfFile>? delay;
  @override
  bool pending(String record) => edits;
  @override
  Future<ParcelReportPolicy> policy(
    String token,
    String record,
    int? company, {
    bool Function()? isCurrent,
  }) async => const ParcelReportPolicy(
    available: true,
    allowed: true,
    customLogo: true,
    used: 0,
    limit: 10,
  );
  @override
  Future<void> generate(
    String token,
    String record,
    int? company, {
    ParcelReportLogo? logo,
    bool Function()? isCurrent,
  }) async {
    generations++;
    exists = true;
    stale = false;
  }

  @override
  Future<SavedParcelPdf> details(
    String token,
    String record,
    int? company, {
    bool Function()? isCurrent,
  }) async => SavedParcelPdf(
    available: exists,
    stale: stale,
    revision: 'a' * 64,
    generatedAt: DateTime.utc(2026, 11, 2),
  );
  @override
  Future<ParcelPdfFile> download(
    String token,
    String record,
    int? company,
    String revision, {
    bool Function()? isCurrent,
  }) async {
    downloads++;
    return delay == null ? file() : delay!.future;
  }

  ParcelPdfFile file() => ParcelPdfFile(
    Uint8List.fromList(ascii.encode('%PDF-1.4 test')),
    'parcel_7.pdf',
    stale: stale,
  );
  @override
  Future<ShareResultStatus> share(ParcelPdfFile file, Rect origin) async {
    shares++;
    this.origin = origin;
    return ShareResultStatus.dismissed;
  }
}

class _NetworkPdf extends ParcelPdfService {
  _NetworkPdf({this.edits = false});
  final bool edits;
  @override
  bool pending(String record) => edits;
}

Widget page(ParcelPdfService service) => ProviderScope(
  overrides: [
    authSessionProvider.overrideWith(_Session.new),
    workspaceProvider.overrideWith(_Workspace.new),
    parcelPdfServiceProvider.overrideWithValue(service),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: child!,
    ),
    home: const ParcelPdfPage(
      company: null,
      record: '7',
      name: 'Northern parcel',
    ),
  ),
);

void main() {
  test('report policy and logo inputs are validated', () {
    final policy = ParcelReportPolicy.fromJson({
      'available': true,
      'allowed': true,
      'custom_logo': false,
      'allowance': {'used': 2, 'limit': 10},
    });
    expect(policy.used, 2);
    expect(policy.limit, 10);
    expect(
      () => ParcelReportPolicy.fromJson({'available': true}),
      throwsException,
    );
    expect(
      ParcelReportLogo.fromBytes(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ).mimeType,
      'image/png',
    );
    expect(
      () => ParcelReportLogo.fromBytes(Uint8List.fromList([1, 2, 3])),
      throwsException,
    );
  });

  test(
    'generation uses POST with pinned company and validates the returned PDF',
    () async {
      ApiClient.setActiveCompanyId(99);
      addTearDown(() => ApiClient.setActiveCompanyId(null));
      final service = _NetworkPdf();
      await http.runWithClient(
        () => service.generate('synthetic', '7', 42),
        () => MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, endsWith('/lands/7/report'));
          expect(request.headers['X-Company-Id'], '42');
          expect(request.headers['authorization'], 'Bearer synthetic');
          return http.Response(
            '%PDF-1.4 generated',
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }),
      );
    },
  );

  test('generation refuses pending edits before sending a request', () async {
    await expectLater(
      http.runWithClient(
        () => _NetworkPdf(edits: true).generate('synthetic', '7', 42),
        () => MockClient((_) async => throw StateError('Must not dispatch')),
      ),
      throwsException,
    );
  });

  test('generation rejects an invalid PDF response', () async {
    await expectLater(
      http.runWithClient(
        () => _NetworkPdf().generate('synthetic', '7', null),
        () => MockClient(
          (_) async => http.Response(
            '<html>error</html>',
            200,
            headers: {'content-type': 'application/pdf'},
          ),
        ),
      ),
      throwsException,
    );
  });

  testWidgets('can generate a missing report after confirmation', (
    tester,
  ) async {
    final service = _Pdf()..exists = false;
    await tester.pumpWidget(page(service));
    await tester.pumpAndSettle();
    final generate = find.widgetWithText(OutlinedButton, 'Generate PDF');
    await tester.scrollUntilVisible(generate, 120);
    await tester.tap(generate);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pumpAndSettle();
    expect(service.generations, 1);
    expect(find.text('Report generated.'), findsOneWidget);
    expect(find.text('Saved parcel report'), findsOneWidget);
  });

  test('metadata validates availability, revision and date', () {
    expect(SavedParcelPdf.fromJson({'available': false}).available, isFalse);
    expect(() => SavedParcelPdf.fromJson({}), throwsException);
    expect(
      () => SavedParcelPdf.fromJson({'available': true, 'revision': 'bad'}),
      throwsException,
    );
  });

  test(
    'only GET requests download existing PDF with explicit workspace and revision',
    () async {
      ApiClient.setActiveCompanyId(999);
      addTearDown(() => ApiClient.setActiveCompanyId(null));
      final service = ParcelPdfService();
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          final metadata = await service.details('synthetic', '7', null);
          expect(metadata.stale, isTrue);
          final file = await service.download(
            'synthetic',
            '7',
            42,
            metadata.revision!,
          );
          expect(file.name, 'parcel_7.pdf');
          expect(file.stale, isTrue);
          expect(ascii.decode(file.bytes), '%PDF-1.4 saved');
        },
        () => MockClient((request) async {
          requests.add(request);
          expect(request.method, 'GET');
          expect(request.headers['authorization'], 'Bearer synthetic');
          if (request.url.path.endsWith('/saved')) {
            expect(request.headers['X-Company-Id'], isNull);
            return http.Response(
              jsonEncode({
                'data': {
                  'available': true,
                  'revision': 'a' * 64,
                  'generated_at': '2026-11-02T00:00:00Z',
                  'stale': true,
                },
              }),
              200,
            );
          }
          expect(request.headers['X-Company-Id'], '42');
          expect(request.url.path, endsWith('/report/download'));
          expect(request.url.queryParameters['revision'], 'a' * 64);
          return http.Response(
            '%PDF-1.4 saved',
            200,
            headers: {
              'content-type': 'application/pdf',
              'x-report-stale': 'true',
            },
          );
        }),
      );
      expect(requests, hasLength(2));
    },
  );

  test(
    'rejects error responses, non-PDF content and oversized downloads',
    () async {
      for (final response in [
        http.Response('{"message":"denied"}', 403),
        http.Response('new version', 409),
        http.Response('missing', 404),
        http.Response(
          '<html>error</html>',
          200,
          headers: {
            'content-type': 'application/pdf',
            'x-report-stale': 'false',
          },
        ),
        http.Response(
          '%PDF-1.4 fake',
          200,
          headers: {'content-type': 'text/html', 'x-report-stale': 'false'},
        ),
        http.Response(
          'x',
          200,
          headers: {'content-length': '${ParcelPdfService.maxBytes + 1}'},
        ),
      ]) {
        await expectLater(
          http.runWithClient(
            () => ParcelPdfService().download('synthetic', '7', null, 'a' * 64),
            () => MockClient((_) async => response),
          ),
          throwsException,
        );
      }
    },
  );

  test('changed scope prevents request dispatch', () async {
    await expectLater(
      http.runWithClient(
        () => ParcelPdfService().download(
          'synthetic',
          '7',
          null,
          'a' * 64,
          isCurrent: () => false,
        ),
        () => MockClient((_) async => throw StateError('Must not dispatch')),
      ),
      throwsException,
    );
  });

  testWidgets('missing report does not offer download before generation', (
    tester,
  ) async {
    final service = _Pdf()..exists = false;
    await tester.pumpWidget(page(service));
    await tester.pumpAndSettle();
    expect(find.text('No saved PDF'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Download & share PDF'),
      findsNothing,
    );
    expect(service.downloads, 0);
  });

  testWidgets(
    'stale report warning and canceled share fit enlarged narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _Pdf()..stale = true;
      await tester.pumpWidget(page(service));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This PDF contains older record details'),
        findsOneWidget,
      );
      final download = find.widgetWithText(
        FilledButton,
        'Download & share PDF',
      );
      await tester.scrollUntilVisible(download, 120);
      await Scrollable.ensureVisible(tester.element(download), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(download);
      await tester.pumpAndSettle();
      final share = find.widgetWithText(FilledButton, 'Share PDF');
      await tester.scrollUntilVisible(share, 100);
      await Scrollable.ensureVisible(tester.element(share), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(share);
      await tester.pumpAndSettle();
      expect(service.downloads, 1);
      expect(service.shares, 2);
      expect(service.origin!.isEmpty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending edits block saved PDF download', (tester) async {
    final service = _Pdf()..edits = true;
    await tester.pumpWidget(page(service));
    await tester.pumpAndSettle();
    final download = find.widgetWithText(FilledButton, 'Download & share PDF');
    await tester.scrollUntilVisible(download, 100);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(service.downloads, 0);
    expect(
      find.textContaining('Sync or resolve pending local edits'),
      findsOneWidget,
    );
  });

  testWidgets(
    'report becoming stale during download requires another share action',
    (tester) async {
      final service = _Pdf();
      await tester.pumpWidget(page(service));
      await tester.pumpAndSettle();
      service.stale = true;
      final download = find.widgetWithText(
        FilledButton,
        'Download & share PDF',
      );
      await tester.scrollUntilVisible(download, 100);
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(service.shares, 0);
      final share = find.widgetWithText(FilledButton, 'Share PDF');
      await tester.scrollUntilVisible(share, 100);
      await Scrollable.ensureVisible(tester.element(share), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(share);
      await tester.pumpAndSettle();
      expect(service.shares, 1);
      expect(service.downloads, 1);
    },
  );

  testWidgets('late download cannot share after workspace replacement', (
    tester,
  ) async {
    final service = _Pdf()..delay = Completer<ParcelPdfFile>();
    await tester.pumpWidget(page(service));
    await tester.pumpAndSettle();
    final download = find.widgetWithText(FilledButton, 'Download & share PDF');
    await tester.scrollUntilVisible(download, 100);
    await tester.tap(download);
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ParcelPdfPage)),
    );
    (container.read(workspaceProvider.notifier) as _Workspace).replace();
    await tester.pump();
    service.delay!.complete(service.file());
    await tester.pumpAndSettle();
    expect(service.shares, 0);
    expect(find.textContaining('Workspace or account changed'), findsOneWidget);
  });

  testWidgets('late download cannot share after account replacement', (
    tester,
  ) async {
    final service = _Pdf()..delay = Completer<ParcelPdfFile>();
    await tester.pumpWidget(page(service));
    await tester.pumpAndSettle();
    final download = find.widgetWithText(FilledButton, 'Download & share PDF');
    await tester.scrollUntilVisible(download, 100);
    await tester.tap(download);
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ParcelPdfPage)),
    );
    (container.read(authSessionProvider.notifier) as _Session).replace();
    await tester.pump();
    service.delay!.complete(service.file());
    await tester.pumpAndSettle();
    expect(service.shares, 0);
    expect(find.textContaining('Workspace or account changed'), findsOneWidget);
  });
}
