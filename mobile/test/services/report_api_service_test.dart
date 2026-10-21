import 'dart:convert';

import 'dart:typed_data';

import 'package:civiclens_mobile/models/civic_report.dart';
import 'package:civiclens_mobile/services/api_client.dart';
import 'package:civiclens_mobile/services/report_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records every request the service makes and replies with [respond].
class _Recorder {
  final List<http.Request> requests = [];

  http.Client client(http.Response Function(http.Request request) respond) =>
      MockClient((request) {
        requests.add(request);
        return Future.value(respond(request));
      });

  http.Request get last => requests.last;

  Map<String, dynamic> get lastBody =>
      jsonDecode(last.body) as Map<String, dynamic>;
}

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

CivicReport _report({
  String category = 'Water Supply',
  String? landmark,
  double latitude = 6.5244,
  double longitude = 3.3792,
  String? photoFileName,
}) => CivicReport(
  id: 'CL-ABC-0001',
  category: category,
  title: 'Leaking pipe near the market',
  description: 'Water leaks from the pipe every morning.',
  locationLabel: 'Kulikawn, Aizawl',
  landmark: landmark,
  latitude: latitude,
  longitude: longitude,
  createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
  photoFileName: photoFileName,
);

void main() {
  group('category mapping', () {
    test('maps every form category onto its backend enum', () {
      expect(apiCategoryFor('Pothole / Road Damage'), 'ROADS');
      expect(apiCategoryFor('Broken Streetlight'), 'STREETLIGHTS');
      expect(apiCategoryFor('Water Supply'), 'WATER');
      expect(apiCategoryFor('Garbage / Waste'), 'WASTE');
      expect(apiCategoryFor('Drainage'), 'DRAINAGE');
      expect(apiCategoryFor('Other'), 'SAFETY');
    });

    test('an unknown form category falls back to the catch-all', () {
      expect(apiCategoryFor('Alien invasion'), 'SAFETY');
    });

    test('maps backend enums back to form categories', () {
      expect(uiCategoryForApi('ROADS'), 'Pothole / Road Damage');
      expect(uiCategoryForApi('STREETLIGHTS'), 'Broken Streetlight');
      expect(uiCategoryForApi('WATER'), 'Water Supply');
      expect(uiCategoryForApi('WASTE'), 'Garbage / Waste');
      expect(uiCategoryForApi('DRAINAGE'), 'Drainage');
      expect(uiCategoryForApi('SAFETY'), 'Other');
    });

    test('an unknown backend enum is shown unchanged, not guessed', () {
      expect(uiCategoryForApi('PARKS'), 'PARKS');
    });
  });

  group('status mapping', () {
    test('maps every backend status onto the Flutter model', () {
      expect(reportStatusForApi('SUBMITTED'), ReportStatus.reported);
      expect(reportStatusForApi('UNDER_REVIEW'), ReportStatus.underReview);
      expect(reportStatusForApi('IN_PROGRESS'), ReportStatus.inProgress);
      expect(reportStatusForApi('RESOLVED'), ReportStatus.resolved);
      expect(reportStatusForApi('REJECTED'), ReportStatus.needsMoreInformation);
    });

    test('an unknown or missing status never crashes; it falls back', () {
      expect(reportStatusForApi('ESCALATED'), ReportStatus.reported);
      expect(reportStatusForApi(null), ReportStatus.reported);
      expect(reportStatusForApi(42), ReportStatus.reported);
    });

    test('matching is case-insensitive', () {
      expect(reportStatusForApi('under_review'), ReportStatus.underReview);
    });
  });

  group('reportCreatePayload', () {
    test('sends only backend-known fields and never client authority', () {
      final payload = reportCreatePayload(
        _report(landmark: 'Near the community hall', photoFileName: 'CL.1.jpg'),
      );

      expect(payload, {
        'title': 'Leaking pipe near the market',
        'description': 'Water leaks from the pipe every morning.',
        'category': 'WATER',
        'area': 'Kulikawn, Aizawl',
        'address': 'Kulikawn, Aizawl',
        'landmark': 'Near the community hall',
        'latitude': 6.5244,
        'longitude': 3.3792,
      });
      for (final forbidden in const [
        'userId',
        'state',
        'district',
        'role',
        'password',
        'photoFileName',
        'photoPath',
      ]) {
        expect(payload.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });

    test('omits the landmark when none was supplied', () {
      final payload = reportCreatePayload(_report());
      expect(payload.containsKey('landmark'), isFalse);
    });

    test('omits coordinates that are not a real reporting point', () {
      final payload = reportCreatePayload(_report(latitude: 0, longitude: 0));
      expect(payload.containsKey('latitude'), isFalse);
      expect(payload.containsKey('longitude'), isFalse);
    });
  });

  group('HttpReportApiService.createReport', () {
    test('posts the mapped payload with the bearer token', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client(
            (_) => _json(201, {
              'id': 'srv-123',
              'category': 'WATER',
              'title': 'Leaking pipe near the market',
              'description': 'Water leaks from the pipe every morning.',
              'area': 'Kulikawn, Aizawl',
              'address': 'Kulikawn, Aizawl',
              'status': 'SUBMITTED',
              'createdAt': '2026-01-02T03:04:05.000Z',
            }),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      final created = await service.createReport(
        token: 'jwt-token',
        report: _report(),
      );

      expect(recorder.last.method, 'POST');
      expect(recorder.last.url.path, '/api/reports');
      expect(recorder.last.headers['Authorization'], 'Bearer jwt-token');
      expect(recorder.lastBody['category'], 'WATER');
      expect(recorder.lastBody['area'], 'Kulikawn, Aizawl');
      expect(recorder.lastBody['address'], 'Kulikawn, Aizawl');

      expect(created.id, 'srv-123');
      expect(created.serverId, 'srv-123');
      expect(created.origin, ReportOrigin.server);
      expect(created.isServerBacked, isTrue);
      expect(created.status, ReportStatus.reported);
      expect(created.createdAt.toUtc(), DateTime.utc(2026, 1, 2, 3, 4, 5));
      // The backend only has its own photoPath; no local photo is claimed.
      expect(created.photoFileName, isNull);
      expect(created.serverPhotoPath, isNull);
    });

    test('keeps a backend photoPath separate from any local photo', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client(
            (_) => _json(201, {
              'id': 'srv-9',
              'category': 'ROADS',
              'title': 'Pothole',
              'description': 'A deep pothole.',
              'address': 'Main Street',
              'status': 'UNDER_REVIEW',
              'createdAt': '2026-02-03T00:00:00.000Z',
              'photoPath': 'uploads/srv-9.jpg',
            }),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      final created = await service.createReport(
        token: 't',
        report: _report(category: 'Pothole / Road Damage'),
      );

      expect(created.serverPhotoPath, 'uploads/srv-9.jpg');
      expect(created.photoFileName, isNull);
      expect(created.hasPhoto, isFalse);
      expect(created.status, ReportStatus.underReview);
    });

    test('a body without an id is an invalidResponse failure', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client((_) => _json(201, {'unexpected': true})),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.createReport(token: 't', report: _report()),
        throwsA(
          isA<ApiException>().having(
            (e) => e.failure,
            'failure',
            ApiFailure.invalidResponse,
          ),
        ),
      );
    });

    test('an unreachable server becomes a network failure', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client(
            (_) => throw http.ClientException('connection refused'),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.createReport(token: 't', report: _report()),
        throwsA(
          isA<ApiException>().having(
            (e) => e.failure,
            'failure',
            ApiFailure.network,
          ),
        ),
      );
    });

    test('a 401 on a token-bearing request fires onUnauthorized', () async {
      final recorder = _Recorder();
      var unauthorizedCalls = 0;
      final client = ApiClient(
        client: recorder.client((_) => _json(401, {'error': 'Invalid token'})),
        baseUrl: 'http://localhost:3000',
      )..onUnauthorized = () => unauthorizedCalls += 1;

      await expectLater(
        HttpReportApiService(client)
            .createReport(token: 'expired', report: _report()),
        throwsA(isA<ApiException>()),
      );

      expect(unauthorizedCalls, 1);
    });
  });

  group('HttpReportApiService.fetchReports', () {
    test('reads the paginated envelope and parses each report', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client(
            (_) => _json(200, {
              'data': [
                {
                  'id': 'srv-1',
                  'category': 'WASTE',
                  'title': 'Garbage pile',
                  'description': 'Bins overflowing.',
                  'address': 'Market Road',
                  'status': 'RESOLVED',
                  'createdAt': '2026-01-01T00:00:00.000Z',
                },
                {
                  'id': 'srv-2',
                  'category': 'DRAINAGE',
                  'title': 'Blocked drain',
                  'description': 'Water not draining.',
                  'address': 'Hill View',
                  'status': 'REJECTED',
                  'createdAt': '2026-01-02T00:00:00.000Z',
                },
              ],
              'pagination': {'page': 1},
            }),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      final reports = await service.fetchReports(token: 'jwt-token');

      expect(recorder.last.method, 'GET');
      expect(recorder.last.url.path, '/api/reports');
      expect(recorder.last.headers['Authorization'], 'Bearer jwt-token');
      expect(reports, hasLength(2));
      expect(reports[0].category, 'Garbage / Waste');
      expect(reports[0].status, ReportStatus.resolved);
      expect(reports[1].status, ReportStatus.needsMoreInformation);
      expect(reports.every((r) => r.isServerBacked), isTrue);
    });

    test('a missing data list is an invalidResponse failure', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client((_) => _json(200, {'data': 'nope'})),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.fetchReports(token: 't'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.failure,
            'failure',
            ApiFailure.invalidResponse,
          ),
        ),
      );
    });

    test('skips a single malformed entry but keeps the rest', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client(
            (_) => _json(200, {
              'data': [
                {'category': 'ROADS'}, // no id: unreadable
                {
                  'id': 'srv-2',
                  'category': 'WATER',
                  'title': 'Leak',
                  'description': 'A leak.',
                  'address': 'Bazaar',
                  'status': 'SUBMITTED',
                  'createdAt': '2026-01-02T00:00:00.000Z',
                },
              ],
            }),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      final reports = await service.fetchReports(token: 't');

      expect(reports, hasLength(1));
      expect(reports.single.id, 'srv-2');
    });

    test('an empty data list yields no reports', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client((_) => _json(200, {'data': []})),
          baseUrl: 'http://localhost:3000',
        ),
      );

      expect(await service.fetchReports(token: 't'), isEmpty);
    });
  });

  group('contentTypeForExtension', () {
    test('maps photo extensions to image MIME types', () {
      expect(contentTypeForExtension('jpg'), 'image/jpeg');
      expect(contentTypeForExtension('.jpeg'), 'image/jpeg');
      expect(contentTypeForExtension('PNG'), 'image/png');
      expect(contentTypeForExtension('webp'), 'image/webp');
      // An unknown or empty extension stays a safe image default.
      expect(contentTypeForExtension(''), 'image/jpeg');
      expect(contentTypeForExtension('heic'), 'image/jpeg');
    });
  });

  group('HttpReportApiService.uploadReportPhoto', () {
    test('posts raw bytes with the caller-supplied content type', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client(
            (_) => _json(200, {'photoPath': 'reports/abc.jpg'}),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      final path = await service.uploadReportPhoto(
        token: 'jwt-token',
        reportId: 'srv-1',
        bytes: Uint8List.fromList(const [1, 2, 3, 4]),
        contentType: 'image/png',
      );

      expect(recorder.last.method, 'POST');
      expect(recorder.last.url.path, '/api/reports/srv-1/photo');
      expect(recorder.last.headers['Authorization'], 'Bearer jwt-token');
      expect(recorder.last.headers['content-type'], 'image/png');
      expect(recorder.last.bodyBytes, const [1, 2, 3, 4]);
      expect(path, 'reports/abc.jpg');
    });

    test('a response without a stored path yields null', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client((_) => _json(200, {'photoPath': '  '})),
          baseUrl: 'http://localhost:3000',
        ),
      );

      expect(
        await service.uploadReportPhoto(
          token: 't',
          reportId: 'srv-1',
          bytes: Uint8List.fromList(const [1]),
          contentType: 'image/jpeg',
        ),
        isNull,
      );
    });

    test('a rejected upload surfaces as an ApiException', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client((_) => _json(413, {'error': 'Too large'})),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.uploadReportPhoto(
          token: 't',
          reportId: 'srv-1',
          bytes: Uint8List.fromList(const [1]),
          contentType: 'image/jpeg',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('HttpReportApiService.fetchReportPhoto', () {
    test('downloads the bytes from the authenticated endpoint', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client(
            (_) => http.Response.bytes(
              const [9, 8, 7],
              200,
              headers: const {'content-type': 'image/jpeg'},
            ),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      final bytes = await service.fetchReportPhoto(
        token: 'jwt-token',
        reportId: 'srv-2',
      );

      expect(recorder.last.method, 'GET');
      expect(recorder.last.url.path, '/api/reports/srv-2/photo');
      expect(recorder.last.headers['Authorization'], 'Bearer jwt-token');
      expect(bytes, const [9, 8, 7]);
    });

    test('a report with no image becomes null, not an error', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client((_) => _json(404, {'error': 'No image'})),
          baseUrl: 'http://localhost:3000',
        ),
      );

      expect(
        await service.fetchReportPhoto(token: 't', reportId: 'srv-3'),
        isNull,
      );
    });

    test('an authorization failure is rethrown', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client((_) => _json(403, {'error': 'Forbidden'})),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.fetchReportPhoto(token: 't', reportId: 'srv-3'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.failure,
            'failure',
            ApiFailure.forbidden,
          ),
        ),
      );
    });
  });

  group('HttpReportApiService.deleteReport', () {
    test('sends an authenticated DELETE for the report', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client((_) => http.Response('', 204)),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await service.deleteReport(token: 'jwt-token', reportId: 'srv-1');

      expect(recorder.last.method, 'DELETE');
      expect(recorder.last.url.path, '/api/reports/srv-1');
      expect(recorder.last.headers['Authorization'], 'Bearer jwt-token');
    });

    test('a forbidden delete surfaces as an ApiException', () async {
      final recorder = _Recorder();
      final service = HttpReportApiService(
        ApiClient(
          client: recorder.client((_) => _json(403, {'error': 'Forbidden'})),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.deleteReport(token: 't', reportId: 'srv-1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.failure,
            'failure',
            ApiFailure.forbidden,
          ),
        ),
      );
    });
  });
}
