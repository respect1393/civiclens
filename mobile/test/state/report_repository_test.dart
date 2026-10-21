import 'dart:io';
import 'dart:typed_data';

import 'package:civiclens_mobile/models/civic_report.dart';
import 'package:civiclens_mobile/services/api_client.dart';
import 'package:civiclens_mobile/services/report_store.dart';
import 'package:civiclens_mobile/state/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_report_api_service.dart';
import '../helpers/fake_report_store.dart';

CivicReport _serverReport(
  String id, {
  String title = 'Server report',
  ReportStatus status = ReportStatus.reported,
  String? serverPhotoPath,
  DateTime? createdAt,
}) => CivicReport(
  id: id,
  category: 'Drainage',
  title: title,
  description: 'Reported to the city.',
  locationLabel: 'Main Road',
  latitude: 12,
  longitude: 77,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 2),
  status: status,
  origin: ReportOrigin.server,
  serverId: id,
  serverPhotoPath: serverPhotoPath,
);

void main() {
  group('load', () {
    test('is empty and silent when there is no session', () async {
      final api = FakeReportApiService();
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: api,
        accessToken: () => null,
      );

      await repository.load();

      expect(repository.isLoaded, isTrue);
      expect(repository.reports, isEmpty);
      expect(repository.lastError, isNull);
      expect(api.fetchTokens, isEmpty);
    });

    test('fetches server reports and sorts them newest first', () async {
      final api = FakeReportApiService(
        onFetch: ({required token}) async => [
          _serverReport('old', createdAt: DateTime.utc(2026, 1, 1)),
          _serverReport('new', createdAt: DateTime.utc(2026, 3, 1)),
        ],
      );
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: api,
        accessToken: () => 'token-1',
      );

      await repository.load();

      expect(api.fetchTokens, ['token-1']);
      expect(repository.reports.map((r) => r.id).toList(), ['new', 'old']);
      expect(repository.reportCount, 2);
      expect(repository.lastError, isNull);
    });

    test('keeps the previous list and records the error on failure', () async {
      var attempts = 0;
      final api = FakeReportApiService(
        onFetch: ({required token}) async {
          attempts += 1;
          if (attempts == 1) return [_serverReport('srv-1')];
          throw ApiException(
            failure: ApiFailure.network,
            message: 'Could not reach the server.',
          );
        },
      );
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: api,
        accessToken: () => 'token-1',
      );

      await repository.load();
      expect(repository.reportCount, 1);

      await repository.load();

      // The earlier server data is kept so the UI does not blank out.
      expect(repository.reportCount, 1);
      expect(repository.lastError, isA<ApiException>());
    });
  });

  group('submitReport', () {
    test('requires a session', () async {
      final api = FakeReportApiService();
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: api,
        accessToken: () => null,
      );

      await expectLater(
        repository.submitReport(
          category: 'Water Supply',
          title: 'Leak',
          description: 'Pipe leaking.',
          locationLabel: 'Main Road',
          latitude: 1,
          longitude: 2,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(api.createCalls, isEmpty);
      expect(repository.reportCount, 0);
    });

    test('creates the report and uploads its photo', () async {
      final store = FakeReportStore();
      final api = FakeReportApiService();
      final repository = ReportRepository(
        store: store,
        apiService: api,
        accessToken: () => 'token-1',
      );

      final saved = await repository.submitReport(
        category: 'Water Supply',
        title: 'Leak',
        description: 'Pipe leaking near the market.',
        locationLabel: 'Main Road',
        latitude: 12,
        longitude: 77,
        photoBytes: Uint8List.fromList(const [1, 2, 3]),
        photoExtension: 'png',
      );

      expect(api.createCalls.single.token, 'token-1');
      expect(repository.reports.single.id, saved.id);
      expect(saved.isServerBacked, isTrue);
      expect(saved.hasPhoto, isTrue);
      expect(store.savedImages.containsKey(saved.photoFileName), isTrue);

      // The bytes went up with the extension's MIME type.
      expect(api.uploadCalls.single.reportId, saved.id);
      expect(api.uploadCalls.single.contentType, 'image/png');
      expect(api.uploadCalls.single.bytes, const [1, 2, 3]);
      expect(saved.hasServerPhoto, isTrue);
      expect(saved.serverPhotoPath, 'reports/${saved.id}.jpg');
    });

    test(
      'keeps the report but flags the photo when the upload fails',
      () async {
        final store = FakeReportStore();
        final api = FakeReportApiService(
          onUploadPhoto:
              ({
                required token,
                required reportId,
                required bytes,
                required contentType,
              }) => throw ApiException(
                failure: ApiFailure.network,
                message: 'Could not upload the photo.',
              ),
        );
        final repository = ReportRepository(
          store: store,
          apiService: api,
          accessToken: () => 'token-1',
        );

        final saved = await repository.submitReport(
          category: 'Water Supply',
          title: 'Leak',
          description: 'Pipe leaking near the market.',
          locationLabel: 'Main Road',
          latitude: 12,
          longitude: 77,
          photoBytes: Uint8List.fromList(const [1, 2, 3]),
        );

        // The report exists and the cached photo renders, but the server holds
        // no image, so it is never claimed as uploaded.
        expect(saved.isServerBacked, isTrue);
        expect(saved.hasPhoto, isTrue);
        expect(saved.hasServerPhoto, isFalse);
        expect(saved.serverPhotoPath, isNull);
      },
    );

    test('does not upload when no photo is attached', () async {
      final api = FakeReportApiService();
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: api,
        accessToken: () => 'token-1',
      );

      final saved = await repository.submitReport(
        category: 'Drainage',
        title: 'Blocked drain',
        description: 'Water is not draining.',
        locationLabel: 'Hill View',
        latitude: 3,
        longitude: 4,
      );

      expect(saved.hasPhoto, isFalse);
      expect(saved.hasServerPhoto, isFalse);
      expect(api.uploadCalls, isEmpty);
    });

    test('stores the landmark and drops it when blank', () async {
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: FakeReportApiService(),
        accessToken: () => 'token-1',
      );

      final withLandmark = await repository.submitReport(
        category: 'Streetlight',
        title: 'Broken lamp',
        description: 'The lamp post stays dark at night.',
        locationLabel: 'Chanmari, Aizawl',
        landmark: '  Near the community hall  ',
        latitude: 23.7271,
        longitude: 92.7176,
      );
      expect(withLandmark.landmark, 'Near the community hall');
      expect(withLandmark.landmarkOrNull, 'Near the community hall');

      final without = await repository.submitReport(
        category: 'Streetlight',
        title: 'Another lamp',
        description: 'Also dark at night.',
        locationLabel: 'Chanmari, Aizawl',
        landmark: '   ',
        latitude: 23.7271,
        longitude: 92.7176,
      );
      expect(without.landmark, isNull);
      expect(without.landmarkOrNull, isNull);
    });

    test('surfaces a failed creation and adds nothing', () async {
      final api = FakeReportApiService(
        onCreate: ({required token, required report}) => throw ApiException(
          failure: ApiFailure.network,
          message: 'Could not reach the server.',
        ),
      );
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: api,
        accessToken: () => 'token-1',
      );

      await expectLater(
        repository.submitReport(
          category: 'Water Supply',
          title: 'Leak',
          description: 'Pipe leaking near the market.',
          locationLabel: 'Main Road',
          latitude: 12,
          longitude: 77,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(repository.reportCount, 0);
    });

    test(
      'creates and uploads even with no local store directory configured',
      () async {
        final api = FakeReportApiService();
        // No `store:` is passed, matching main.dart. The default store must
        // degrade to a no-op cache rather than throwing the "no base directory"
        // StateError that aborted submissions on real devices.
        final repository = ReportRepository(
          apiService: api,
          accessToken: () => 'token-1',
        );

        final saved = await repository.submitReport(
          category: 'Water Supply',
          title: 'Leak',
          description: 'Pipe leaking near the market.',
          locationLabel: 'Main Road',
          latitude: 12,
          longitude: 77,
          photoBytes: Uint8List.fromList(const [1, 2, 3]),
        );

        expect(repository.reportCount, 1);
        expect(saved.isServerBacked, isTrue);
        // The photo reached the backend even though it could not be cached.
        expect(api.uploadCalls.single.reportId, saved.id);
        expect(saved.hasServerPhoto, isTrue);
      },
    );

    test(
      'recovers the report when an ambiguous create actually landed',
      () async {
        final api = FakeReportApiService(
          onCreate: ({required token, required report}) => throw ApiException(
            failure: ApiFailure.network,
            message: 'The connection dropped.',
          ),
          onFetch: ({required token}) async => [
            CivicReport(
              id: 'srv-99',
              category: 'Water Supply',
              title: 'Leak',
              description: 'Pipe leaking near the market.',
              locationLabel: 'Main Road',
              latitude: 12,
              longitude: 77,
              createdAt: DateTime.now(),
              origin: ReportOrigin.server,
              serverId: 'srv-99',
            ),
          ],
        );
        final repository = ReportRepository(
          store: FakeReportStore(),
          apiService: api,
          accessToken: () => 'token-1',
        );

        final saved = await repository.submitReport(
          category: 'Water Supply',
          title: 'Leak',
          description: 'Pipe leaking near the market.',
          locationLabel: 'Main Road',
          latitude: 12,
          longitude: 77,
        );

        // The failed create is reconciled against the server, so the citizen is
        // not invited to resubmit and file a duplicate.
        expect(saved.serverId, 'srv-99');
        expect(repository.reportCount, 1);
      },
    );
  });

  group('deleteReport', () {
    test('requires a session', () async {
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: FakeReportApiService(),
        accessToken: () => null,
      );

      await expectLater(
        repository.deleteReport('srv-1'),
        throwsA(isA<ApiException>()),
      );
    });

    test(
      'removes the report and its local photo after the server confirms',
      () async {
        final store = FakeReportStore();
        final repository = ReportRepository(
          store: store,
          apiService: FakeReportApiService(),
          accessToken: () => 'token-1',
        );

        final saved = await repository.submitReport(
          category: 'Water Supply',
          title: 'Leak',
          description: 'Pipe leaking near the market.',
          locationLabel: 'Main Road',
          latitude: 12,
          longitude: 77,
          photoBytes: Uint8List.fromList(const [4, 5, 6]),
        );
        expect(store.savedImages, contains(saved.photoFileName));

        await repository.deleteReport(saved.id);

        expect(repository.reportCount, 0);
        expect(repository.findById(saved.id), isNull);
        expect(store.savedImages, isEmpty);
      },
    );

    test('keeps the report when the server rejects the delete', () async {
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: _FailingDeleteService(),
        accessToken: () => 'token-1',
      );
      await repository.load();
      await repository.submitReport(
        category: 'Water Supply',
        title: 'Leak',
        description: 'Pipe leaking near the market.',
        locationLabel: 'Main Road',
        latitude: 12,
        longitude: 77,
      );

      await expectLater(
        repository.deleteReport('srv-1'),
        throwsA(isA<ApiException>()),
      );
      expect(repository.reportCount, 1);
      expect(repository.findById('srv-1'), isNotNull);
    });
  });

  group('resolveReportImage', () {
    test('returns the cached bytes when the file exists', () async {
      final tempDir = Directory.systemTemp.createTempSync('civiclens-repo-');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final store = ReportStore(directory: tempDir);
      final bytes = Uint8List.fromList(const [4, 5, 6, 7]);
      final fileName = await store.saveReportImage('srv-1', bytes);

      final repository = ReportRepository(
        store: store,
        apiService: FakeReportApiService(),
        accessToken: () => 'token-1',
      );
      final report = CivicReport(
        id: 'srv-1',
        category: 'Drainage',
        title: 'Blocked drain',
        description: 'Water is not draining.',
        locationLabel: 'Hill View',
        latitude: 3,
        longitude: 4,
        createdAt: DateTime.now(),
        origin: ReportOrigin.server,
        serverId: 'srv-1',
        photoFileName: fileName,
        serverPhotoPath: 'reports/srv-1.jpg',
      );

      expect(await repository.resolveReportImage(report), bytes);
    });

    test('falls back to the authenticated server copy', () async {
      final api = FakeReportApiService(
        photoBytes: Uint8List.fromList(const [8, 8, 8]),
      );
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: api,
        accessToken: () => 'token-1',
      );
      final report = _serverReport(
        'srv-9',
        serverPhotoPath: 'reports/srv-9.jpg',
      );

      expect(await repository.resolveReportImage(report), const [8, 8, 8]);
      expect(api.fetchPhotoCalls.single.reportId, 'srv-9');
    });

    test('returns null when there is no image anywhere', () async {
      final repository = ReportRepository(
        store: FakeReportStore(),
        apiService: FakeReportApiService(),
        accessToken: () => 'token-1',
      );

      expect(
        await repository.resolveReportImage(_serverReport('srv-1')),
        isNull,
      );
    });
  });
}

/// A [ReportApiService] whose delete always fails, for rollback coverage.
class _FailingDeleteService extends FakeReportApiService {
  @override
  Future<void> deleteReport({
    required String token,
    required String reportId,
  }) async {
    throw ApiException(
      failure: ApiFailure.server,
      message: 'Could not delete this report.',
    );
  }
}
