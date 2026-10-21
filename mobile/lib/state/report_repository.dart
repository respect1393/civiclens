import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/civic_report.dart';
import '../services/api_client.dart';
import '../services/report_api_service.dart';
import '../services/report_store.dart';

/// Backend-backed view over the citizen's civic reports.
///
/// The municipal backend is the single source of truth. Reports are fetched
/// with [load], created with [submitReport] and removed with [deleteReport];
/// nothing is written to a local report database, so the app never shows a
/// stale or invented list. Report photos are uploaded to the backend, which is
/// their durable home; the device keeps only a short-lived cache of the bytes
/// the citizen attached (see [ReportStore]) so the image renders instantly.
class ReportRepository extends ChangeNotifier {
  ReportRepository({
    ReportStore? store,
    ReportApiService? apiService,
    String? Function()? accessToken,
  }) : _store = store ?? ReportStore(),
       // Private fields cannot be initialising formals for named parameters.
       // ignore: prefer_initializing_formals
       _apiService = apiService,
       // ignore: prefer_initializing_formals
       _accessToken = accessToken;

  final ReportStore _store;
  final ReportApiService? _apiService;

  /// Supplies the current bearer token, or null when signed out.
  ///
  /// It is a callback rather than a stored value so the repository always sees
  /// the latest session without holding credentials of its own.
  final String? Function()? _accessToken;

  final List<CivicReport> _reports = <CivicReport>[];

  bool _isLoaded = false;
  bool _isLoading = false;
  Object? _lastError;

  /// The reports the backend returns, newest first.
  List<CivicReport> get reports => List<CivicReport>.unmodifiable(_reports);

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;

  /// Error from the most recent load attempt, if any.
  Object? get lastError => _lastError;

  int get reportCount => _reports.length;

  /// Whether a session is available to talk to the backend.
  bool get isSignedIn {
    final token = _accessToken?.call();
    return _apiService != null && token != null && token.isNotEmpty;
  }

  /// Count of reports for each status.
  Map<ReportStatus, int> get statusCounts {
    final counts = <ReportStatus, int>{
      for (final status in ReportStatus.values) status: 0,
    };
    for (final report in _reports) {
      counts[report.status] = (counts[report.status] ?? 0) + 1;
    }
    return counts;
  }

  CivicReport? findById(String id) {
    for (final report in _reports) {
      if (report.id == id || report.serverId == id) return report;
    }
    return null;
  }

