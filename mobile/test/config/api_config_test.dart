import 'package:civiclens_mobile/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiConfig.resolve', () {
    test('a --dart-define override wins on every platform', () {
      expect(
        ApiConfig.resolve(
          fromDefine: 'http://192.168.1.42:3000',
          isAndroid: true,
        ),
        'http://192.168.1.42:3000',
      );
      expect(
        ApiConfig.resolve(fromDefine: 'http://10.0.0.5:3000', isAndroid: false),
        'http://10.0.0.5:3000',
      );
    });

    test('a trailing slash is trimmed so paths never double up', () {
      expect(
        ApiConfig.resolve(
          fromDefine: 'http://192.168.1.42:3000/',
          isAndroid: true,
        ),
        'http://192.168.1.42:3000',
      );
    });

    test('a blank define falls back to the platform default', () {
      expect(
        ApiConfig.resolve(fromDefine: '   ', isAndroid: true),
        ApiConfig.emulatorBaseUrl,
      );
      expect(
        ApiConfig.resolve(fromDefine: null, isAndroid: false),
        ApiConfig.desktopBaseUrl,
      );
    });

    test('the Android emulator uses the host-loopback alias', () {
      expect(ApiConfig.emulatorBaseUrl, 'http://10.0.2.2:3000');
    });
  });
}
