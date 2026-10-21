import 'dart:async';

import 'package:geolocator/geolocator.dart';

// --------------------------------------------------
// ACCURACY POLICY
//
// High-accuracy mode is a request to the device, never a guarantee. These
// values decide when a reading may be presented as a precise GPS fix and
// when the citizen must instead be told that the fix is worse than that.
// --------------------------------------------------

/// Horizontal accuracy, in metres, that a fix must meet (or beat) before it
/// may be presented as "your current location" without asking.
///
/// 50 m is a realistic target for a phone with a clear view of the sky. It
/// is a target, not a promise: when the device or the environment cannot do
/// better, the citizen is shown the reported accuracy instead.
const double preciseLocationThresholdMetres = 50;

/// A fix older than this is treated as a possibly stale (cached) reading
/// instead of a fresh GPS result.
const Duration maxFreshFixAge = Duration(minutes: 2);

/// Overall budget for an explicit "use my current location" request: long
/// enough for a cold GPS receiver to obtain a real fix.
const Duration defaultLocationTimeLimit = Duration(seconds: 30);

/// Budget for the opportunistic "centre on me" read that runs without any
/// user interaction, so it can never hold the radio while the citizen works.
const Duration backgroundLocationTimeLimit = Duration(seconds: 10);

/// How many fresh readings are requested before the best imperfect fix is
/// handed back as the best available result.
const int defaultLocationAttemptLimit = 3;

/// A device position in degrees, with everything the platform reported
/// about how good it is.
///
/// Deliberately independent of the geolocator package so screens can be
/// tested with a fake that never touches platform channels.
class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.timestamp,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in metres, exactly as the platform reported it
  /// (the radius within which the true position lies with ~68% confidence).
  ///
  /// Null when the platform did not report a value. It is never rounded up
  /// or invented: a coarse reading stays coarse.
  final double? accuracy;

  /// When the platform produced this fix, when it said so. Null when the
  /// platform did not report a timestamp.
  final DateTime? timestamp;

  /// Why this reading cannot be presented as a precise GPS fix.
  ///
  /// An empty list means the fix met the accuracy target, was fresh and was
  /// not produced under approximate-only permission.
  List<LocationIssue> issues({
    bool approximatePermission = false,
    double thresholdMetres = preciseLocationThresholdMetres,
    Duration maxAge = maxFreshFixAge,
    DateTime? now,
  }) {
    final found = <LocationIssue>[];

    if (approximatePermission) {
      found.add(LocationIssue.approximatePermission);
    }

    final value = accuracy;
    if (value == null || !value.isFinite) {
      found.add(LocationIssue.unknownAccuracy);
    } else if (value > thresholdMetres) {
      found.add(LocationIssue.inaccurate);
    }

    final stamp = timestamp;
    if (stamp != null) {
      final reference = now ?? DateTime.now();
      if (stamp.isBefore(reference.subtract(maxAge))) {
        found.add(LocationIssue.stale);
      }
    }

    return found;
  }

  /// Convenience wrapper around [issues]: true only for a fix that is
  /// accurate enough, fresh and not approximate-only.
  bool isPrecise({
    bool approximatePermission = false,
    double thresholdMetres = preciseLocationThresholdMetres,
    Duration maxAge = maxFreshFixAge,
    DateTime? now,
  }) {
    return issues(
      approximatePermission: approximatePermission,
      thresholdMetres: thresholdMetres,
      maxAge: maxAge,
      now: now,
    ).isEmpty;
  }
}

/// A quality problem that stops a reading from being shown as precise.
enum LocationIssue {
  /// The device only shares approximate (coarse) coordinates.
  approximatePermission,

  /// The reported accuracy is worse than [preciseLocationThresholdMetres].
  inaccurate,

  /// The fix is older than [maxFreshFixAge], so it may be cached.
  stale,

  /// The platform reported no accuracy value at all.
  unknownAccuracy,
}

