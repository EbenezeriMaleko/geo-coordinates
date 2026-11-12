import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/network/api_client.dart';
import 'record_recovery_service.dart';

class SavedParcelPdf {
  const SavedParcelPdf({
    required this.available,
    this.revision,
    this.generatedAt,
    this.stale = false,
  });
  final bool available;
  final String? revision;
  final DateTime? generatedAt;
  final bool stale;

  factory SavedParcelPdf.fromJson(Map<String, dynamic> json) {
    if (json['available'] is! bool) {
      throw Exception('The server did not return saved report availability.');
    }
    final available = json['available'] == true;
    final revision = json['revision']?.toString();
    final generated = DateTime.tryParse(json['generated_at']?.toString() ?? '');
    if (available &&
        (revision == null ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(revision) ||
            generated == null ||
            json['stale'] is! bool)) {
      throw Exception('The server returned incomplete report details.');
    }
    return SavedParcelPdf(
      available: available,
      revision: revision,
      generatedAt: generated,
      stale: json['stale'] == true,
    );
  }
}

class ParcelPdfFile {
  const ParcelPdfFile(this.bytes, this.name, {required this.stale});
  final Uint8List bytes;
  final String name;
  final bool stale;
}

class ParcelReportPolicy {
  const ParcelReportPolicy({
    required this.available,
    required this.allowed,
    required this.customLogo,
    required this.used,
    required this.limit,
  });
  final bool available;
  final bool allowed;
  final bool customLogo;
  final int used;
  final int? limit;

  factory ParcelReportPolicy.fromJson(Map<String, dynamic> json) {
    final allowance = json['allowance'];
    if (json['available'] is! bool ||
        json['allowed'] is! bool ||
        json['custom_logo'] is! bool ||
        allowance is! Map ||
        allowance['used'] is! num ||
        (allowance['limit'] != null && allowance['limit'] is! num)) {
      throw Exception('The server returned incomplete report settings.');
    }
    return ParcelReportPolicy(
      available: json['available'] as bool,
      allowed: json['allowed'] as bool,
      customLogo: json['custom_logo'] as bool,
      used: (allowance['used'] as num).toInt(),
      limit: (allowance['limit'] as num?)?.toInt(),
    );
  }
}

class ParcelReportLogo {
  ParcelReportLogo._(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;

  factory ParcelReportLogo.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw Exception('Choose a PNG or JPEG logo no larger than 1 MB.');
    }
    final png =
        bytes.length >= 8 &&
        const [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ].asMap().entries.every((entry) => bytes[entry.key] == entry.value);
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    if (!png && !jpeg) throw Exception('Choose a PNG or JPEG logo.');
    return ParcelReportLogo._(bytes, png ? 'image/png' : 'image/jpeg');
  }
}

class ParcelPdfService {
  static const maxBytes = 12 * 1024 * 1024;
  bool pending(String record) => RecordRecoveryService().pending(record);

