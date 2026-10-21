import 'package:civiclens_mobile/models/civic_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CivicReport serialisation round trip', () {
    final now = DateTime(2026, 10, 15, 10, 30);
    final event = StatusEvent(
      status: ReportStatus.underReview,
      timestamp: now.add(const Duration(hours: 1)),
      note: 'Under review',
    );
    final report = CivicReport(
      id: 'CL-TEST-1',
      category: 'Pothole / Road Damage',
      title: 'Deep pothole',
      description: 'Large pothole near junction',
      photoFileName: 'CL-TEST-1.jpg',
      locationLabel: 'Market Junction',
      landmark: 'Near the community hall',
      latitude: 12.9716,
      longitude: 77.5946,
      createdAt: now,
      status: ReportStatus.underReview,
      adminNotes: 'Demo note',
      statusHistory: [event],
    );

    final json = report.toJson();
    final decoded = CivicReport.fromJson(json);

    expect(decoded.id, report.id);
    expect(decoded.category, report.category);
    expect(decoded.title, report.title);
    expect(decoded.description, report.description);
    expect(decoded.photoFileName, report.photoFileName);
    expect(decoded.locationLabel, report.locationLabel);
    expect(json['landmark'], 'Near the community hall');
    expect(decoded.landmark, report.landmark);
    expect(decoded.latitude, report.latitude);
    expect(decoded.longitude, report.longitude);
    expect(decoded.createdAt, report.createdAt);
    expect(decoded.status, report.status);
    expect(decoded.adminNotes, report.adminNotes);
    expect(decoded.isSample, false);
    expect(decoded.statusHistory.length, 1);
    expect(decoded.statusHistory.first.status, ReportStatus.underReview);
    expect(decoded.statusHistory.first.note, 'Under review');
  });

  test('CivicReport.fromJson throws for missing id', () {
    expect(
      () => CivicReport.fromJson(const {}),
      throwsA(isA<FormatException>()),
    );
  });

  test('CivicReport.fromJson tolerates missing fields', () {
    final decoded = CivicReport.fromJson(const {'id': 'CL-MIN'});

    expect(decoded.id, 'CL-MIN');
    expect(decoded.category, 'Other');
    expect(decoded.title, 'Untitled report');
    expect(decoded.description, '');
    expect(decoded.photoFileName, isNull);
    expect(decoded.locationLabel, 'Location unavailable');
    // Reports saved before the landmark field existed simply have no key.
    expect(decoded.landmark, isNull);
    expect(decoded.landmarkOrNull, isNull);
    expect(decoded.hasCoordinates, isFalse);
    expect(decoded.status, ReportStatus.reported);
    expect(decoded.isSample, false);
    expect(decoded.adminNotes, isNull);
    expect(decoded.statusHistory, isEmpty);
  });

  test('ReportStatus.fromName returns reported for unknown', () {
    expect(ReportStatus.fromName(null), ReportStatus.reported);
    expect(ReportStatus.fromName('unknown'), ReportStatus.reported);
  });

  test('ReportStatus.fromName accepts label and name', () {
    expect(ReportStatus.fromName('Under Review'), ReportStatus.underReview);
    expect(ReportStatus.fromName('inProgress'), ReportStatus.inProgress);
  });

  test('CivicReport.copyWith updates values and clears flags', () {
    final report = CivicReport(
      id: 'CL-1',
      category: 'Water Supply',
      title: 'Leak',
      description: 'Leak',
      photoFileName: 'CL-1.jpg',
      locationLabel: 'Road',
      latitude: 1,
      longitude: 2,
      createdAt: DateTime(2026),
    );

    final updated = report.copyWith(
      title: 'Major leak',
      clearPhoto: true,
      adminNotes: 'Note',
    );

    expect(updated.title, 'Major leak');
    expect(updated.photoFileName, isNull);
    expect(updated.adminNotes, 'Note');

    final cleared = updated.copyWith(clearAdminNotes: true);
    expect(cleared.adminNotes, isNull);
  });

  test('landmark is optional, trimmed and never stored blank', () {
    final report = CivicReport(
      id: 'CL-LM-1',
      category: 'Water Supply',
      title: 'Leak',
      description: 'Leak',
      locationLabel: 'Kulikawn, Aizawl',
      landmark: '  Near the community hall  ',
      latitude: 12.9716,
      longitude: 77.5946,
      createdAt: DateTime(2026),
    );

    expect(report.landmarkOrNull, 'Near the community hall');
    expect(report.hasCoordinates, isTrue);

    final decoded = CivicReport.fromJson(report.toJson());
    expect(decoded.landmark, 'Near the community hall');

    final cleared = report.copyWith(clearLandmark: true);
    expect(cleared.landmark, isNull);
    expect(cleared.landmarkOrNull, isNull);
    // Clearing the landmark leaves the rest of the report untouched.
    expect(cleared.locationLabel, report.locationLabel);
    expect(cleared.latitude, report.latitude);

    final blank = report.copyWith(landmark: '   ');
    expect(blank.landmarkOrNull, isNull);
    expect(CivicReport.fromJson(blank.toJson()).landmark, isNull);
  });

  test('hasCoordinates rejects unusable points', () {
    CivicReport reportAt({
      required double latitude,
      required double longitude,
    }) {
      return CivicReport(
        id: 'CL-GPS-1',
        category: 'Other',
        title: 'Point',
        description: 'Point',
        locationLabel: 'Nowhere',
        latitude: latitude,
        longitude: longitude,
        createdAt: DateTime(2026),
      );
    }

    // A neutral (0, 0) point means "no location was ever stored".
    expect(reportAt(latitude: 0, longitude: 0).hasCoordinates, isFalse);
    // Out of range values cannot come from the map or the GPS.
    expect(reportAt(latitude: 95, longitude: 10).hasCoordinates, isFalse);
    expect(reportAt(latitude: 10, longitude: 200).hasCoordinates, isFalse);
    // A real point is accepted.
    expect(reportAt(latitude: -33.86, longitude: 151.2).hasCoordinates, isTrue);
  });
}
