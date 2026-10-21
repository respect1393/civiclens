import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_session.dart';

/// Where the saved authentication session lives.
///
/// Implementations must never store passwords — only the bearer token and the
/// profile the UI renders. The stored session is a convenience for restoring
/// the screens the citizen already saw; it is **not** proof of authorization.
/// The backend re-verifies the token on every protected request.
abstract class SessionStore {
  /// Returns the saved session, or null when the citizen is signed out.
  ///
  /// Throws when the stored payload cannot be understood, so the caller can
  /// wipe it rather than trusting corrupted data.
  Future<AuthSession?> read();

  /// Persists [session]. Failures are tolerated by the caller: the session
  /// then simply lasts for the current run of the app.
  Future<void> write(AuthSession session);

  /// Removes the saved session. Clearing an absent session is not an error.
  Future<void> clear();
}

/// Stores the session in the platform keystore / keychain via
/// `flutter_secure_storage`, never in plain `SharedPreferences`.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'civiclens.auth.session';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.trim().isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Stored session is not an object.');
    }
    return AuthSession.fromJson(Map<String, dynamic>.from(decoded));
  }

  @override
  Future<void> write(AuthSession session) => _storage.write(
    key: _key,
    value: jsonEncode(<String, dynamic>{'version': 1, ...session.toJson()}),
  );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
