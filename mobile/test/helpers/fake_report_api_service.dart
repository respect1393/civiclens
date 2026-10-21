import 'dart:typed_data';

import 'package:civiclens_mobile/models/civic_report.dart';
import 'package:civiclens_mobile/services/report_api_service.dart';

/// A [ReportApiService] double that records calls and never touches the network.
class FakeReportApiService implements ReportApiService {
  FakeReportApiService({
    this.onCreate,
    this.onFetch,
    this.onUploadPhoto,
    this.onFetchPhoto,
    this.onDelete,
    this.photoBytes,
  });

  Future<CivicReport> Function({
    required String token,
    required CivicReport report,
  })?
  onCreate;

  Future<List<CivicReport>> Function({required String token})? onFetch;

  Future<void> Function({required String token, required String reportId})?
  onDelete;

  Future<String?> Function({
    required String token,
    required String reportId,
    required Uint8List bytes,
    required String contentType,
  })?
  onUploadPhoto;

  Future<Uint8List?> Function({
    required String token,
    required String reportId,
  })?
  onFetchPhoto;

  /// Bytes returned by [fetchReportPhoto]; null means "no stored image".
  Uint8List? photoBytes;

  final List<({String token, CivicReport report})> createCalls = [];
  final List<String> fetchTokens = [];
  final List<
    ({String token, String reportId, Uint8List bytes, String contentType})
  >
  uploadCalls = [];
  final List<({String token, String reportId})> fetchPhotoCalls = [];
  final List<({String token, String reportId})> deleteCalls = [];

  /// Builds the canned server response for a report: a server-assigned id and
  /// origin, so delivery merges look like a real round trip.
  static CivicReport serverEcho(CivicReport report, {String id = 'srv-1'}) =>
      CivicReport(
        id: id,
        category: report.category,
        title: report.title,
        description: report.description,
        locationLabel: report.locationLabel,
        landmark: report.landmarkOrNull,
        latitude: report.latitude,
        longitude: report.longitude,
        createdAt: report.createdAt,
        status: report.status,
        origin: ReportOrigin.server,
        serverId: id,
      );

  @override
  Future<CivicReport> createReport({
    required String token,
    required CivicReport report,
  }) {
    createCalls.add((token: token, report: report));
    final handler = onCreate;
    if (handler == null) return Future.value(serverEcho(report));
    return handler(token: token, report: report);
  }

  @override
  Future<List<CivicReport>> fetchReports({required String token}) {
    fetchTokens.add(token);
    final handler = onFetch;
    if (handler == null) return Future.value(<CivicReport>[]);
    return handler(token: token);
  }

  @override
  Future<String?> uploadReportPhoto({
    required String token,
    required String reportId,
    required Uint8List bytes,
    required String contentType,
  }) {
    uploadCalls.add((
      token: token,
      reportId: reportId,
      bytes: bytes,
      contentType: contentType,
    ));
    final handler = onUploadPhoto;
    if (handler == null) return Future.value('reports/$reportId.jpg');
    return handler(
      token: token,
      reportId: reportId,
      bytes: bytes,
      contentType: contentType,
    );
  }

  @override
  Future<Uint8List?> fetchReportPhoto({
    required String token,
    required String reportId,
  }) {
    fetchPhotoCalls.add((token: token, reportId: reportId));
    final handler = onFetchPhoto;
    if (handler == null) return Future.value(photoBytes);
    return handler(token: token, reportId: reportId);
  }

  @override
  Future<void> deleteReport({required String token, required String reportId}) {
    deleteCalls.add((token: token, reportId: reportId));
    final handler = onDelete;
    if (handler == null) return Future.value();
    return handler(token: token, reportId: reportId);
  }
}
