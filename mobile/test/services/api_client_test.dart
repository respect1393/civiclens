import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:civiclens_mobile/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records the requests the client makes.
class _Recorder {
  final List<http.Request> requests = [];

  http.Request get last => requests.last;
}

ApiClient _client(_Recorder recorder, http.Response Function(http.Request) h) {
  final client = ApiClient(
    client: MockClient((request) async {
      recorder.requests.add(request);
      return h(request);
    }),
    baseUrl: 'http://localhost:3000',
  );
  return client;
}

void main() {
  group('postBytes', () {
    test('sends the raw bytes, content type and bearer token', () async {
      final recorder = _Recorder();
      final client = _client(
        recorder,
        (_) => http.Response(
          jsonEncode({'photoPath': 'reports/abc.jpg'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final response = await client.postBytes(
        '/api/reports/srv-1/photo',
        Uint8List.fromList(const [1, 2, 3, 4]),
        contentType: 'image/png',
        token: 'jwt-token',
      );

      expect(recorder.last.method, 'POST');
      expect(recorder.last.url.path, '/api/reports/srv-1/photo');
      expect(recorder.last.headers['Content-Type'], 'image/png');
      expect(recorder.last.headers['Authorization'], 'Bearer jwt-token');
      expect(recorder.last.bodyBytes, const [1, 2, 3, 4]);
      expect(response['photoPath'], 'reports/abc.jpg');
    });

    test('omits the bearer token when none is supplied', () async {
      final recorder = _Recorder();
      final client = _client(recorder, (_) => http.Response('{}', 200));

      await client.postBytes(
        '/api/reports/srv-1/photo',
        Uint8List.fromList(const [1]),
        contentType: 'image/jpeg',
      );

      expect(recorder.last.headers.containsKey('Authorization'), isFalse);
    });

    test('maps a rejected upload to a badRequest failure', () async {
      final recorder = _Recorder();
      final client = _client(
        recorder,
        (_) => http.Response(
          jsonEncode({'error': 'Unsupported image format'}),
          400,
        ),
      );

      await expectLater(
        client.postBytes(
          '/api/reports/srv-1/photo',
          Uint8List.fromList(const [1]),
          contentType: 'image/jpeg',
          token: 't',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.failure, 'failure', ApiFailure.badRequest)
              .having(
                (e) => e.serverMessage,
                'serverMessage',
                'Unsupported image format',
              ),
        ),
      );
    });

    test('a socket failure becomes a network failure', () async {
      final client = ApiClient(
        client: MockClient(
          (_) async => throw http.ClientException('connection refused'),
        ),
        baseUrl: 'http://localhost:3000',
      );

      await expectLater(
        client.postBytes(
          '/api/reports/srv-1/photo',
          Uint8List.fromList(const [1]),
          contentType: 'image/jpeg',
          token: 't',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.failure,
            'failure',
            ApiFailure.network,
          ),
        ),
      );
    });
  });

  group('getBytes', () {
    test('returns the raw response body for a success', () async {
      final recorder = _Recorder();
      final client = _client(
        recorder,
        (_) => http.Response.bytes(
          const [9, 8, 7],
          200,
          headers: {'content-type': 'image/jpeg'},
        ),
      );

      final bytes = await client.getBytes(
        '/api/reports/srv-2/photo',
        token: 'jwt-token',
      );

      expect(recorder.last.method, 'GET');
      expect(recorder.last.url.path, '/api/reports/srv-2/photo');
      expect(recorder.last.headers['Authorization'], 'Bearer jwt-token');
      expect(bytes, const [9, 8, 7]);
    });

    test('a 404 becomes a notFound failure so callers can opt out', () async {
      final recorder = _Recorder();
      final client = _client(recorder, (_) => http.Response('', 404));

      await expectLater(
        client.getBytes('/api/reports/srv-2/photo', token: 't'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.failure,
            'failure',
            ApiFailure.notFound,
          ),
        ),
      );
    });

    test('a 401 on a token-bearing request fires onUnauthorized', () async {
      final recorder = _Recorder();
      var calls = 0;
      final client = ApiClient(
        client: MockClient((request) async {
          recorder.requests.add(request);
          return http.Response('', 401);
        }),
        baseUrl: 'http://localhost:3000',
      )..onUnauthorized = () => calls += 1;

      await expectLater(
        client.getBytes('/api/reports/srv-2/photo', token: 'expired'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
    });

    test('a 401 without a token does not fire onUnauthorized', () async {
      final recorder = _Recorder();
      var calls = 0;
      final client = ApiClient(
        client: MockClient((request) async {
          recorder.requests.add(request);
          return http.Response('', 401);
        }),
        baseUrl: 'http://localhost:3000',
      )..onUnauthorized = () => calls += 1;

      await expectLater(
        client.getBytes('/api/reports/srv-2/photo'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 0);
    });

    test('a hung request times out', () async {
      final gate = Completer<http.Response>();
      final client = ApiClient(
        client: MockClient((_) => gate.future),
        baseUrl: 'http://localhost:3000',
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        client.getBytes('/api/reports/srv-2/photo', token: 't'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.failure,
            'failure',
            ApiFailure.timeout,
          ),
        ),
      );

      gate.complete(http.Response('', 200));
    });
  });

  group('deleteJson', () {
    test('sends an authenticated DELETE and accepts an empty 204', () async {
      final recorder = _Recorder();
      final client = _client(recorder, (_) => http.Response('', 204));

      final body = await client.deleteJson(
        '/api/reports/srv-1',
        token: 'jwt-token',
      );

      expect(recorder.last.method, 'DELETE');
      expect(recorder.last.url.path, '/api/reports/srv-1');
      expect(recorder.last.headers['Authorization'], 'Bearer jwt-token');
      expect(body, isEmpty);
    });

    test('a 403 becomes a forbidden failure', () async {
      final recorder = _Recorder();
      final client = _client(recorder, (_) => http.Response('', 403));

      await expectLater(
        client.deleteJson('/api/reports/srv-1', token: 't'),
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
