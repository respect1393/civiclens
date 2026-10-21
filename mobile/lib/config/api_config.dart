import 'dart:io' show Platform;

/// Single source of truth for the CIVICLENS backend base URL.
///
/// No widget or service may hardcode a host: they read [baseUrl] (or accept an
/// injected base URL) so the endpoint can change without touching
/// authentication logic.
///
/// ## Development environments
///
/// | Where the app runs | Base URL |
/// | --- | --- |
/// | Android emulator | `http://10.0.2.2:3000` (the emulator's alias for host loopback) |
/// | Physical Android phone | `http://<LAPTOP_LAN_IP>:3000` via `--dart-define` |
/// | Flutter on the same machine as the backend | `http://127.0.0.1:3000` |
///
/// Override the default for any platform:
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.42:3000
/// ```
///
/// The phone and the laptop must share a network and the laptop firewall must
/// allow port 3000. The backend binds every interface (`app.listen(PORT)`), so
/// no backend change is needed for physical-device development.
///
/// ## Plain HTTP is development only
///
/// Everything above is **plain HTTP and must never ship**. It exists only so
/// the local Express server can be reached while developing. Production must
/// be served over HTTPS with normal TLS verification; this project never
/// relaxes certificate checks. Android therefore permits cleartext only in the
/// debug and profile manifests.
class ApiConfig {
  ApiConfig._();

  /// Set with `--dart-define=API_BASE_URL=...`; empty when not provided.
  static const String defineBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Android emulator alias for the host machine's loopback interface.
  static const String emulatorBaseUrl = 'http://10.0.2.2:3000';

  /// Backend running on the same machine as the Flutter process.
  static const String desktopBaseUrl = 'http://127.0.0.1:3000';

  /// The base URL in effect for this build, without a trailing slash.
  static String get baseUrl =>
      resolve(fromDefine: defineBaseUrl, isAndroid: Platform.isAndroid);

  /// Resolves the base URL from its inputs so tests never touch the platform.
  static String resolve({String? fromDefine, required bool isAndroid}) {
    final override = fromDefine?.trim();
    if (override != null && override.isNotEmpty) {
      return _stripTrailingSlash(override);
    }
    return isAndroid ? emulatorBaseUrl : desktopBaseUrl;
  }

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
