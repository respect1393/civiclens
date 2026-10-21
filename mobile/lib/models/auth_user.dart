/// The citizen profile returned by the backend's auth endpoints.
///
/// Server payloads are treated as untrusted input: every field is checked and
/// trimmed before it reaches the UI, and anything malformed raises a
/// [FormatException] instead of producing a half-built object.
///
/// The backend also returns a `role`, which is deliberately **not** stored
/// here. The citizen app performs no client-side authorization — the backend
/// is the only authority for roles and permissions — so a locally persisted
/// role could never grant access to anything.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.state,
    this.district,
  });

  final String id;
  final String name;
  final String email;

  /// Present for every account created through public registration; nullable
  /// because the backend column is nullable and administrators may have none.
  final String? state;
  final String? district;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final id = _requiredText(json['id'], 'id');
    final name = _requiredText(json['name'], 'name');
    final email = _requiredText(json['email'], 'email');

    return AuthUser(
      id: id,
      name: name,
      email: email,
      state: _optionalText(json['state']),
      district: _optionalText(json['district']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'email': email,
    if (state != null) 'state': state,
    if (district != null) 'district': district,
  };

  static String _requiredText(Object? value, String field) {
    final text = value is String ? value.trim() : '';
    if (text.isEmpty) {
      throw FormatException('Session field "$field" is missing.');
    }
    return text;
  }

  static String? _optionalText(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
