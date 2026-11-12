import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:xml/xml.dart';
import '../../../core/network/api_client.dart';
import 'land_cloud_service.dart';
import 'record_recovery_service.dart';

enum RecordExportFormat {
  csv('CSV', 'csv', 'text/csv'),
  kml('KML', 'kml', 'application/vnd.google-earth.kml+xml'),
  geojson('GeoJSON', 'geojson', 'application/geo+json');

  const RecordExportFormat(this.label, this.extension, this.mime);
  final String label;
  final String extension;
  final String mime;
}

class RecordExportFile {
  const RecordExportFile({
    required this.bytes,
    required this.name,
    required this.format,
  });
  final Uint8List bytes;
  final String name;
  final RecordExportFormat format;
}

String recordExportFilename(
  String record,
  String name,
  RecordExportFormat format,
) {
  final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
  final short = safe.length > 64 ? safe.substring(0, 64) : safe;
  return 'land_${int.parse(record)}_${short.isEmpty ? 'record' : short}.${format.extension}';
}

void validateRecordExport(
  Uint8List bytes,
  RecordExportFormat format,
  String geometry,
) {
  if (bytes.isEmpty) throw Exception('The server returned an empty export.');
  if (format == RecordExportFormat.csv) return;
  final expected = switch (geometry) {
    'point' => 'Point',
    'polyline' => 'LineString',
    'polygon' => 'Polygon',
    _ => null,
  };
  if (expected == null) {
    throw Exception('This record geometry cannot be exported safely.');
  }
  try {
    final content = utf8.decode(bytes);
    if (format == RecordExportFormat.geojson) {
      final data = jsonDecode(content);
      if (data is! Map ||
          data['type'] != 'Feature' ||
          data['geometry'] is! Map ||
          data['geometry']['type'] != expected ||
          data['geometry']['coordinates'] is! List) {
        throw const FormatException();
      }
    } else {
      final document = XmlDocument.parse(content);
      if (document.doctypeElement != null ||
          document.rootElement.name.local != 'kml' ||
          document.findAllElements(expected).length != 1) {
        throw const FormatException();
      }
    }
  } catch (_) {
    throw Exception(
      'The server returned invalid or mismatched geometry. Update the backend before exporting this format.',
    );
  }
}

class RecordExportService {
  RecordExportService({LandCloudService? cloud})
    : cloud = cloud ?? LandCloudService();
  final LandCloudService cloud;
  static const maxBytes = 16 * 1024 * 1024;

  bool pending(String record) => RecordRecoveryService().pending(record);

  Future<RecordExportFile> download(
    String token,
    String record,
    RecordExportFormat format, {
    bool Function()? isCurrent,
  }) async {
    final id = int.tryParse(record);
    if (id == null || id <= 0) {
      throw Exception('A saved cloud record is required for file export.');
    }
    final detail = await cloud.getLand(token, record);
    if (isCurrent?.call() == false) {
      throw Exception('Workspace or account changed. Reopen export.');
    }
    final client = http.Client();
    try {
      final request =
          http.Request(
              'GET',
              ApiClient.uri(
                '/lands/$id/export',
                queryParameters: {'type': format.extension},
              ),
            )
            ..followRedirects = false
            ..headers.addAll({
              ...ApiClient.jsonHeaders(bearerToken: token),
              'Accept': format.mime,
            });
      final response = await client.send(request).timeout(ApiClient.timeout);
      if ((response.contentLength ?? 0) > maxBytes) {
        throw Exception(
          'This export exceeds the mobile download limit. Use the web app.',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(ApiClient.timeout)) {
        if (isCurrent?.call() == false) {
          throw Exception('Workspace or account changed. Reopen export.');
        }
        if (builder.length + chunk.length > maxBytes) {
          throw Exception(
            'This export exceeds the mobile download limit. Use the web app.',
          );
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (response.statusCode != 200) {
        String message =
            'Unable to export this record. Check access and retry.';
        try {
          final body = jsonDecode(utf8.decode(bytes));
          if (body is Map) {
            final errors = body['errors'];
            final messages = errors is Map
                ? errors.values
                      .whereType<List>()
                      .expand((values) => values)
                      .whereType<String>()
                : const <String>[];
            message =
                messages.firstOrNull ?? body['message']?.toString() ?? message;
          }
        } catch (_) {}
        throw Exception(message);
      }
      final mime = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (mime != format.mime &&
          !(format == RecordExportFormat.geojson && mime == 'application/json')) {
        throw Exception('The server did not return the requested file format.');
      }
      validateRecordExport(bytes, format, detail.type);
      return RecordExportFile(
        bytes: bytes,
        name: recordExportFilename(record, detail.name, format),
        format: format,
      );
    } finally {
      client.close();
    }
  }

  Future<ShareResultStatus> share(RecordExportFile file, Rect origin) async =>
      (await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              file.bytes,
              mimeType: file.format.mime,
              name: file.name,
            ),
          ],
          fileNameOverrides: [file.name],
          sharePositionOrigin: origin,
        ),
      )).status;
}

final recordExportServiceProvider = Provider<RecordExportService>(
  (ref) => RecordExportService(),
);
