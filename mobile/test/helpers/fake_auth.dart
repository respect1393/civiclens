import 'dart:async';
import 'dart:convert';

import 'package:civiclens_mobile/models/auth_session.dart';
import 'package:civiclens_mobile/models/auth_user.dart';
import 'package:civiclens_mobile/services/auth_service.dart';
import 'package:civiclens_mobile/services/session_store.dart';
import 'package:civiclens_mobile/state/auth_repository.dart';

/// A session-store double with no platform keystores behind it.
///
/// Widget tests run inside the fake-async zone, where a `MethodChannel` call to
/// `flutter_secure_storage` would never complete. This keeps the session in a
/// plain variable and still exercises the real read/write/clear contract.
class FakeSessionStore implements SessionStore {
  FakeSessionStore([this.session]);

  /// The persisted session, or null when the citizen is signed out.
  AuthSession? session;

  int readCount = 0;
  int writeCount = 0;
  int clearCount = 0;

  /// When set, [read] throws so corrupted-storage paths can be tested.
  bool failOnRead = false;

  /// When set, [read] waits on it, so the splash state is observable.
  Completer<void>? gate;

  @override
  Future<AuthSession?> read() async {
    readCount += 1;
    final pending = gate;
    if (pending != null) await pending.future;
    if (failOnRead) {
      throw const FormatException('Simulated corrupted secure storage.');
    }
    return session;
  }

  @override
  Future<void> write(AuthSession newSession) async {
    writeCount += 1;
    session = newSession;
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
    session = null;
  }
}

/// An [AuthService] double that records calls and never touches the network.
class FakeAuthService implements AuthService {
  FakeAuthService({this.onLogin, this.onRegister});

  Future<AuthSession> Function({
    required String email,
    required String password,
  })?
  onLogin;

  Future<AuthSession> Function({
    required String name,
    required String email,
    required String password,
    required String state,
    required String district,
  })?
  onRegister;

  final List<({String email, String password})> loginCalls = [];
  final List<
    ({
      String name,
      String email,
      String password,
      String state,
      String district,
    })
  >
  registerCalls = [];

  /// The canned session handed back by a successful call.
  static AuthSession sessionFor(String email, {String name = 'Asha Verma'}) =>
      AuthSession(
        token: 'test-token-${email.hashCode}',
        user: AuthUser(
          id: 'user-1',
          name: name,
          email: email,
          state: 'Karnataka',
          district: 'Bengaluru Urban',
        ),
      );

  @override
  Future<AuthSession> login({required String email, required String password}) {
    loginCalls.add((email: email, password: password));
    final handler = onLogin;
    if (handler == null) return Future.value(sessionFor(email));
    return handler(email: email, password: password);
  }

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
    required String state,
    required String district,
  }) {
    registerCalls.add((
      name: name,
      email: email,
      password: password,
      state: state,
      district: district,
    ));
    final handler = onRegister;
    if (handler == null) return Future.value(sessionFor(email, name: name));
    return handler(
      name: name,
      email: email,
      password: password,
      state: state,
      district: district,
    );
  }
}

/// Builds an [AuthRepository] backed by the fakes above.
///
/// Pass [seeded] a session to start already signed in; otherwise the
/// repository starts signed out once `AuthGate` restores it.
AuthRepository buildAuthRepository({
  AuthSession? seeded,
  FakeAuthService? service,
  FakeSessionStore? store,
}) => AuthRepository(
  authService: service ?? FakeAuthService(),
  sessionStore: store ?? FakeSessionStore(seeded),
);

/// A syntactically valid JWT whose payload carries [epochSeconds] as `exp`.
///
/// The signature is meaningless: the app never verifies it, it only reads the
/// expiry locally. Real verification happens on the backend.
String jwtExpiringAt(int epochSeconds) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final payload = base64Url.encode(
    utf8.encode(
      '{"id":"user-1","email":"asha.verma@example.com",'
      '"role":"CITIZEN","exp":$epochSeconds}',
    ),
  );
  return '$header.$payload.not-a-real-signature';
}

/// A JWT that expired an hour ago.
String expiredJwt() => jwtExpiringAt(
  DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch ~/
      1000,
);

/// A JWT that stays valid for another hour.
String freshJwt() => jwtExpiringAt(
  DateTime.now().toUtc().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000,
);

/// Wraps [token] in a session carrying the usual profile.
AuthSession sessionWithToken(
  String token, {
  String name = 'Asha Verma',
  String email = 'asha.verma@example.com',
}) => AuthSession(
  token: token,
  user: AuthUser(
    id: 'user-1',
    name: name,
    email: email,
    state: 'Karnataka',
    district: 'Bengaluru Urban',
  ),
);
