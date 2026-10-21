import 'auth_user.dart';

/// A successful authentication result: the bearer token plus the profile the
/// UI needs.
///
/// The token is a bearer credential. It is never logged, never placed in a
/// message shown to the citizen, and never persisted anywhere except through
/// a [SessionStore] (secure storage on device).
class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    if (token is! String || token.trim().isEmpty) {
      throw const FormatException('Session is missing its token.');
    }

    final user = json['user'];
    if (user is! Map) {
      throw const FormatException('Session is missing its user.');
    }

    return AuthSession(
      token: token.trim(),
      user: AuthUser.fromJson(Map<String, dynamic>.from(user)),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'token': token,
    'user': user.toJson(),
  };
}
