import 'package:civiclens_mobile/services/place_search_service.dart';
import 'package:latlong2/latlong.dart';

/// In-memory [PlaceSearchService] double.
///
/// Widget tests must not reach the live Nominatim API, so every success,
/// empty, network, service and timeout path is scripted here and the picker
/// is exercised against the messages and state changes it produces.
class FakePlaceSearchService implements PlaceSearchService {
  FakePlaceSearchService({
    this.results = const [],
    this.failure,
    this.addressLabel = '',
    this.addressError,
  });

  /// Matches returned on a successful search.
  final List<PlaceResult> results;

  /// Thrown instead of results when scripted to fail.
  final PlaceSearchException? failure;

  /// Label returned by [describeLocation]; empty means "no label available".
  final String addressLabel;

  /// Thrown by [describeLocation] when scripted to fail, so reverse-geocoding
  /// failures can be exercised without the live service.
  final Object? addressError;

  /// Queries received, so tests can assert exactly how many requests were
  /// sent and what they carried.
  final List<String> queries = [];

  /// Number of [describeLocation] calls.
  int describeCalls = 0;

  @override
  Future<List<PlaceResult>> search(String query, {int limit = 5}) async {
    queries.add(query);

    final failure = this.failure;
    if (failure != null) throw failure;

    return results.take(limit).toList();
  }

  @override
  Future<String> describeLocation(LatLng location) async {
    describeCalls++;

    final addressError = this.addressError;
    if (addressError != null) throw addressError;

    return addressLabel;
  }

  @override
  void dispose() {}
}
