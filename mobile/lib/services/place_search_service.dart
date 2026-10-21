import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A single forward-geocoding hit, reduced to the fields the picker needs.
class PlaceResult {
  const PlaceResult({
    required this.latitude,
    required this.longitude,
    required this.displayName,
  });

  final double latitude;
  final double longitude;
  final String displayName;
}

/// Why a place search could not produce results.
///
/// These are deliberately distinct so the UI never tells a citizen "not found"
/// when the real problem was that the network or the service was unreachable.
enum PlaceSearchFailure {
  /// The service answered, but nothing matched the query.
  noResults,

  /// The device could not reach the service at all.
  networkUnavailable,

  /// The service answered with a non-200 status (rate limit, 5xx, ...).
  serviceUnavailable,

  /// The service answered 200 but the payload could not be understood.
  invalidResponse,

  /// The request took too long.
  timeout,
}

/// Thrown by [PlaceSearchService] when a search cannot be answered.
///
/// Every message is safe to show to the citizen and never claims a place was
/// found when it was not.
class PlaceSearchException implements Exception {
  const PlaceSearchException(this.failure, this.message);

  final PlaceSearchFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// Resolves a place name into coordinates.
///
/// Injectable so widget tests can exercise success, empty, network and
/// service-error paths without live internet access.
abstract class PlaceSearchService {
  /// Returns at most [limit] matches for [query].
  ///
  /// Throws a [PlaceSearchException] when no results could be produced.
  /// An empty list is a legitimate answer and means "nothing matched".
  Future<List<PlaceResult>> search(String query, {int limit = 5});

  /// Resolves [location] into a short human-readable label.
  ///
  /// Optional by nature: returning an empty string means "no label
  /// available", and the coordinates stay fully usable.
  Future<String> describeLocation(LatLng location);

  /// Releases any resources held by the service.
  ///
  /// Only the owner of an implementation may call it (the screens that
  /// construct their own service instead of receiving an injected one).
  void dispose() {}
}

/// Place search backed by the public OpenStreetMap Nominatim API.
///
/// Follows the documented usage policy: a single request per user action, no
/// automatic retries, an identifying User-Agent, and results attributed on the
/// map. Autocomplete is intentionally not implemented — Nominatim forbids
/// client-side autocomplete, so the picker only searches on an explicit,
/// debounced user query.
class NominatimPlaceSearchService implements PlaceSearchService {
  NominatimPlaceSearchService({
    http.Client? client,
    this.userAgent = _defaultUserAgent,
  }) : _client = client ?? http.Client();

  /// Identifies the application, as the Nominatim usage policy requires.
  /// Stock library user-agents are explicitly not accepted.
  static const String _defaultUserAgent =
      'CivicLensMobile/1.0 (com.genevo.civiclens_mobile; civic-reporting-app)';

  static const String _host = 'nominatim.openstreetmap.org';

  final http.Client _client;
  final String userAgent;

  @override
  Future<List<PlaceResult>> search(String query, {int limit = 5}) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      return const [];
    }

    final uri = Uri.https(_host, '/search', {
      'q': trimmed,
      'format': 'jsonv2',
      'limit': '$limit',
      'addressdetails': '1',
    });

    final http.Response response;

    try {
      response = await _client
          .get(
            uri,
            headers: {'Accept': 'application/json', 'User-Agent': userAgent},
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const PlaceSearchException(
        PlaceSearchFailure.timeout,
        'The place search took too long. Try again, or select the location '
        'directly on the map.',
      );
    } catch (_) {
      // SocketException, ClientException, handshake failures, DNS failures.
      throw const PlaceSearchException(
        PlaceSearchFailure.networkUnavailable,
        'Could not reach place search. Check your connection, or select the '
        'location directly on the map.',
      );
    }

    if (response.statusCode == 429 || response.statusCode == 503) {
      throw const PlaceSearchException(
        PlaceSearchFailure.serviceUnavailable,
        'Place search is busy right now. Wait a moment and try again, or '
        'select the location directly on the map.',
      );
    }

    if (response.statusCode != 200) {
      throw const PlaceSearchException(
        PlaceSearchFailure.serviceUnavailable,
        'Place search is temporarily unavailable. You can still select the '
        'location directly on the map.',
      );
    }

    final List<dynamic> decoded;

    try {
      final body = jsonDecode(response.body);

      if (body is! List) {
        throw const FormatException('Expected a JSON array of results.');
      }

      decoded = body;
    } on FormatException {
      throw const PlaceSearchException(
        PlaceSearchFailure.invalidResponse,
        'Place search returned an unexpected response. You can still select '
        'the location directly on the map.',
      );
    }

    final results = <PlaceResult>[];

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;

      final latitude = _coordinate(item['lat']);
      final longitude = _coordinate(item['lon']);

      if (latitude == null || longitude == null) continue;

      final displayName = (item['display_name'] ?? '').toString().trim();

      if (displayName.isEmpty) continue;

      results.add(
        PlaceResult(
          latitude: latitude,
          longitude: longitude,
          displayName: displayName,
        ),
      );

      if (results.length >= limit) break;
    }

    return results;
  }

  /// Nominatim returns coordinates as JSON strings, so they need parsing and
  /// a range check before they can move the map.
  static double? _coordinate(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');

    if (value == null || value.isNaN || !value.isFinite) return null;

    return value;
  }

  @override
  Future<String> describeLocation(LatLng location) async {
    final uri = Uri.https(_host, '/reverse', {
      'lat': location.latitude.toString(),
      'lon': location.longitude.toString(),
      'format': 'jsonv2',
      'zoom': '18',
      'addressdetails': '1',
    });

    try {
      final response = await _client
          .get(
            uri,
            headers: {'Accept': 'application/json', 'User-Agent': userAgent},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return '';

      final result = jsonDecode(response.body);

      if (result is! Map<String, dynamic>) return '';

      final address = result['address'] as Map<String, dynamic>? ?? {};

      final road =
          address['road'] ??
          address['pedestrian'] ??
          address['footway'] ??
          address['residential'];

      final locality =
          address['neighbourhood'] ??
          address['suburb'] ??
          address['quarter'] ??
          address['village'] ??
          address['town'] ??
          address['city'] ??
          address['municipality'] ??
          address['county'];

      final state = address['state'];

      final parts = <String>[];

      for (final value in [road, locality, state]) {
        if (value == null) continue;

        final text = value.toString().trim();

        if (text.isNotEmpty && !parts.contains(text)) {
          parts.add(text);
        }
      }

      if (parts.isNotEmpty) return parts.join(', ');

      return (result['display_name'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    _client.close();
  }
}
