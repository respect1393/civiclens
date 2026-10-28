import 'dart:typed_data';

import '../models/civic_report.dart';
import 'api_client.dart';

/// The MIME type that matches a photo file extension.
///
/// Falls back to JPEG, the app's default camera format, for anything unknown so
/// the backend's byte-level validation remains the real gate.
String contentTypeForExtension(String extension) {
  switch (extension.trim().toLowerCase().replaceFirst('.', '')) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'jpg':
    case 'jpeg':
    default:
      return 'image/jpeg';
  }
}

/// Maps the report form's human-readable categories to the backend's
/// `ReportCategory` enum and back.
///
/// The two vocabularies are intentionally decoupled: the app keeps friendly
/// labels for citizens, while the backend stores stable enum names. The form
/// currently offers exactly these six options, so the mapping is 1:1. Anything
/// unrecognised falls back to the backend's catch-all (`SAFETY`) when sending,
/// and to the raw server value when displaying, so an unexpected value can
/// neither crash the app nor silently become a different category.
const Map<String, String> _categoryToApi = {
  'Pothole / Road Damage': 'ROADS',
  'Broken Streetlight': 'STREETLIGHTS',
  'Water Supply': 'WATER',
  'Garbage / Waste': 'WASTE',
  'Drainage': 'DRAINAGE',
  'Other': 'SAFETY',
};

const Map<String, String> _apiToCategory = {
  'ROADS': 'Pothole / Road Damage',
  'STREETLIGHTS': 'Broken Streetlight',
  'WATER': 'Water Supply',
  'WASTE': 'Garbage / Waste',
  'DRAINAGE': 'Drainage',
  'SAFETY': 'Other',
};

/// The backend enum name for a form category.
String apiCategoryFor(String uiCategory) {
  final key = uiCategory.trim();
  return _categoryToApi[key] ?? 'SAFETY';
}

/// The form category for a backend enum name.
///
/// Unknown names are returned unchanged rather than guessed, so the UI shows
/// the server's own value instead of mislabelling it.
String uiCategoryForApi(String apiCategory) {
  final key = apiCategory.trim().toUpperCase();
  return _apiToCategory[key] ?? apiCategory;
}

/// The Flutter status for a backend `ReportStatus` enum name.
///
/// The backend exposes five statuses but Flutter has no dedicated `rejected`
/// status, so `REJECTED` is mapped onto `needsMoreInformation` — the closest
/// existing meaning ("not accepted; action needed"). This is a deliberate,
/// documented, lossy mapping; the status history is never fabricated, and an
/// unknown value falls back to `reported` instead of inventing a status.
ReportStatus reportStatusForApi(Object? value) {
  if (value is! String) return ReportStatus.reported;
  switch (value.trim().toUpperCase()) {
    case 'SUBMITTED':
      return ReportStatus.reported;
    case 'UNDER_REVIEW':
      return ReportStatus.underReview;
    case 'IN_PROGRESS':
      return ReportStatus.inProgress;
    case 'RESOLVED':
      return ReportStatus.resolved;
    case 'REJECTED':
      return ReportStatus.needsMoreInformation;
    default:
      return ReportStatus.reported;
  }
}

/// Builds the citizen-safe request body for `POST /api/reports`.
///
/// Only fields the backend accepts are sent. Ownership and geography
/// (`userId`, `state`, `district`, role, password) are deliberately omitted —
/// the server derives them from the token. The photo is not part of this JSON
/// body; once the report exists its bytes are uploaded to the dedicated
/// `POST /api/reports/:id/photo` endpoint, so the local `photoFileName` is
/// never put in this payload either.
Map<String, dynamic> reportCreatePayload(CivicReport report) {
  final payload = <String, dynamic>{
    'title': report.title,
    'description': report.description,
    'category': apiCategoryFor(report.category),
    // The form collects a single human-readable location, so it is sent as
    // both the required `area` and `address`. Documented, consistent mapping.
    'area': report.locationLabel,
    'address': report.locationLabel,
  };

  final landmark = report.landmarkOrNull;
  if (landmark != null) {
    payload['landmark'] = landmark;
  }

  if (report.hasCoordinates) {
    payload['latitude'] = report.latitude;
    payload['longitude'] = report.longitude;
  }

  return payload;
}

/// Parses a backend report JSON object into a [CivicReport].
///
/// The result is marked [ReportOrigin.server]; the local `photoFileName` stays
/// null because the backend only ever returns its own `photoPath`, which is
/// kept separately in [CivicReport.serverPhotoPath]. Throws [FormatException]
/// when the identifier is missing so the caller can surface a safe error.
CivicReport civicReportFromApiJson(Map<String, dynamic> json) {
  final id = _asString(json['id']);
  if (id.isEmpty) {
    throw const FormatException('Report entry is missing its identifier.');
  }

  final photoPath = _asNullableString(json['photoPath']);

  return CivicReport(
    id: id,
    category: uiCategoryForApi(_asString(json['category'])),
    title: _asString(json['title'], fallback: 'Untitled report'),
    description: _asString(json['description']),
    locationLabel: _asString(
      json['address'],
      fallback: _asString(json['area'], fallback: 'Location unavailable'),
    ),
    landmark: _asNullableString(json['landmark']),
    latitude: _asDouble(json['latitude']),
    longitude: _asDouble(json['longitude']),
    createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
    status: reportStatusForApi(json['status']),
    origin: ReportOrigin.server,
    serverId: id,
    serverPhotoPath: photoPath,
  );
}

