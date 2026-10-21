import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../services/auth_service.dart';
import '../services/session_store.dart';

/// What the app should be showing right now.
enum AuthStatus {
  /// A saved session is being read; the splash screen is up.
  checking,

  /// No usable session — show the login screen.
  unauthenticated,

  /// A session exists locally — show the existing application. The backend
  /// still has to accept this token on every protected request.
  authenticated,
}

/// Owns authentication state: session restoration, sign-in, registration and
/// sign-out.
///
/// Deliberately separate from [ReportRepository]: signing out clears only the
/// saved credentials, never locally stored reports, photos or any other app
/// data. Roles are never read from the client — the backend is authoritative.
class AuthRepository extends ChangeNotifier {
  AuthRepository({required this.authService, required this.sessionStore});

  final AuthService authService;
  final SessionStore sessionStore;

  AuthStatus _status = AuthStatus.checking;
  AuthSession? _session;
  bool _busy = false;
  Future<void>? _restore;

  AuthStatus get status => _status;

  /// The signed-in citizen, or null when signed out. Display only.
  AuthUser? get user => _session?.user;

  /// The bearer token for authenticated requests. Never log it.
  String? get token => _session?.token;

  /// True while a sign-in or registration request is in flight, so the UI can
  /// disable its submit button and prevent duplicate submissions.
  bool get isBusy => _busy;

  /// Reads the saved session exactly once and resolves to the initial status.
  ///
  /// Safe to call repeatedly (hot restart, rebuilds): only the first call does
  /// the work, so restoration can never race itself or navigate twice.
  Future<void> restoreSession() => _restore ??= _restoreSession();

  Future<void> _restoreSession() async {
    try {
      final session = await sessionStore.read();

      if (session == null) {
        _setStatus(AuthStatus.unauthenticated);
        return;
      }

      if (_tokenIsUnusable(session.token)) {
        // Expired or unreadable credentials are dropped rather than kept
        // around "just in case". Reports and other local data stay untouched.
        await _clearStoredSession();
        _setStatus(AuthStatus.unauthenticated);
        return;
      }

      _session = session;
      _setStatus(AuthStatus.authenticated);
    } catch (_) {
      // Corrupted or unreadable secure storage: treat as signed out.
      await _clearStoredSession();
      _setStatus(AuthStatus.unauthenticated);
    }
  }

  /// Signs in and adopts the returned session.
  ///
  /// Throws [ApiException] so the login screen can show a useful message.
  Future<void> signIn({required String email, required String password}) =>
      _authenticate(
        () => authService.login(email: email.trim(), password: password),
      );

  /// Creates a CITIZEN account and adopts the returned session.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String state,
    required String district,
  }) => _authenticate(
    () => authService.register(
      name: name.trim(),
      email: email.trim(),
      password: password,
      state: state.trim(),
      district: district.trim(),
    ),
  );

  Future<void> _authenticate(Future<AuthSession> Function() call) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();

    try {
      final session = await call();
      _session = session;
      _setStatus(AuthStatus.authenticated);

      try {
        await sessionStore.write(session);
      } catch (_) {
        // Persistence is best effort: the citizen stays signed in for this run
        // and simply signs in again next launch. The failure is swallowed so a
        // broken keystore can never leak the token into an error message.
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Signs out: clears the saved session and returns to the login screen.
  ///
  /// Never touches local reports, photos or unrelated preferences.
  Future<void> signOut() async {
    _session = null;
    _setStatus(AuthStatus.unauthenticated);
    await _clearStoredSession();
  }

  /// Called by [ApiClient] when the backend rejects a token this app sent.
  ///
  /// The token is dropped locally; the actual verdict stays with the server.
  void handleUnauthorized() {
    if (_status != AuthStatus.authenticated) return;
    _session = null;
    _setStatus(AuthStatus.unauthenticated);
    unawaited(_clearStoredSession());
  }

  Future<void> _clearStoredSession() async {
    try {
      await sessionStore.clear();
    } catch (_) {
      // A keystore that cannot delete still must not block signing out.
    }
  }

  void _setStatus(AuthStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  /// Decides whether a locally stored token is *definitely* unusable.
  ///
  /// There is no `/api/auth/me` endpoint, so the token cannot be verified
  /// against the server at startup without firing an unrelated request. This
  /// is therefore only a negative check: it drops credentials that are
  /// provably dead so a seven-day-old JWT is not offered forever. It never
  /// grants anything — the backend still verifies signature and expiry on
  /// every protected request, and a token this function cannot read is left
  /// for the server to reject with 401.
  static bool _tokenIsUnusable(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      // Not shaped like a JWT: nothing provable, let the server decide.
      return false;
    }

    try {
      final payload = base64Url.decode(base64Url.normalize(parts[1]));
      final decoded = jsonDecode(utf8.decode(payload));

      // A JWT payload is always a JSON object. Anything else is corrupt data.
      if (decoded is! Map<String, dynamic>) return true;

      final rawExp = decoded['exp'];
      final seconds = rawExp is num
          ? rawExp.toInt()
          : int.tryParse('${rawExp ?? ''}');
      if (seconds == null) return false;

      final expiry = DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      );
      return !expiry.isAfter(DateTime.now().toUtc());
    } on FormatException {
      // Unreadable payload inside a JWT-shaped token: corrupt.
      return true;
    } catch (_) {
      return false;
    }
  }
}
