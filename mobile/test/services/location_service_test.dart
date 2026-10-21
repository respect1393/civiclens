import 'dart:async';

import 'package:civiclens_mobile/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// Scripted stand-in for the geolocator platform, so the production service
/// can be exercised end to end without a GPS radio, a permission dialog or
/// any platform channel.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  LocationPermission checkPermissionResult = LocationPermission.whileInUse;
  LocationPermission requestPermissionResult = LocationPermission.whileInUse;
  LocationAccuracyStatus accuracyStatus = LocationAccuracyStatus.precise;
  bool serviceEnabled = true;

  /// Positions handed out in order; the last one is repeated.
  final List<Position> positions = <Position>[];

  /// When set, [getCurrentPosition] waits for it instead of returning a fix.
  Completer<Position>? pending;

  /// Thrown by [getCurrentPosition] instead of a fix.
  Object? positionError;

  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int positionRequests = 0;
  LocationSettings? lastSettings;

  @override
  Future<LocationPermission> checkPermission() async {
    checkPermissionCalls++;
    return checkPermissionResult;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls++;
    return requestPermissionResult;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async => accuracyStatus;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    positionRequests++;
    lastSettings = locationSettings;

    final error = positionError;
    if (error != null) return Future<Position>.error(error);

    final pending = this.pending;
    if (pending != null) return pending.future;

    if (positions.isEmpty) {
      return Future<Position>.error(const LocationServiceDisabledException());
    }

    return Future<Position>.value(
      positions.length > 1 ? positions.removeAt(0) : positions.first,
    );
  }
}