  /// Fetches the reports visible to the signed-in citizen from the backend.
  ///
  /// Safe to call repeatedly. When a request fails the previous (server-sourced)
  /// list is kept and [lastError] is set, so the UI can show an honest error
  /// instead of silently reverting to local or demo data. Signed-out callers
  /// end with an empty list and no error.
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final service = _apiService;
      final token = _accessToken?.call();
      if (service == null || token == null || token.isEmpty) {
        _reports.clear();
        _lastError = null;
      } else {
        final fetched = await service.fetchReports(token: token);
        fetched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _reports
          ..clear()
          ..addAll(fetched);
        _lastError = null;
      }
      _isLoaded = true;
    } catch (error) {
      _lastError = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates a report on the backend, returning the stored record.
  ///
  /// The report only exists once the backend accepts it: nothing is added to
  /// [reports] before the request succeeds, so a failed submission is never
  /// shown as saved. When [photoBytes] are supplied they are (1) cached on the
  /// device for immediate display and (2) uploaded to the backend, which is now
  /// the durable home of the image. A photo upload failure does not discard the
  /// already-created report; it simply leaves [CivicReport.serverPhotoPath]
  /// null so the UI can be honest about the missing evidence. [ApiException]
  /// from report creation itself is rethrown so the UI can explain the failure
  /// and let the citizen retry.
  Future<CivicReport> submitReport({
    required String category,
    required String title,
    required String description,
    required String locationLabel,
    required double latitude,
    required double longitude,
    String? landmark,
    Uint8List? photoBytes,
    String photoExtension = 'jpg',
  }) async {
    final service = _apiService;
    final token = _accessToken?.call();
    if (service == null || token == null || token.isEmpty) {
      throw ApiException(
        failure: ApiFailure.unauthorized,
        message: 'Please sign in to submit a report.',
      );
    }

    final trimmedLandmark = landmark?.trim();
    final draft = CivicReport(
      id: 'draft',
      category: category,
      title: title,
      description: description,
      locationLabel: locationLabel,
      latitude: latitude,
      longitude: longitude,
      landmark: (trimmedLandmark == null || trimmedLandmark.isEmpty)
          ? null
          : trimmedLandmark,
      createdAt: DateTime.now(),
      status: ReportStatus.reported,
    );

    final created = await _createReport(token: token, draft: draft);

    final hasPhoto = photoBytes != null && photoBytes.isNotEmpty;

    String? photoFileName;
    if (hasPhoto) {
      // Caching the bytes is a best-effort convenience only. The report has
      // already been created, so a cache miss must never fail the submission.
      try {
        photoFileName = await _store.saveReportImage(
          created.id,
          photoBytes,
          extension: photoExtension,
        );
      } catch (_) {
        photoFileName = null;
      }
    }

    var saved = created.copyWith(photoFileName: photoFileName);

    if (hasPhoto) {
      try {
        final serverPath = await service.uploadReportPhoto(
          token: token,
          reportId: created.id,
          bytes: photoBytes,
          contentType: contentTypeForExtension(photoExtension),
        );
        if (serverPath != null) {
          saved = saved.copyWith(serverPhotoPath: serverPath);
        }
      } catch (_) {
        // The report exists but its photo did not reach the backend. Keeping
        // serverPhotoPath null is what lets the UI report this honestly.
      }
    }

    _reports.insert(0, saved);
    _reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
    return saved;
  }

  /// Deletes the report identified by [id] on the backend.
  ///
  /// The local list is only updated after the server confirms the deletion, so
  /// a failed request never leaves the UI claiming a still-existing report is
  /// gone. [ApiException] is rethrown on failure.
  Future<void> deleteReport(String id) async {
    final service = _apiService;
    final token = _accessToken?.call();
    if (service == null || token == null || token.isEmpty) {
      throw ApiException(
        failure: ApiFailure.unauthorized,
        message: 'Please sign in again to delete this report.',
      );
    }

    await service.deleteReport(token: token, reportId: id);

    final index = _reports.indexWhere(
      (report) => report.id == id || report.serverId == id,
    );
    if (index < 0) return;

    final removed = _reports.removeAt(index);
    _lastError = null;

    final photoFileName = removed.photoFileName;
    if (photoFileName != null && photoFileName.trim().isNotEmpty) {
      final stillReferenced = _reports.any(
        (report) => report.photoFileName == photoFileName,
      );
      if (!stillReferenced) {
        await _store.deleteImage(photoFileName);
      }
    }

    notifyListeners();
  }

  /// Creates the report on the backend, recovering from an ambiguous failure.
  ///
  /// A timeout or a dropped connection cannot tell us whether the server
  /// processed the request. Rather than risk the citizen resubmitting and
  /// creating a duplicate, we re-fetch the list and, when a report matching this
  /// draft has clearly just landed, return it as the created record. A request
  /// that failed for any other (definite) reason is rethrown unchanged.
  Future<CivicReport> _createReport({
    required String token,
    required CivicReport draft,
  }) async {
    try {
      return await _apiService!.createReport(token: token, report: draft);
    } on ApiException catch (error) {
      if (error.failure == ApiFailure.timeout ||
          error.failure == ApiFailure.network) {
        final recovered = await _findJustCreatedReport(
          token: token,
          draft: draft,
        );
        if (recovered != null) return recovered;
      }
      rethrow;
    }
  }

  /// Looks for the report a just-failed create may nevertheless have persisted.
  ///
  /// Only a close field match created within a short window counts, so an
  /// unrelated older report is never mistaken for this submission. Any failure
  /// to reconcile returns null and lets the original error surface.
  Future<CivicReport?> _findJustCreatedReport({
    required String token,
    required CivicReport draft,
  }) async {
    try {
      final fetched = await _apiService!.fetchReports(token: token);
      for (final report in fetched) {
        if (_isSameSubmission(report, draft)) return report;
      }
    } catch (_) {
      // Reconciliation is best-effort; fall back to reporting the failure.
    }
    return null;
  }

  bool _isSameSubmission(CivicReport candidate, CivicReport draft) {
    final withinWindow =
        candidate.createdAt.difference(draft.createdAt).abs() <
        const Duration(minutes: 5);
    return withinWindow &&
        candidate.title == draft.title &&
        candidate.description == draft.description &&
        candidate.locationLabel == draft.locationLabel;
  }

  /// Resolves a stored image reference to an existing file, or null.
  Future<File?> resolveImage(CivicReport report) {
    return _store.resolveImage(report.photoFileName);
  }

  /// Resolves a report's image bytes for display.
  ///
  /// Preference order:
  ///  1. the local cache written when the photo was captured (instant, works
  ///     offline),
  ///  2. otherwise, for a server-backed report, the authenticated image
  ///     endpoint — so reports fetched from the backend (including other
  ///     citizens' reports in the same area) show their stored evidence.
  ///
  /// Returns null when no image is available; callers fall back to a
  /// placeholder rather than showing a broken image.
  Future<Uint8List?> resolveReportImage(CivicReport report) async {
    File? file;
    try {
      file = await _store.resolveImage(report.photoFileName);
    } catch (_) {
      file = null;
    }
    if (file != null) {
      try {
        return await file.readAsBytes();
      } catch (_) {
        // Fall through to the backend copy when the cached file is unreadable.
      }
    }

    final service = _apiService;
    final token = _accessToken?.call();
    final hasServerPhoto =
        report.isServerBacked && (report.serverPhotoPath?.isNotEmpty ?? false);
    if (service == null || token == null || token.isEmpty || !hasServerPhoto) {
      return null;
    }

    try {
      return await service.fetchReportPhoto(
        token: token,
        reportId: report.serverId ?? report.id,
      );
    } catch (_) {
      return null;
    }
  }
}