/// Citizen-facing sentences explaining why [issues] stop a reading from
/// being presented as a precise GPS fix.
///
/// [LocationIssue.unknownAccuracy] is intentionally not rendered here: the
/// caller always states the reported accuracy next to this text, which
/// covers both "no value" and "value too large".
String explainLocationIssues(List<LocationIssue> issues) {
  final sentences = <String>[];

  if (issues.contains(LocationIssue.approximatePermission)) {
    sentences.add(
      'Your device is only sharing an approximate location, which can be '
      'off by 1–2 km. Turn on precise location in your device settings for '
      'a better fix.',
    );
  }

  if (issues.contains(LocationIssue.inaccurate)) {
    sentences.add(
      'This position is less accurate than the target of about '
      '±${formatMetres(preciseLocationThresholdMetres)}.',
    );
  }

  if (issues.contains(LocationIssue.stale)) {
    sentences.add(
      'Your device returned an old, cached position instead of a fresh one.',
    );
  }

  return sentences.join(' ');
}

/// Formats a distance in metres for display, e.g. `12 m`, `1,500 m`.
///
/// Values are rounded, never inflated or smoothed: what the device reports
/// is what the citizen is told.
String formatMetres(double metres) {
  final rounded = metres.round();
  final digits = rounded.abs().toString();

  if (digits.length <= 3) return '$rounded m';

  final buffer = StringBuffer();
  final leading = digits.length % 3 == 0 ? 3 : digits.length % 3;

  buffer.write(digits.substring(0, leading));
  for (var i = leading; i < digits.length; i += 3) {
    buffer.write(',');
    buffer.write(digits.substring(i, i + 3));
  }

  return '${rounded.isNegative ? '-' : ''}$buffer m';
}

/// Sentence fragment stating the reported accuracy, e.g. ` (accuracy ±12 m)`.
///
/// Empty when the platform reported no accuracy: nothing is ever invented
/// for the citizen to read.
String accuracyNote(DeviceLocation location) {
  final accuracy = location.accuracy;
  if (accuracy == null || !accuracy.isFinite) return '';
  return ' (accuracy ±${formatMetres(accuracy)})';
}

/// Why a device-location request could not produce a position.
enum LocationFailure {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  timeout,
  unavailable,
}

/// Thrown by [LocationService] when no position can be produced.
///
/// Always carries a message that is safe to show to the citizen.
class LocationServiceException implements Exception {
  const LocationServiceException(this.failure, this.message);

  final LocationFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// Reads the device position, translating every platform failure into a
/// [LocationServiceException] with a user-facing message.
///
/// The manual map picker never requires this service to succeed: coordinates
/// can always be chosen by hand, so every message points the user back to it.
abstract class LocationService {
  /// True when the app already holds location permission.
  ///
  /// Checking this must never trigger the system permission prompt, which is
  /// what keeps manual map selection usable without any location permission.
  Future<bool> hasGrantedPermission();

  /// True when permission only allows approximate (coarse) positions.
  ///
  /// On Android 12+ the citizen can grant "approximate location only" while
  /// the permission still reads as granted; the platform then deliberately
  /// offsets the coordinates by up to a couple of kilometres. Reading this
  /// never triggers the system permission prompt.
  Future<bool> isApproximateOnly();