Position _fix(
  double latitude,
  double longitude, {
  required double accuracy,
  DateTime? timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  late _FakeGeolocatorPlatform platform;
  late GeolocatorPlatform originalPlatform;

  const service = GeolocatorLocationService();

  setUp(() {
    originalPlatform = GeolocatorPlatform.instance;
    platform = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = platform;
  });

  tearDown(() {
    GeolocatorPlatform.instance = originalPlatform;
  });

  group('fix quality', () {
    test('an accurate fix is precise and needs no explanation', () {
      final fix = DeviceLocation(latitude: 1, longitude: 2, accuracy: 12);

      expect(fix.isPrecise(), isTrue);
      expect(fix.issues(), isEmpty);
      expect(accuracyNote(fix), ' (accuracy ±12 m)');
    });

    test('a fix worse than the target is flagged as inaccurate', () {
      final fix = DeviceLocation(latitude: 1, longitude: 2, accuracy: 1500);

      expect(fix.isPrecise(), isFalse);
      expect(fix.issues(), [LocationIssue.inaccurate]);
      expect(
        explainLocationIssues(fix.issues()),
        contains('less accurate than the target'),
      );
      expect(formatMetres(1500), '1,500 m');
      expect(formatMetres(12), '12 m');
    });

    test('a fix without a reported accuracy is never called precise', () {
      final fix = DeviceLocation(latitude: 1, longitude: 2);

      expect(fix.isPrecise(), isFalse);
      expect(fix.issues(), [LocationIssue.unknownAccuracy]);
      expect(accuracyNote(fix), '');
    });

    test('an old fix is flagged as stale', () {
      final fix = DeviceLocation(
        latitude: 1,
        longitude: 2,
        accuracy: 8,
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
      );

      expect(fix.isPrecise(), isFalse);
      expect(fix.issues(), [LocationIssue.stale]);
      expect(explainLocationIssues(fix.issues()), contains('cached'));
    });

    test('approximate-only permission blocks precision even at 25 m', () {
      final fix = DeviceLocation(latitude: 1, longitude: 2, accuracy: 25);

      // The number alone would be precise; the permission is what disqualifies
      // it, because Android deliberately offsets approximate coordinates.
      expect(fix.isPrecise(), isTrue);
      expect(fix.isPrecise(approximatePermission: true), isFalse);
      expect(fix.issues(approximatePermission: true), [
        LocationIssue.approximatePermission,
      ]);
      expect(
        explainLocationIssues(fix.issues(approximatePermission: true)),
        contains('approximate location'),
      );
    });
  });

  group('permission and service failures', () {
    test(
      'disabled location services are reported before anything else',
      () async {
        platform.serviceEnabled = false;

        await expectLater(
          service.getCurrentLocation(),
          throwsA(
            isA<LocationServiceException>().having(
              (error) => error.failure,
              'failure',
              LocationFailure.servicesDisabled,
            ),
          ),
        );
        expect(platform.checkPermissionCalls, 0);
        expect(platform.positionRequests, 0);
      },
    );

    test('a denied permission never produces a position', () async {
      platform.checkPermissionResult = LocationPermission.denied;
      platform.requestPermissionResult = LocationPermission.denied;

      await expectLater(
        service.getCurrentLocation(),
        throwsA(
          isA<LocationServiceException>()
              .having(
                (error) => error.failure,
                'failure',
                LocationFailure.permissionDenied,
              )
              .having(
                (error) => error.message,
                'message',
                contains('choose the problem location manually'),
              ),
        ),
      );
      expect(platform.requestPermissionCalls, 1);
      expect(platform.positionRequests, 0);
    });

    test('permission is never requested when the caller forbids it', () async {
      platform.checkPermissionResult = LocationPermission.denied;

      await expectLater(
        service.getCurrentLocation(requestPermission: false),
        throwsA(
          isA<LocationServiceException>().having(
            (error) => error.failure,
            'failure',
            LocationFailure.permissionDenied,
          ),
        ),
      );
      expect(platform.requestPermissionCalls, 0);
    });

    test('a permanently denied permission points to device settings', () async {
      platform.checkPermissionResult = LocationPermission.deniedForever;

      await expectLater(
        service.getCurrentLocation(),
        throwsA(
          isA<LocationServiceException>()
              .having(
                (error) => error.failure,
                'failure',
                LocationFailure.permissionDeniedForever,
              )
              .having(
                (error) => error.message,
                'message',
                contains('permanently denied'),
              ),
        ),
      );
      expect(platform.positionRequests, 0);
    });

    test('approximate-only permission is detected from the platform', () async {
      platform.accuracyStatus = LocationAccuracyStatus.reduced;
      expect(await service.isApproximateOnly(), isTrue);

      platform.accuracyStatus = LocationAccuracyStatus.precise;
      expect(await service.isApproximateOnly(), isFalse);

      platform.accuracyStatus = LocationAccuracyStatus.unknown;
      expect(await service.isApproximateOnly(), isFalse);

      platform.checkPermissionResult = LocationPermission.denied;
      expect(await service.isApproximateOnly(), isFalse);
    });
  });

  group('reading a position', () {
    test('requests a high-accuracy fix with a time limit', () async {
      platform.positions.add(_fix(23.7, 92.7, accuracy: 9));

      final result = await service.getCurrentLocation(
        timeLimit: const Duration(seconds: 5),
      );

      expect(result.latitude, 23.7);
      expect(result.accuracy, 9);
      expect(platform.positionRequests, 1);
      expect(platform.lastSettings!.accuracy, LocationAccuracy.high);
      expect(platform.lastSettings!.timeLimit, isNotNull);
      // The deadline shrinks by however long the permission checks took.
      expect(
        platform.lastSettings!.timeLimit!.inMilliseconds,
        inInclusiveRange(4500, 5000),
      );
    });

    test('asks again while the fix misses the accuracy target', () async {
      platform.positions
        ..add(_fix(23.7, 92.7, accuracy: 900))
        ..add(_fix(23.7, 92.7, accuracy: 11));

      final result = await service.getCurrentLocation();

      expect(result.accuracy, 11);
      expect(platform.positionRequests, 2);
    });

    test('hands back the best of several inaccurate fixes', () async {
      platform.positions
        ..add(_fix(23.7, 92.7, accuracy: 800))
        ..add(_fix(23.7, 92.7, accuracy: 450))
        ..add(_fix(23.7, 92.7, accuracy: 600));

      final result = await service.getCurrentLocation();

      // Never better than it is: the caller is told 450 m, not "GPS fixed".
      expect(result.accuracy, 450);
      expect(platform.positionRequests, 3);
    });

    test('a stale fix is retried instead of being accepted as fresh', () async {
      final stale = DateTime.now().subtract(const Duration(minutes: 30));

      for (var i = 0; i < 3; i++) {
        platform.positions.add(_fix(23.7, 92.7, accuracy: 6, timestamp: stale));
      }

      final result = await service.getCurrentLocation();

      // The fix is still handed back (it is the best available), but only
      // after every attempt, because it never counted as fresh.
      expect(platform.positionRequests, 3);
      expect(result.timestamp, stale);
      expect(result.isPrecise(), isFalse);
      expect(result.issues(), [LocationIssue.stale]);
    });

    test(
      'approximate-only permission gives up after a single quick read',
      () async {
        platform.accuracyStatus = LocationAccuracyStatus.reduced;
        platform.positions
          ..add(_fix(23.7, 92.7, accuracy: 1500))
          ..add(_fix(23.7, 92.7, accuracy: 12));

        final result = await service.getCurrentLocation();

        expect(platform.positionRequests, 1);
        expect(result.accuracy, 1500);
        expect(await service.isApproximateOnly(), isTrue);
      },
    );

    test('a fix that never arrives is reported as a timeout', () async {
      platform.pending = Completer<Position>();

      await expectLater(
        service.getCurrentLocation(timeLimit: const Duration(milliseconds: 60)),
        throwsA(
          isA<LocationServiceException>()
              .having(
                (error) => error.failure,
                'failure',
                LocationFailure.timeout,
              )
              .having(
                (error) => error.message,
                'message',
                contains('manually on the map'),
              ),
        ),
      );
    });

    test('a platform crash degrades into guidance, not an exception', () async {
      platform.positionError = StateError('native blew up');

      await expectLater(
        service.getCurrentLocation(),
        throwsA(
          isA<LocationServiceException>().having(
            (error) => error.failure,
            'failure',
            LocationFailure.unavailable,
          ),
        ),
      );
    });
  });
}