  Future<http.Response> _get(
    String token,
    String record,
    int? company,
    String action, {
    String? revision,
    bool Function()? isCurrent,
  }) async {
    final id = int.tryParse(record);
    if (id == null || id < 1) {
      throw Exception('A saved cloud record is required.');
    }
    if (isCurrent?.call() == false) {
      throw Exception('Workspace or account changed. Reopen the report.');
    }
    final client = http.Client();
    try {
      final headers = ApiClient.jsonHeaders(bearerToken: token)
        ..remove('X-Company-Id');
      if (company != null) headers['X-Company-Id'] = '$company';
      headers['Accept'] = action == 'download'
          ? 'application/pdf'
          : 'application/json';
      final request =
          http.Request(
              'GET',
              ApiClient.uri(
                action.isEmpty
                    ? '/lands/$id/report'
                    : '/lands/$id/report/$action',
                queryParameters: {'revision': ?revision},
              ),
            )
            ..followRedirects = false
            ..headers.addAll(headers);
      final response = await client.send(request).timeout(ApiClient.timeout);
      final limit = action == 'download' ? maxBytes : 64 * 1024;
      if ((response.contentLength ?? 0) > limit) {
        throw Exception(
          'The report exceeds the mobile download limit. Use the web app.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(ApiClient.timeout)) {
        if (isCurrent?.call() == false) {
          throw Exception('Workspace or account changed. Reopen the report.');
        }
        if (bytes.length + chunk.length > limit) {
          throw Exception(
            'The report exceeds the mobile download limit. Use the web app.',
          );
        }
        bytes.add(chunk);
      }
      if (isCurrent?.call() == false) {
        throw Exception('Workspace or account changed. Reopen the report.');
      }
      final result = http.Response.bytes(
        bytes.takeBytes(),
        response.statusCode,
        headers: response.headers,
      );
      if (result.statusCode != 200) {
        String message = switch (result.statusCode) {
          404 =>
            'No saved report is available, or this server needs the report-download update.',
          409 => 'The saved PDF changed. Refresh before downloading.',
          401 || 403 =>
            'This report is not available with your current account or workspace access.',
          _ => 'The saved report could not be loaded. Try again.',
        };
        if (result.statusCode == 422) {
          try {
            final body = jsonDecode(result.body);
            if (body is Map && body['message'] is String) {
              message = body['message'];
            }
          } catch (_) {}
        }
        throw Exception(message);
      }
      return result;
    } finally {
      client.close();
    }
  }

  Future<ParcelReportPolicy> policy(
    String token,
    String record,
    int? company, {
    bool Function()? isCurrent,
  }) async {
    final response = await _get(
      token,
      record,
      company,
      '',
      isCurrent: isCurrent,
    );
    final body = jsonDecode(response.body);
    if (body is! Map || body['data'] is! Map) {
      throw Exception('The server did not return report settings.');
    }
    return ParcelReportPolicy.fromJson(
      Map<String, dynamic>.from(body['data'] as Map),
    );
  }

  Future<void> generate(
    String token,
    String record,
    int? company, {
    ParcelReportLogo? logo,
    bool Function()? isCurrent,
  }) async {
    final id = int.tryParse(record);
    if (id == null || id < 1) {
      throw Exception('A saved cloud record is required.');
    }
    if (isCurrent?.call() == false) {
      throw Exception('Workspace or account changed. Reopen the report.');
    }
    if (pending(record)) {
      throw Exception(
        'Sync or resolve pending local edits before generating a report.',
      );
    }
    final uri = ApiClient.uri('/lands/$id/report');
    if (kReleaseMode && uri.scheme != 'https') {
      throw Exception('Secure HTTPS is required to generate reports.');
    }
    final client = http.Client();
    try {
      final headers = ApiClient.jsonHeaders(bearerToken: token)
        ..remove('X-Company-Id')
        ..remove('Content-Type');
      if (company != null) headers['X-Company-Id'] = '$company';
      headers['Accept'] = 'application/pdf';
      final request = http.MultipartRequest('POST', uri)
        ..followRedirects = false
        ..headers.addAll(headers);
      if (logo != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'logo',
            logo.bytes,
            filename: logo.mimeType == 'image/png' ? 'logo.png' : 'logo.jpg',
            contentType: MediaType.parse(logo.mimeType),
          ),
        );
      }
      final response = await client.send(request).timeout(ApiClient.timeout);
      final limit = response.statusCode == 200 ? maxBytes : 64 * 1024;
      if ((response.contentLength ?? 0) > limit) {
        throw Exception('Report response exceeds the size limit.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(ApiClient.timeout)) {
        if (isCurrent?.call() == false) {
          throw Exception('Workspace or account changed. Reopen the report.');
        }
        if (bytes.length + chunk.length > limit) {
          throw Exception('Report response exceeds the size limit.');
        }
        bytes.add(chunk);
      }
      if (isCurrent?.call() == false) {
        throw Exception('Workspace or account changed. Reopen the report.');
      }
      final payload = bytes.takeBytes();
      if (response.statusCode != 200) {
        String message =
            'The report could not be generated. Refresh before trying again.';
        try {
          final body = jsonDecode(utf8.decode(payload));
          if (body is Map && body['message'] is String) {
            message = body['message'];
          }
        } catch (_) {}
        throw Exception(message);
      }
      if (response.headers['content-type']
                  ?.split(';')
                  .first
                  .trim()
                  .toLowerCase() !=
              'application/pdf' ||
          payload.length < 5 ||
          ascii.decode(payload.sublist(0, 5), allowInvalid: true) != '%PDF-') {
        throw Exception(
          'The server returned an invalid PDF. Refresh before trying again.',
        );
      }
    } on TimeoutException {
      throw Exception(
        'The request timed out. The report may have been generated; refresh before retrying.',
      );
    } finally {
      client.close();
    }
  }

  Future<SavedParcelPdf> details(
    String token,
    String record,
    int? company, {
    bool Function()? isCurrent,
  }) async {
    final response = await _get(
      token,
      record,
      company,
      'saved',
      isCurrent: isCurrent,
    );
    final body = jsonDecode(response.body);
    if (body is! Map || body['data'] is! Map) {
      throw Exception('The server did not return saved report details.');
    }
    return SavedParcelPdf.fromJson(Map<String, dynamic>.from(body['data']));
  }

  Future<ParcelPdfFile> download(
    String token,
    String record,
    int? company,
    String revision, {
    bool Function()? isCurrent,
  }) async {
    final response = await _get(
      token,
      record,
      company,
      'download',
      revision: revision,
      isCurrent: isCurrent,
    );
    final bytes = response.bodyBytes;
    if (response.headers['content-type']
                ?.split(';')
                .first
                .trim()
                .toLowerCase() !=
            'application/pdf' ||
        bytes.length < 5 ||
        ascii.decode(bytes.sublist(0, 5), allowInvalid: true) != '%PDF-' ||
        !['true', 'false'].contains(response.headers['x-report-stale'])) {
      throw Exception('The server did not return a valid saved PDF.');
    }
    return ParcelPdfFile(
      bytes,
      'parcel_${int.parse(record)}.pdf',
      stale: response.headers['x-report-stale'] == 'true',
    );
  }

  Future<ShareResultStatus> share(ParcelPdfFile file, Rect origin) async =>
      (await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              file.bytes,
              mimeType: 'application/pdf',
              name: file.name,
            ),
          ],
          fileNameOverrides: [file.name],
          sharePositionOrigin: origin,
        ),
      )).status;
}

final parcelPdfServiceProvider = Provider<ParcelPdfService>(
  (ref) => ParcelPdfService(),
);
