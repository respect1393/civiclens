import 'package:civiclens_mobile/models/civic_report.dart';
import 'package:flutter_test/flutter_test.dart';

CivicReport _base() => CivicReport(
  id: 'CL-1',
  category: 'Other',
  title: 'Title',
  description: 'Description',
  locationLabel: 'Somewhere',
  latitude: 1,
  longitude: 2,
  createdAt: DateTime.utc(2026, 1, 1),
);

void main() {
  group('ReportOrigin defaults', () {
    test('a fresh report is local-only', () {
      final report = _base();
      expect(report.origin, ReportOrigin.local);
      expect(report.serverId, isNull);
      expect(report.serverPhotoPath, isNull);
      expect(report.isServerBacked, isFalse);
    });

    test('copyWith can promote a report to server-backed', () {
      final served = _base().copyWith(
        origin: ReportOrigin.server,
        serverId: 'srv-1',
        serverPhotoPath: 'uploads/srv-1.jpg',
      );
      expect(served.origin, ReportOrigin.server);
      expect(served.serverId, 'srv-1');
      expect(served.serverPhotoPath, 'uploads/srv-1.jpg');
      expect(served.isServerBacked, isTrue);
      // A backend photo reference is never mistaken for a local photo.
      expect(served.hasPhoto, isFalse);
    });
  });

  group('persistence', () {
    test('server metadata survives a JSON round trip', () {
      final served = _base().copyWith(
        origin: ReportOrigin.server,
        serverId: 'srv-1',
        serverPhotoPath: 'uploads/srv-1.jpg',
      );

      final restored = CivicReport.fromJson(served.toJson());

      expect(restored.origin, ReportOrigin.server);
      expect(restored.serverId, 'srv-1');
      expect(restored.serverPhotoPath, 'uploads/srv-1.jpg');
    });

    test('a file written before this field existed stays local', () {
      final json = _base().toJson()
        ..remove('origin')
        ..remove('serverId')
        ..remove('serverPhotoPath');

      final restored = CivicReport.fromJson(json);

      expect(restored.origin, ReportOrigin.local);
      expect(restored.serverId, isNull);
      expect(restored.serverPhotoPath, isNull);
    });

    test('an unrecognised origin falls back to local', () {
      final json = _base().toJson()..['origin'] = 'somewhere-else';
      expect(CivicReport.fromJson(json).origin, ReportOrigin.local);
    });
  });
}