/// Reads and writes reports on the backend using the shared [ApiClient].
abstract class ReportApiService {
  /// Creates [report] on the backend and returns the stored record.
  Future<CivicReport> createReport({
    required String token,
    required CivicReport report,
  });

  /// Retrieves the reports visible to the current citizen.
  ///
  /// When [mine] is true, requests only reports submitted by the authenticated
  /// account (`GET /api/reports?mine=true`); otherwise requests reports within
  /// the account's geographic scope. When [district] is provided, results are
  /// limited to that district (the backend scopes it to the user's own state).
  Future<List<CivicReport>> fetchReports({
    required String token,
    bool mine = false,
    String? district,
  });

  /// Uploads [bytes] as the report's image and returns the stored reference.
  ///
  /// Completes only when the backend confirms the upload; failures surface as
  /// [ApiException]. Returns null only if the backend accepted the request but
  /// returned no reference, which callers treat as "photo not stored".
  Future<String?> uploadReportPhoto({
    required String token,
    required String reportId,
    required Uint8List bytes,
    required String contentType,
  });

  /// Fetches the report's stored image bytes, or null when there is none.
  ///
  /// Access is authenticated and authorized on the server, exactly as for the
  /// report itself.
  Future<Uint8List?> fetchReportPhoto({
    required String token,
    required String reportId,
  });

  /// Deletes the report identified by [reportId] on the backend.
  ///
  /// Completes only when the server confirms the deletion; failures surface as
  /// [ApiException] so the caller never reports success for a report that still
  /// exists on the server.
  Future<void> deleteReport({required String token, required String reportId});
}

/// HTTP implementation backed by the app's single [ApiClient].
///
/// All transport concerns (base URL, bearer token, timeouts, 401 handling,
/// citizen-safe errors) are handled by [ApiClient]; this class only shapes
/// report payloads and parses responses.
class HttpReportApiService implements ReportApiService {
  HttpReportApiService(this._client);

  final ApiClient _client;

  @override
  Future<CivicReport> createReport({
    required String token,
    required CivicReport report,
  }) async {
    final response = await _client.postJson(
      '/api/reports',
      reportCreatePayload(report),
      token: token,
    );
    try {
      return civicReportFromApiJson(response);
    } on FormatException {
      throw ApiException(
        failure: ApiFailure.invalidResponse,
        message: 'The server sent an unexpected response. Please try again.',
      );
    }
  }

  @override
  Future<List<CivicReport>> fetchReports({
    required String token,
    bool mine = false,
    String? district,
  }) async {
    final query = <String, String>{};
    if (mine) query['mine'] = 'true';
    if (district != null && district.trim().isNotEmpty) {
      query['district'] = district.trim();
    }
    final path = query.isNotEmpty
        ? '/api/reports?${Uri(queryParameters: query)}'
        : '/api/reports';
    final response = await _client.getJson(path, token: token);
    final data = response['data'];
    if (data is! List) {
      throw ApiException(
        failure: ApiFailure.invalidResponse,
        message: 'The server sent an unexpected response. Please try again.',
      );
    }

    final reports = <CivicReport>[];
    for (final entry in data) {
      if (entry is! Map) continue;
      try {
        reports.add(civicReportFromApiJson(Map<String, dynamic>.from(entry)));
      } on FormatException {
        // Skip a single unreadable entry rather than discarding the list.
      }
    }
    return reports;
  }

  @override
  Future<String?> uploadReportPhoto({
    required String token,
    required String reportId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final response = await _client.postBytes(
      '/api/reports/${Uri.encodeComponent(reportId)}/photo',
      bytes,
      contentType: contentType,
      token: token,
    );
    final path = response['photoPath'];
    return path is String && path.trim().isNotEmpty ? path.trim() : null;
  }

  @override
  Future<Uint8List?> fetchReportPhoto({
    required String token,
    required String reportId,
  }) async {
    try {
      return await _client.getBytes(
        '/api/reports/${Uri.encodeComponent(reportId)}/photo',
        token: token,
      );
    } on ApiException catch (error) {
      // "No image for this report" is an expected, non-fatal outcome.
      if (error.failure == ApiFailure.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<void> deleteReport({
    required String token,
    required String reportId,
  }) async {
    await _client.deleteJson(
      '/api/reports/${Uri.encodeComponent(reportId)}',
      token: token,
    );
  }
}

String _asString(Object? value, {String fallback = ''}) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value != null) {
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return fallback;
}

String? _asNullableString(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}
