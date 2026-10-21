import 'dart:convert';

import 'package:civiclens_mobile/services/api_client.dart';
import 'package:civiclens_mobile/services/auth_service.dart';
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

const Map<String, dynamic> _userJson = {
  'id': 'user-1',
  'name': 'Asha Verma',
  'email': 'asha.verma@example.com',
  'state': 'Karnataka',
  'district': 'Bengaluru Urban',
  'role': 'CITIZEN',
};

void main() {
  group('HttpAuthService.register', () {
    test('posts the documented payload and returns the session', () async {
      final recorder = _Recorder();
      final service = HttpAuthService(
        ApiClient(
          client: recorder.client(
            (_) => _json(201, {'user': _userJson, 'token': 'jwt-token'}),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      final session = await service.register(
        name: 'Asha Verma',
        email: 'asha.verma@example.com',
        password: 'sup3rsecret',
        state: 'Karnataka',
        district: 'Bengaluru Urban',
      );

      expect(recorder.last.method, 'POST');
      expect(recorder.last.url.path, '/api/auth/register');
      expect(recorder.lastBody, {
        'name': 'Asha Verma',
        'email': 'asha.verma@example.com',
        'password': 'sup3rsecret',
        'state': 'Karnataka',
        'district': 'Bengaluru Urban',
      });
      // Registration must not claim a role: the backend decides that.
      expect(recorder.lastBody.containsKey('role'), isFalse);
      expect(session.token, 'jwt-token');
      expect(session.user.name, 'Asha Verma');
      expect(session.user.district, 'Bengaluru Urban');
    });

    test('maps "Email already registered" onto the email field', () async {
      final recorder = _Recorder();
      final service = HttpAuthService(
        ApiClient(
          client: recorder.client(
            (_) => _json(400, {'error': 'Email already registered'}),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.register(
          name: 'Asha',
          email: 'taken@example.com',
          password: 'sup3rsecret',
          state: 'Karnataka',
          district: 'Bengaluru Urban',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.failure, 'failure', ApiFailure.badRequest)
              .having((e) => e.message, 'message', contains('already exists'))
              .having((e) => e.fieldErrors['email'], 'email error', isNotEmpty),
        ),
      );
    });

    test('surfaces Zod field errors with safe copy', () async {
      final recorder = _Recorder();
      final service = HttpAuthService(
        ApiClient(
          client: recorder.client(
            (_) => _json(400, {
              'error': 'Invalid registration data',
              'details': {
                'email': {
                  '_errors': ['Invalid email'],
                },
                'district': {
                  '_errors': ['String must contain at least 1 character(s)'],
                },
              },
            }),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.register(
          name: 'Asha',
          email: 'nope',
          password: 'sup3rsecret',
          state: 'Karnataka',
          district: '',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', contains('highlighted'))
              .having((e) => e.fieldErrors['email'], 'email', 'Invalid email')
              .having((e) => e.fieldErrors['district'], 'district', isNotEmpty),
        ),
      );
    });
  });

  group('HttpAuthService.login', () {
    test('posts only email and password', () async {
      final recorder = _Recorder();
      final service = HttpAuthService(
        ApiClient(
          client: recorder.client(
            (_) => _json(200, {'user': _userJson, 'token': 'jwt-token'}),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      final session = await service.login(
        email: 'asha.verma@example.com',
        password: 'sup3rsecret',
      );

      expect(recorder.last.url.path, '/api/auth/login');
      expect(recorder.lastBody, {
        'email': 'asha.verma@example.com',
        'password': 'sup3rsecret',
      });
      expect(session.user.email, 'asha.verma@example.com');
    });

    test('401 becomes a friendly "incorrect credentials" message', () async {
      final recorder = _Recorder();
      final service = HttpAuthService(
        ApiClient(
          client: recorder.client(
            (_) => _json(401, {'error': 'Invalid credentials'}),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.login(email: 'a@b.co', password: 'wrong'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.failure, 'failure', ApiFailure.unauthorized)
              .having(
                (e) => e.message,
                'message',
                'Incorrect email or password.',
              ),
        ),
      );
    });

    test('a successful login never triggers the unauthorized hook', () async {
      final recorder = _Recorder();
      var unauthorizedCalls = 0;
      final client = ApiClient(
        client: recorder.client(
          (_) => _json(200, {'user': _userJson, 'token': 'jwt-token'}),
        ),
        baseUrl: 'http://localhost:3000',
      )..onUnauthorized = () => unauthorizedCalls += 1;

      await HttpAuthService(client)
          .login(email: 'asha.verma@example.com', password: 'sup3rsecret');

      expect(unauthorizedCalls, 0);
    });

    test('a rejected login never clears the session', () async {
      final recorder = _Recorder();
      var unauthorizedCalls = 0;
      final client = ApiClient(
        client: recorder.client(
          (_) => _json(401, {'error': 'Invalid credentials'}),
        ),
        baseUrl: 'http://localhost:3000',
      )..onUnauthorized = () => unauthorizedCalls += 1;

      await expectLater(
        HttpAuthService(client).login(email: 'a@b.co', password: 'wrong'),
        throwsA(isA<ApiException>()),
      );

      // A bad password is not a dead session: the hook must stay silent.
      expect(unauthorizedCalls, 0);
    });
  });

  group('HttpAuthService failure handling', () {
    test('a 401 on a token-bearing request fires onUnauthorized', () async {
      final recorder = _Recorder();
      var unauthorizedCalls = 0;
      final client = ApiClient(
        client: recorder.client((_) => _json(401, {'error': 'Invalid token'})),
        baseUrl: 'http://localhost:3000',
      )..onUnauthorized = () => unauthorizedCalls += 1;

      await expectLater(
        client.getJson('/api/reports', token: 'expired-token'),
        throwsA(isA<ApiException>()),
      );

      expect(unauthorizedCalls, 1);
      expect(recorder.last.headers['Authorization'], 'Bearer expired-token');
    });

    test('a 500 never leaks the server body or the token', () async {
      final recorder = _Recorder();
      final service = HttpAuthService(
        ApiClient(
          client: recorder.client(
            (_) => http.Response(
              'stack trace: secret-token-abc at handler.ts:12',
              500,
              headers: const {'content-type': 'text/plain'},
            ),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.login(email: 'asha.verma@example.com', password: 'sup3rsecret'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            allOf(
              isNot(contains('secret-token-abc')),
              isNot(contains('handler.ts')),
              contains('went wrong'),
            ),
          ),
        ),
      );
    });

    test('a malformed success body is an invalidResponse failure', () async {
      final recorder = _Recorder();
      final service = HttpAuthService(
        ApiClient(
          client: recorder.client((_) => _json(200, {'unexpected': true})),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.login(email: 'asha.verma@example.com', password: 'sup3rsecret'),
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
      final service = HttpAuthService(
        ApiClient(
          client: recorder.client(
            (_) => throw http.ClientException('connection refused'),
          ),
          baseUrl: 'http://localhost:3000',
        ),
      );

      await expectLater(
        service.login(email: 'asha.verma@example.com', password: 'sup3rsecret'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.failure, 'failure', ApiFailure.network)
              .having((e) => e.message, 'message', contains('connection')),
        ),
      );
    });
  });

  group('ApiClient base URL handling', () {
    test('a trailing slash on the base URL never doubles up a path', () async {
      final recorder = _Recorder();
      final client = ApiClient(
        client: recorder.client((_) => _json(200, <String, dynamic>{})),
        baseUrl: 'http://localhost:3000/',
      );

      await client.postJson('/api/auth/login', const {});

      expect(
        recorder.last.url.toString(),
        'http://localhost:3000/api/auth/login',
      );
    });

    test('a relative path without a leading slash is normalised', () async {
      final recorder = _Recorder();
      final client = ApiClient(
        client: recorder.client((_) => _json(200, <String, dynamic>{})),
        baseUrl: 'http://localhost:3000',
      );

      await client.getJson('api/reports');

      expect(recorder.last.url.path, '/api/reports');
    });
  });
}
