import 'dart:async';

import 'package:civiclens_mobile/services/location_service.dart';

/// In-memory [LocationService] double.
///
/// Widget tests cannot reach a GPS radio or the Android permission dialogs, so
/// every permission/service/timeout path is scripted here and the screens are
/// exercised against the messages and state changes they produce.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.deviceLocation,
    this.failure,
    this.granted = false,
    this.approximatePermission = false,
    this.pending,
  });

  /// Position returned on success.
  final DeviceLocation? deviceLocation;

  /// Thrown instead of a position when scripted to fail.
  final LocationServiceException? failure;

  /// Whether the app already holds permission (never prompts either way).
  final bool granted;

  /// Whether the device only shares approximate (coarse) positions.
  final bool approximatePermission;

  /// When set, [getCurrentLocation] waits for this completer before
  /// completing, so tests can observe an in-flight request (and prove that a
  /// second one is never started while it runs).
  final Completer<DeviceLocation>? pending;

  /// Number of [hasGrantedPermission] calls.
  int permissionChecks = 0;

  /// Number of [isApproximateOnly] calls.
  int approximateChecks = 0;

  /// Number of [getCurrentLocation] calls.
  int requestCount = 0;

  /// Whether the most recent [getCurrentLocation] call asked for permission.
  bool? lastRequestedPermission;

  /// Time limits requested by the caller, in call order.
  final List<Duration?> requestedTimeLimits = <Duration?>[];

  /// Scripted results handed out one per [getCurrentLocation] call, in order.
  ///
  /// Each entry is a [DeviceLocation] to return or a
  /// [LocationServiceException] to throw, which lets a test drive a sequence
  /// such as "first reading inaccurate, retry accurate". While it holds
  /// entries it takes precedence over [deviceLocation] and [failure].
  final List<Object> outcomes = <Object>[];

  @override
  Future<bool> hasGrantedPermission() async {
    permissionChecks++;
    return granted;
  }

  @override
  Future<bool> isApproximateOnly() async {
    approximateChecks++;
    return granted && approximatePermission;
  }

  @override
  Future<DeviceLocation> getCurrentLocation({
    bool requestPermission = true,
    Duration? timeLimit,
  }) async {
    requestCount++;
    lastRequestedPermission = requestPermission;
    requestedTimeLimits.add(timeLimit);

    final pending = this.pending;
    if (pending != null) return pending.future;

    final outcomes = this.outcomes;
    if (outcomes.isNotEmpty) {
      final next = outcomes.removeAt(0);
      if (next is DeviceLocation) return next;
      throw next;
    }

    final failure = this.failure;
    if (failure != null) throw failure;

    final deviceLocation = this.deviceLocation;
    if (deviceLocation != null) return deviceLocation;

    throw const LocationServiceException(
      LocationFailure.unavailable,
      'Your location is currently unavailable.',
    );
  }
}
