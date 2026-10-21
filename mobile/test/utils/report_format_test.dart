import 'package:civiclens_mobile/models/civic_report.dart';
import 'package:civiclens_mobile/utils/report_format.dart';
import 'package:flutter_test/flutter_test.dart';

CivicReport _reportWith({
  required String label,
  double latitude = 23.7271,
  double longitude = 92.7176,
}) {
  return CivicReport(
    id: 'CL-FMT-1',
    category: 'Water Supply',
    title: 'Leak',
    description: 'Pipe leak',
    locationLabel: label,
    latitude: latitude,
    longitude: longitude,
    createdAt: DateTime(2026, 10, 15),
  );
}

void main() {
  group('looksLikeCoordinates', () {
    test('recognises bare latitude, longitude pairs', () {
      expect(looksLikeCoordinates('12.9716, 77.5946'), isTrue);
      expect(looksLikeCoordinates('-33.8688, 151.2093'), isTrue);
      expect(looksLikeCoordinates('0.000000, 0.000000'), isTrue);
      expect(looksLikeCoordinates('  12.9716 , 77.5946  '), isTrue);
    });

    test('rejects place names and anything else', () {
      expect(looksLikeCoordinates('Kulikawn, Aizawl'), isFalse);
      expect(looksLikeCoordinates('Near the market, Aizawl'), isFalse);
      expect(looksLikeCoordinates('12.9716'), isFalse);
      expect(looksLikeCoordinates(''), isFalse);
      expect(looksLikeCoordinates('Location unavailable'), isFalse);
    });
  });

  group('displayLocationName', () {
    test('shows the name the citizen chose', () {
      expect(
        displayLocationName(_reportWith(label: 'Kulikawn, Aizawl')),
        'Kulikawn, Aizawl',
      );
      expect(
        displayLocationName(_reportWith(label: '  Kulikawn  ')),
        'Kulikawn',
      );
    });

    test('never presents raw coordinates as an address', () {
      expect(
        displayLocationName(_reportWith(label: '12.9716, 77.5946')),
        'Location name not available',
      );
      expect(
        displayLocationName(_reportWith(label: 'Location unavailable')),
        'Location name not available',
      );
      expect(
        displayLocationName(_reportWith(label: '   ')),
        'Location name not available',
      );
    });
  });

  group('displayCoordinates', () {
    test('renders the stored point to six decimal places', () {
      expect(
        displayCoordinates(_reportWith(label: 'Aizawl')),
        '23.727100, 92.717600',
      );
    });

    test('is null when no usable point was ever stored', () {
      expect(
        displayCoordinates(
          _reportWith(label: 'None', latitude: 0, longitude: 0),
        ),
        isNull,
      );
    });
  });
}
