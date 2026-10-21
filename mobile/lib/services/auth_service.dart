import '../models/auth_session.dart';
import 'api_client.dart';

/// Citizen authentication against the CIVICLENS backend.
///
/// Implementations throw [ApiException] with a message that is always safe to
/// show on a login or registration form. Passwords are sent only to the server
/// and are never stored, logged or placed in an exception message.
abstract class AuthService {
  /// Creates a CITIZEN account and returns the freshly issued session.
  ///
  /// There is no administrator option: the backend hardcodes the CITIZEN role
  /// for public registration.
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
    required String state,
    required String district,
  });

  /// Exchanges credentials for a session.
  Future<AuthSession> login({required String email, required String password});
}

/// [AuthService] over HTTP: `POST /api/auth/register` and `POST /api/auth/login`.
class HttpAuthService implements AuthService {
  HttpAuthService(this._client);

  final ApiClient _client;

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
    required String state,
    required String district,
  }) async {
    try {
      final response = await _client.postJson(
        '/api/auth/register',
        <String, dynamic>{
          'name': name,
          'email': email,
          'password': password,
          'state': state,
          'district': district,
        },
      );
      return _parseSession(response);
    } on ApiException catch (error) {
      throw _translateRegister(error);
    }
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.postJson(
        '/api/auth/login',
        <String, dynamic>{'email': email, 'password': password},
      );
      return _parseSession(response);
    } on ApiException catch (error) {
      if (error.failure == ApiFailure.unauthorized) {
        throw ApiException(
          failure: error.failure,
          statusCode: error.statusCode,
          message: 'Incorrect email or password.',
        );
      }
      rethrow;
    }
  }

  /// Accepts only the documented `{user, token}` shape; anything else becomes
  /// an `invalidResponse` failure instead of a crash.
  static AuthSession _parseSession(Map<String, dynamic> response) {
    try {
      return AuthSession.fromJson(response);
    } on FormatException {
      throw ApiException(
        failure: ApiFailure.invalidResponse,
        message: 'The server sent an unexpected response. Please try again.',
      );
    }
  }

  static ApiException _translateRegister(ApiException error) {
    if (error.failure != ApiFailure.badRequest) return error;

    final server = error.serverMessage?.toLowerCase() ?? '';
    if (server.contains('already registered')) {
      return ApiException(
        failure: error.failure,
        statusCode: error.statusCode,
        serverMessage: error.serverMessage,
        message: 'An account with this email already exists.',
        fieldErrors: <String, String>{
          ...error.fieldErrors,
          'email': 'This email is already registered.',
        },
      );
    }

    if (error.fieldErrors.isNotEmpty) {
      return ApiException(
        failure: error.failure,
        statusCode: error.statusCode,
        serverMessage: error.serverMessage,
        fieldErrors: error.fieldErrors,
        message: 'Please review the highlighted fields.',
      );
    }

    return error;
  }
}
