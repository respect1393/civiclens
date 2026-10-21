import 'dart:convert';

import 'package:civiclens_mobile/services/place_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

/// Builds a service whose HTTP layer is fully scripted, so no test ever
/// depends on live internet access.
NominatimPlaceSearchService _service(
  Future<http.Response> Function(http.Request request) handler,
) {
  return NominatimPlaceSearchService(client: MockClient(handler));
}

void main() {
  group('NominatimPlaceSearchService.search', () {
    test('parses a successful response and identifies the app', () async {
      http.Request? seen;

      final service = _service((request) async {
        seen = request;
        return http.Response(
          jsonEncode([
            {
              'lat': '23.7271',
              'lon': '92.7176',
              'display_name': 'Aizawl, Mizoram, India',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final results = await service.search('Aizawl');

      expect(results, hasLength(1));
      expect(results.single.latitude, 23.7271);
      expect(results.single.longitude, 92.7176);
      expect(results.single.displayName, 'Aizawl, Mizoram, India');

      // The usage policy requires an identifying User-Agent; a stock
      // library user-agent is not accepted.
      expect(seen!.headers['User-Agent'], contains('CivicLensMobile'));
      expect(seen!.url.path, '/search');
      expect(seen!.url.queryParameters['q'], 'Aizawl');
      expect(seen!.url.queryParameters['limit'], '5');
    });

    test('an empty JSON array is a legitimate no-match answer', () async {
      final service = _service((request) async {
        return http.Response(
          jsonEncode([]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(await service.search('zzzznowhere'), isEmpty);
    });

    test('a blank query is answered locally without any request', () async {
      var requests = 0;

      final service = _service((request) async {
        requests++;
        return http.Response('[]', 200);
      });

      expect(await service.search('   '), isEmpty);
      expect(requests, 0);
    });

    test('results past [limit] are dropped', () async {
      final service = _service((request) async {
        return http.Response(
          jsonEncode([
            for (var i = 0; i < 10; i++)
              {'lat': '$i', 'lon': '$i', 'display_name': 'Place $i'},
          ]),
          200,
        );
      });

      expect((await service.search('place', limit: 2)).length, 2);
    });

    test('entries without usable coordinates are skipped', () async {
      final service = _service((request) async {
        return http.Response(
          jsonEncode([
            {'lat': 'not-a-number', 'lon': '92.7176', 'display_name': 'Bad'},
            {'lat': '23.7271', 'lon': '92.7176', 'display_name': ''},
            {'lat': '23.75', 'lon': '92.72', 'display_name': 'Good'},
          ]),
          200,
        );
      });

      final results = await service.search('Aizawl');

      expect(results, hasLength(1));
      expect(results.single.displayName, 'Good');
    });

    test('a socket error is reported as networkUnavailable', () async {
      final service = _service((request) async {
        throw http.ClientException('Failed host lookup');
      });

      final error = await service
          .search('Aizawl')
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<PlaceSearchException>());
      final failure = error as PlaceSearchException;
      expect(failure.failure, PlaceSearchFailure.networkUnavailable);
      expect(failure.message, contains('select the location directly'));
    });

    test(
      'HTTP 429 is reported as serviceUnavailable, not as no match',
      () async {
        final service = _service((request) async {
          return http.Response('rate limited', 429);
        });

        final error =
            await service
                    .search('Aizawl')
                    .then<Object?>((_) => null, onError: (Object e) => e)
                as PlaceSearchException;

        expect(error.failure, PlaceSearchFailure.serviceUnavailable);
        expect(error.message, isNot(contains('No places matched')));
      },
    );

    test('HTTP 500 is reported as serviceUnavailable', () async {
      final service = _service((request) async {
        return http.Response('server error', 500);
      });

      final error =
          await service
                  .search('Aizawl')
                  .then<Object?>((_) => null, onError: (Object e) => e)
              as PlaceSearchException;

      expect(error.failure, PlaceSearchFailure.serviceUnavailable);
    });

    test('a non-JSON body is reported as invalidResponse', () async {
      final service = _service((request) async {
        return http.Response(
          '<html>captcha</html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      final error =
          await service
                  .search('Aizawl')
                  .then<Object?>((_) => null, onError: (Object e) => e)
              as PlaceSearchException;

      expect(error.failure, PlaceSearchFailure.invalidResponse);
    });

    test('a JSON object instead of an array is invalidResponse', () async {
      final service = _service((request) async {
        return http.Response(jsonEncode({'error': 'wrong'}), 200);
      });

      final error =
          await service
                  .search('Aizawl')
                  .then<Object?>((_) => null, onError: (Object e) => e)
              as PlaceSearchException;

      expect(error.failure, PlaceSearchFailure.invalidResponse);
    });
  });

  group('NominatimPlaceSearchService.describeLocation', () {
    test('builds a short label from the address parts', () async {
      final service = _service((request) async {
        expect(request.url.path, '/reverse');

        return http.Response(
          jsonEncode({
            'display_name': 'long, full, display, name',
            'address': {
              'road': 'Bara Bazar',
              'town': 'Aizawl',
              'state': 'Mizoram',
            },
          }),
          200,
        );
      });

      final label = await service.describeLocation(
        const LatLng(23.7271, 92.7176),
      );

      expect(label, 'Bara Bazar, Aizawl, Mizoram');
    });

    test('falls back to display_name when no address parts exist', () async {
      final service = _service((request) async {
        return http.Response(
          jsonEncode({'display_name': 'Aizawl, India', 'address': {}}),
          200,
        );
      });

      expect(
        await service.describeLocation(const LatLng(23.7271, 92.7176)),
        'Aizawl, India',
      );
    });

    test('any failure yields an empty label instead of throwing', () async {
      final service = _service((request) async {
        throw http.ClientException('offline');
      });

      expect(
        await service.describeLocation(const LatLng(23.7271, 92.7176)),
        '',
      );
    });

    test('a non-200 reverse response yields an empty label', () async {
      final service = _service((request) async {
        return http.Response('no data', 404);
      });

      expect(
        await service.describeLocation(const LatLng(23.7271, 92.7176)),
        '',
      );
    });
  });
}