  /// Returns the current device position.
  ///
  /// Set [requestPermission] to false to guarantee that the system permission
  /// prompt is never shown (used for opportunistic "centre on me" behaviour).
  ///
  /// [timeLimit] overrides the overall budget for the request. Within it the
  /// position is requested fresh, with high accuracy, and re-requested while
  /// the fix misses the accuracy target. The best fix obtained is returned
  /// even when it is imperfect, so callers can tell the citizen exactly how
  /// accurate it is instead of silently accepting it.
  Future<DeviceLocation> getCurrentLocation({
    bool requestPermission = true,
    Duration? timeLimit,
  });
}

/// Production implementation backed by the geolocator plugin.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService({
    this.targetAccuracyMetres = preciseLocationThresholdMetres,
    this.attemptLimit = defaultLocationAttemptLimit,
  });

  /// Accuracy the device should reach before a fix is treated as precise.
  final double targetAccuracyMetres;

  /// How many fresh readings are requested before giving the best one back.
  final int attemptLimit;

  static const String _unavailableMessage =
      'Your location is currently unavailable. You can still choose the '
      'problem location manually on the map.';

  @override
  Future<bool> hasGrantedPermission() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isApproximateOnly() async {
    try {
      if (!await hasGrantedPermission()) return false;
      final status = await Geolocator.getLocationAccuracy();
      return status == LocationAccuracyStatus.reduced;
    } catch (_) {
      // Platforms that cannot answer are never reported as approximate:
      // the reported accuracy of each fix still guards the result.
      return false;
    }
  }

  @override
  Future<DeviceLocation> getCurrentLocation({
    bool requestPermission = true,
    Duration? timeLimit,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw const LocationServiceException(
        LocationFailure.servicesDisabled,
        'Location services are disabled. Enable them, or choose the problem '
        'location manually on the map.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.denied:
        throw const LocationServiceException(
          LocationFailure.permissionDenied,
          'Location permission was denied. You can still choose the problem '
          'location manually on the map.',
        );
      case LocationPermission.deniedForever:
        throw const LocationServiceException(
          LocationFailure.permissionDeniedForever,
          'Location permission is permanently denied. Enable it in your '
          'device settings, or choose the problem location manually on the '
          'map.',
        );
      case LocationPermission.unableToDetermine:
        throw const LocationServiceException(
          LocationFailure.unavailable,
          _unavailableMessage,
        );
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        break;
    }

    final approximateOnly = await isApproximateOnly();

    // Approximate-only permission can never reach the target, so one quick
    // reading is all that is worth waiting for. Otherwise the device gets
    // the full budget to converge on a precise fix.
    final budget =
        timeLimit ??
        (approximateOnly
            ? const Duration(seconds: 12)
            : defaultLocationTimeLimit);
    final deadline = DateTime.now().add(budget);
    final maxAttempts = approximateOnly ? 1 : attemptLimit;

    DeviceLocation? best;
    var timedOut = false;
    var sawPlatformError = false;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final remaining = deadline.difference(DateTime.now());

      if (remaining <= Duration.zero) {
        timedOut = true;
        break;
      }

      final Position position;
      try {
        // Requested fresh every time: a new reading starts new location
        // updates instead of trusting whatever was cached last.
        position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: remaining,
          ),
        ).timeout(remaining);
      } on TimeoutException {
        timedOut = true;
        break;
      } on PermissionDeniedException {
        throw const LocationServiceException(
          LocationFailure.permissionDenied,
          'Location permission was denied. You can still choose the problem '
          'location manually on the map.',
        );
      } on LocationServiceDisabledException {
        throw const LocationServiceException(
          LocationFailure.servicesDisabled,
          'Location services are disabled. Enable them, or choose the '
          'problem location manually on the map.',
        );
      } catch (_) {
        // Includes the Android "No location permissions are defined in the
        // manifest" PlatformException, which the manifest fix prevents but
        // which must still degrade into guidance instead of a crash.
        sawPlatformError = true;
        break;
      }

      final candidate = DeviceLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy.isFinite ? position.accuracy : null,
        timestamp: position.timestamp,
      );

      if (best == null || _isBetter(candidate, best)) {
        best = candidate;
      }

      if (_meetsTarget(candidate)) {
        return candidate;
      }
    }

    // An imperfect but real fix is handed back as it is: the caller shows
    // the reported accuracy and lets the citizen decide, rather than the
    // app pretending the reading was precise.
    if (best != null) return best;

    if (!sawPlatformError && timedOut) {
      throw const LocationServiceException(
        LocationFailure.timeout,
        'Could not get your location in time. You can still choose the '
        'problem location manually on the map.',
      );
    }

    throw const LocationServiceException(
      LocationFailure.unavailable,
      _unavailableMessage,
    );
  }

  /// True when [candidate] is worth keeping over [current].
  bool _isBetter(DeviceLocation candidate, DeviceLocation current) {
    final candidateAccuracy = candidate.accuracy;
    final currentAccuracy = current.accuracy;

    if (candidateAccuracy == null) return false;
    if (currentAccuracy == null) return true;
    return candidateAccuracy < currentAccuracy;
  }

  bool _meetsTarget(DeviceLocation candidate) {
    final accuracy = candidate.accuracy;
    if (accuracy == null || !accuracy.isFinite) return false;
    if (accuracy > targetAccuracyMetres) return false;

    final stamp = candidate.timestamp;
    if (stamp == null) return true;
    return !stamp.isBefore(DateTime.now().subtract(maxFreshFixAge));
  }
}
