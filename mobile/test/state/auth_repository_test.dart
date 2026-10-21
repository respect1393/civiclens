import 'package:civiclens_mobile/services/api_client.dart';
import 'package:civiclens_mobile/state/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth.dart';

Future<AuthRepository> restored({
  required FakeSessionStore store,
  FakeAuthService? service,
}) async {
  final repository = buildAuthRepository(service: service, store: store);
  await repository.restoreSession();
  return repository;
}

void main() {
  group('restoreSession', () {
    test('starts in the checking state', () {
      final repository = buildAuthRepository();
      expect(repository.status, AuthStatus.checking);
      expect(repository.user, isNull);
      expect(repository.token, isNull);
    });

    test('no saved session means signed out, and nothing is deleted', () async {
      final store = FakeSessionStore();
      final repository = await restored(store: store);

      expect(repository.status, AuthStatus.unauthenticated);
      expect(repository.user, isNull);
      expect(store.clearCount, 0);
    });

    test('a usable saved session restores the citizen', () async {
      final store = FakeSessionStore(sessionWithToken(freshJwt()));
      final repository = await restored(store: store);

      expect(repository.status, AuthStatus.authenticated);
      expect(repository.user?.email, 'asha.verma@example.com');
      expect(repository.token, freshJwt());
    });

    test('an expired token is dropped instead of offered forever', () async {
      final store = FakeSessionStore(sessionWithToken(expiredJwt()));
      final repository = await restored(store: store);

      expect(repository.status, AuthStatus.unauthenticated);
      expect(store.clearCount, 1);
      expect(store.session, isNull);
    });

    test(
      'a token that is not JWT-shaped is left for the server to judge',
      () async {
        final store = FakeSessionStore(sessionWithToken('opaque-token'));
        final repository = await restored(store: store);

        expect(repository.status, AuthStatus.authenticated);
        expect(store.clearCount, 0);
      },
    );

    test('corrupted storage signs the citizen out without crashing', () async {
      final store = FakeSessionStore()..failOnRead = true;
      final repository = await restored(store: store);

      expect(repository.status, AuthStatus.unauthenticated);
      expect(store.clearCount, 1);
    });

    test('is idempotent so rebuilds cannot double-restore', () async {
      final store = FakeSessionStore(sessionWithToken(freshJwt()));
      final repository = buildAuthRepository(store: store);

      await Future.wait([
        repository.restoreSession(),
        repository.restoreSession(),
      ]);
      await repository.restoreSession();

      expect(store.readCount, 1);
    });
  });

  group('signIn', () {
    test('adopts and persists the returned session', () async {
      final store = FakeSessionStore();
      final repository = await restored(store: store);

      await repository.signIn(
        email: '  asha.verma@example.com ',
        password: 'sup3rsecret',
      );

      expect(repository.status, AuthStatus.authenticated);
      expect(repository.user?.email, 'asha.verma@example.com');
      expect(store.writeCount, 1);
      expect(store.session?.token, isNotNull);
      // The password is never persisted with the session.
      expect(
        store.session?.toJson().toString(),
        isNot(contains('sup3rsecret')),
      );
    });

    test('trims the email before sending it', () async {
      final service = FakeAuthService();
      final repository = await restored(
        store: FakeSessionStore(),
        service: service,
      );

      await repository.signIn(email: ' a@b.co ', password: 'pw');

      expect(service.loginCalls.single.email, 'a@b.co');
    });

    test('a failure leaves the citizen signed out and rethrows', () async {
      final service = FakeAuthService(
        onLogin: ({required email, required password}) => Future.error(
          ApiException(
            failure: ApiFailure.unauthorized,
            message: 'Incorrect email or password.',
            statusCode: 401,
          ),
        ),
      );
      final repository = await restored(
        store: FakeSessionStore(),
        service: service,
      );

      await expectLater(
        repository.signIn(email: 'a@b.co', password: 'wrong'),
        throwsA(isA<ApiException>()),
      );

      expect(repository.status, AuthStatus.unauthenticated);
      expect(repository.isBusy, isFalse);
    });

    test('a broken keystore still lets the citizen in', () async {
      final store = _FailingWriteStore();
      final repository = await restored(store: store);

      await repository.signIn(email: 'a@b.co', password: 'pw');

      expect(repository.status, AuthStatus.authenticated);
      expect(store.writeCount, 1);
    });

    test('re-entrant submissions are ignored, not queued', () async {
      final service = FakeAuthService();
      final repository = await restored(
        store: FakeSessionStore(),
        service: service,
      );

      final first = repository.signIn(email: 'a@b.co', password: 'pw');
      final second = repository.signIn(email: 'a@b.co', password: 'pw');
      await Future.wait([first, second]);

      expect(service.loginCalls, hasLength(1));
    });
  });

  group('register', () {
    test('sends trimmed values and adopts the session', () async {
      final service = FakeAuthService();
      final store = FakeSessionStore();
      final repository = await restored(store: store, service: service);

      await repository.register(
        name: '  Asha Verma ',
        email: ' asha@example.com ',
        password: 'sup3rsecret',
        state: ' Karnataka ',
        district: ' Bengaluru Urban ',
      );

      final call = service.registerCalls.single;
      expect(call.name, 'Asha Verma');
      expect(call.email, 'asha@example.com');
      expect(call.state, 'Karnataka');
      expect(call.district, 'Bengaluru Urban');
      expect(repository.status, AuthStatus.authenticated);
      expect(store.writeCount, 1);
    });

    test('a rejected registration keeps the citizen signed out', () async {
      final service = FakeAuthService(
        onRegister:
            ({
              required name,
              required email,
              required password,
              required state,
              required district,
            }) => Future.error(
              ApiException(
                failure: ApiFailure.badRequest,
                message: 'An account with this email already exists.',
                statusCode: 400,
                fieldErrors: const {
                  'email': 'This email is already registered.',
                },
              ),
            ),
      );
      final repository = await restored(
        store: FakeSessionStore(),
        service: service,
      );

      await expectLater(
        repository.register(
          name: 'Asha',
          email: 'taken@example.com',
          password: 'sup3rsecret',
          state: 'Karnataka',
          district: 'Bengaluru Urban',
        ),
        throwsA(isA<ApiException>()),
      );

      expect(repository.status, AuthStatus.unauthenticated);
      expect(repository.isBusy, isFalse);
    });
  });

  group('signOut', () {
    test('clears the session without touching stored data', () async {
      final store = FakeSessionStore(sessionWithToken(freshJwt()));
      final repository = await restored(store: store);
      expect(repository.status, AuthStatus.authenticated);

      await repository.signOut();

      expect(repository.status, AuthStatus.unauthenticated);
      expect(repository.user, isNull);
      expect(store.session, isNull);
      expect(store.clearCount, 1);
    });
  });

  group('handleUnauthorized', () {
    test(
      'drops an active session when the backend rejects its token',
      () async {
        final store = FakeSessionStore(sessionWithToken(freshJwt()));
        final repository = await restored(store: store);

        repository.handleUnauthorized();
        await Future<void>.delayed(Duration.zero);

        expect(repository.status, AuthStatus.unauthenticated);
        expect(store.clearCount, 1);
      },
    );

    test('does nothing when already signed out', () async {
      final store = FakeSessionStore();
      final repository = await restored(store: store);

      repository.handleUnauthorized();
      await Future<void>.delayed(Duration.zero);

      expect(store.clearCount, 0);
    });
  });
}

/// A store whose writes always fail, standing in for a broken keystore.
class _FailingWriteStore extends FakeSessionStore {
  @override
  Future<void> write(_) async {
    writeCount += 1;
    throw const FormatException('Simulated keystore failure.');
  }
}
