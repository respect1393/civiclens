import 'dart:async';

import 'package:civiclens_mobile/screens/location_picker_screen.dart';
import 'package:civiclens_mobile/services/location_service.dart';
import 'package:civiclens_mobile/services/place_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../helpers/fake_location_service.dart';
import '../helpers/fake_place_search_service.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// Lets a SnackBar's auto-dismiss timer fire so no fake timer is left pending.
Future<void> _flushSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await _settle(tester);
}

/// Advances past the reverse-geocoding debounce so the settled point is
/// resolved before the test asserts on it.
Future<void> _settleMap(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await _settle(tester);
}

/// Holds the value the picker pops with, so a test can assert on it after
/// tapping Confirm Location.
class _SelectionHolder {
  LocationSelection? value;
}

/// Opens the picker on its own route, the same way the report form does.
Future<_SelectionHolder> _openPicker(
  WidgetTester tester, {
  required FakeLocationService service,
  required PlaceSearchService geocoder,
  required LocationPickerScreen Function(
    FakeLocationService service,
    PlaceSearchService geocoder,
  )
  builder,
}) async {
  final holder = _SelectionHolder();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              holder.value = await Navigator.of(context)
                  .push<LocationSelection>(
                    MaterialPageRoute<LocationSelection>(
                      builder: (_) => builder(service, geocoder),
                    ),
                  );
            },
            child: const Text('Open picker'),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);

  await tester.tap(find.text('Open picker'));
  await _settle(tester);

  return holder;
}

/// Types [query] into the search field and submits it explicitly.
///
/// Nominatim forbids client-side autocomplete, so the picker only searches
/// when the citizen asks for it.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.tap(find.byIcon(Icons.search));
  await _settle(tester);
}

/// A search service whose responses are completed by the test, so requests
/// that are still in flight can be observed.
class _ControllableSearchService implements PlaceSearchService {
  int searchCalls = 0;
  final List<Completer<List<PlaceResult>>> pending = [];

  @override
  Future<List<PlaceResult>> search(String query, {int limit = 5}) {
    searchCalls++;
    final completer = Completer<List<PlaceResult>>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<String> describeLocation(LatLng location) async => '';

  @override
  void dispose() {}
}

void main() {
  testWidgets(
    'opening the picker never asks the device for a location without permission',
    (WidgetTester tester) async {
      final service = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService();

      await _openPicker(
        tester,
        service: service,
        geocoder: geocoder,
        builder: (service, geocoder) => LocationPickerScreen(
          locationService: service,
          placeSearchService: geocoder,
        ),
      );

      expect(find.text('Choose problem location'), findsOneWidget);
      // Requirement: manual selection must not need GPS permission, so the
      // picker may only centre on the device when permission already exists.
      expect(service.permissionChecks, greaterThan(0));
      expect(service.requestCount, 0);
      // Opening the picker must not search either.
      expect(geocoder.queries, isEmpty);
    },
  );

  testWidgets('Confirm Location is disabled until a point is chosen', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService();

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(
      find.text(
        'Move the map so the pin marks the problem location, or search for '
        'a place',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Confirm Location returns the exact coordinates and label supplied by the form',
    (WidgetTester tester) async {
      final service = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService();

      final holder = await _openPicker(
        tester,
        service: service,
        geocoder: geocoder,
        builder: (service, geocoder) => LocationPickerScreen(
          initialLatitude: 6.5244,
          initialLongitude: 3.3792,
          initialLabel: 'Main Street, Ikeja',
          locationService: service,
          placeSearchService: geocoder,
        ),
      );

      expect(find.text('Main Street, Ikeja'), findsOneWidget);

      final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

      await tester.tap(confirm);
      await _settle(tester);

      final selection = holder.value;
      expect(selection, isNotNull);
      expect(selection!.latitude, 6.5244);
      expect(selection.longitude, 3.3792);
      expect(selection.label, 'Main Street, Ikeja');
    },
  );

  testWidgets('a failed reading leaves manual selection usable', (
    WidgetTester tester,
  ) async {
    // Permission was granted but the reading still fails: the picker must stay
    // interactive instead of crashing or inventing coordinates.
    final service = FakeLocationService(
      granted: true,
      failure: const LocationServiceException(
        LocationFailure.permissionDenied,
        'Location permission was denied. You can still choose the problem '
        'location manually on the map.',
      ),
    );
    final geocoder = FakePlaceSearchService();

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    // The silent start-up reading failed, so nothing may be confirmed yet.
    expect(holder.value, isNull);
    final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(find.text('Choose problem location'), findsOneWidget);
  });

  // --------------------------------------------------
  // PLACE SEARCH
  // --------------------------------------------------

  testWidgets('a successful search lists the matching places', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(
      results: const [
        PlaceResult(
          latitude: 23.7271,
          longitude: 92.7176,
          displayName: 'Aizawl, Mizoram, India',
        ),
        PlaceResult(
          latitude: 23.7500,
          longitude: 92.7200,
          displayName: 'Chanmari, Aizawl, Mizoram, India',
        ),
      ],
    );

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await _search(tester, 'Aizawl');

    expect(geocoder.queries, ['Aizawl']);
    // Each row leads with the place name and keeps the rest of the address
    // as secondary detail.
    expect(find.widgetWithText(ListTile, 'Aizawl'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Mizoram, India'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Chanmari'), findsOneWidget);
    expect(
      find.widgetWithText(ListTile, 'Aizawl, Mizoram, India'),
      findsOneWidget,
    );
    // A successful search must not raise an error message.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'typing alone never sends a search request (Nominatim forbids autocomplete)',
    (WidgetTester tester) async {
      final service = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService(
        results: const [
          PlaceResult(
            latitude: 23.7271,
            longitude: 92.7176,
            displayName: 'Aizawl, Mizoram, India',
          ),
        ],
      );

      await _openPicker(
        tester,
        service: service,
        geocoder: geocoder,
        builder: (service, geocoder) => LocationPickerScreen(
          locationService: service,
          placeSearchService: geocoder,
        ),
      );

      await tester.enterText(find.byType(TextField), 'Aizawl');
      await _settle(tester);

      expect(geocoder.queries, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('an empty search result is reported as no match', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(results: const []);

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await _search(tester, 'zzzznowhere');

    expect(geocoder.queries, ['zzzznowhere']);
    // "Nothing matched" must be told apart from a network or service error.
    expect(find.textContaining('No places matched'), findsOneWidget);
    expect(find.textContaining('Could not reach'), findsNothing);
    expect(find.textContaining('temporarily unavailable'), findsNothing);

    await _flushSnackBar(tester);
  });

  testWidgets('a network failure is reported as unreachable, not as no match', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(
      failure: const PlaceSearchException(
        PlaceSearchFailure.networkUnavailable,
        'Could not reach place search. Check your connection, or select the '
        'location directly on the map.',
      ),
    );

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await _search(tester, 'Aizawl');

    expect(find.textContaining('Could not reach place search'), findsOneWidget);
    // It must never claim the place simply was not found.
    expect(find.textContaining('No places matched'), findsNothing);

    await _flushSnackBar(tester);
  });

  testWidgets('an HTTP failure is reported as a busy service', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(
      failure: const PlaceSearchException(
        PlaceSearchFailure.serviceUnavailable,
        'Place search is busy right now. Wait a moment and try again, or '
        'select the location directly on the map.',
      ),
    );

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await _search(tester, 'Aizawl');

    expect(
      find.textContaining('Place search is busy right now'),
      findsOneWidget,
    );
    expect(find.textContaining('No places matched'), findsNothing);

    await _flushSnackBar(tester);
  });

  testWidgets('a timeout is reported as slow, not as no match', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(
      failure: const PlaceSearchException(
        PlaceSearchFailure.timeout,
        'The place search took too long. Try again, or select the location '
        'directly on the map.',
      ),
    );

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await _search(tester, 'Aizawl');

    expect(find.textContaining('took too long'), findsOneWidget);
    expect(find.textContaining('No places matched'), findsNothing);

    await _flushSnackBar(tester);
  });

  testWidgets('an invalid response is reported as unexpected, not empty', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(
      failure: const PlaceSearchException(
        PlaceSearchFailure.invalidResponse,
        'Place search returned an unexpected response. You can still select '
        'the location directly on the map.',
      ),
    );

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await _search(tester, 'Aizawl');

    expect(find.textContaining('unexpected response'), findsOneWidget);
    expect(find.textContaining('No places matched'), findsNothing);

    await _flushSnackBar(tester);
  });

  testWidgets('selecting a result moves the map and enables Confirm Location', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(
      results: const [
        PlaceResult(
          latitude: 23.7271,
          longitude: 92.7176,
          displayName: 'Aizawl, Mizoram, India',
        ),
      ],
      addressLabel: 'Aizawl, Mizoram',
    );

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await _search(tester, 'Aizawl');
    await tester.tap(find.widgetWithText(ListTile, 'Aizawl'));
    await _settle(tester);

    // The chosen place becomes the selected problem location. The label
    // appears in the search field and in the panel, so assert on the panel
    // through the address status text, which is unique to it.
    expect(
      find.descendant(
        of: find.byType(LocationPickerScreen),
        matching: find.text('Aizawl, Mizoram, India'),
      ),
      findsWidgets,
    );

    final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await _settle(tester);

    final selection = holder.value;
    expect(selection, isNotNull);
    expect(selection!.latitude, 23.7271);
    expect(selection.longitude, 92.7176);
    expect(selection.label, 'Aizawl, Mizoram, India');
  });

  testWidgets('manual map selection still works after a failed search', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(
      failure: const PlaceSearchException(
        PlaceSearchFailure.networkUnavailable,
        'Could not reach place search. Check your connection, or select the '
        'location directly on the map.',
      ),
      addressLabel: 'Chanmari, Aizawl',
    );

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await _search(tester, 'Aizawl');
    expect(find.textContaining('Could not reach place search'), findsOneWidget);
    await _flushSnackBar(tester);

    // The failure must not lock the map: a tap still selects a point. Tap
    // away from the centre pin, the map controls and the attribution.
    await tester.tapAt(
      tester.getTopLeft(find.byType(FlutterMap)) + const Offset(120, 120),
    );
    // flutter_map holds the tap for its double-tap timeout, so advance time
    // before settling for the gesture arena to resolve.
    await tester.pump(const Duration(milliseconds: 500));
    await _settle(tester);

    final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await _settle(tester);

    // The coordinates are real, and no address label was invented.
    final selection = holder.value;
    expect(selection, isNotNull);
    expect(selection!.latitude, isNot(0));
    expect(selection.label, 'Chanmari, Aizawl');
  });

  // --------------------------------------------------
  // FIXED CENTRE PIN
  // --------------------------------------------------

  testWidgets('the pin sits on the centre of the map viewport', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService();

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    final mapCentre = tester.getCenter(find.byType(FlutterMap));
    final pin = find.byIcon(Icons.location_on).first;

    // Horizontally centred in the actual map viewport, not the screen...
    expect(tester.getCenter(pin).dx, moreOrLessEquals(mapCentre.dx));
    // ...and vertically placed so the tip of the pin marks the point that
    // will be selected, whatever the header and bottom panel do to layout.
    expect(
      tester.getBottomRight(pin).dy,
      moreOrLessEquals(mapCentre.dy, epsilon: 8),
    );
  });

  testWidgets('dragging the map settles one new point and one address lookup', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(addressLabel: 'Chanmari, Aizawl');

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        initialLatitude: 23.7271,
        initialLongitude: 92.7176,
        initialLabel: 'Aizawl, Mizoram, India',
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    const originalPoint = '23.727100, 92.717600';
    expect(find.text(originalPoint), findsOneWidget);
    expect(find.text('Aizawl, Mizoram, India'), findsOneWidget);

    // The pin never moves; the map moves underneath it.
    await tester.drag(find.byType(FlutterMap), const Offset(-140, -60));
    await _settleMap(tester);

    // The candidate point is now whatever sits under the pin, and the whole
    // gesture cost exactly one reverse-geocoding request.
    expect(find.text(originalPoint), findsNothing);
    expect(find.text('Chanmari, Aizawl'), findsOneWidget);
    expect(geocoder.describeCalls, 1);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Location'));
    await _settle(tester);

    final selection = holder.value;
    expect(selection, isNotNull);
    expect(selection!.latitude, isNot(23.7271));
    expect(selection.longitude, isNot(92.7176));
    expect(selection.label, 'Chanmari, Aizawl');
  });

  testWidgets('zooming keeps the selected point and its label', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(addressLabel: 'Should not appear');

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        initialLatitude: 23.7271,
        initialLongitude: 92.7176,
        initialLabel: 'Aizawl, Mizoram, India',
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await tester.tap(find.byTooltip('Zoom in'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Zoom in'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Zoom out'));
    await _settle(tester);

    // Zooming changes the scale, never the point under the pin, and it must
    // not fire a needless reverse-geocoding request.
    expect(find.text('23.727100, 92.717600'), findsOneWidget);
    expect(find.text('Aizawl, Mizoram, India'), findsOneWidget);
    expect(geocoder.describeCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Location'));
    await _settle(tester);

    expect(holder.value!.latitude, 23.7271);
    expect(holder.value!.longitude, 92.7176);
    expect(holder.value!.label, 'Aizawl, Mizoram, India');
  });

  testWidgets('the current-location control centres the pin on the fix', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(
      granted: false,
      deviceLocation: const DeviceLocation(
        latitude: 23.74,
        longitude: 92.72,
        accuracy: 12,
      ),
    );
    final geocoder = FakePlaceSearchService(addressLabel: 'Chanmari, Aizawl');

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    // Opening the picker never asks for a location on its own.
    expect(service.requestCount, 0);

    await tester.tap(find.byTooltip('Use my current location'));
    await _settle(tester);

    // The reading moves the map, and the citizen is told the point moved so
    // they can still adjust or decline it.
    expect(service.requestCount, 1);
    expect(find.text('23.740000, 92.720000'), findsOneWidget);
    expect(find.text('Chanmari, Aizawl'), findsOneWidget);
    expect(
      find.textContaining('Map centred on your current location'),
      findsOneWidget,
    );

    // The message floats over the confirmation button until it dismisses.
    await _flushSnackBar(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Location'));
    await _settle(tester);

    final selection = holder.value;
    expect(selection, isNotNull);
    expect(selection!.latitude, 23.74);
    expect(selection.longitude, 92.72);
    expect(selection.label, 'Chanmari, Aizawl');
  });

  testWidgets('a failed reverse geocoding never blocks the coordinates', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = FakePlaceSearchService(
      addressError: const PlaceSearchException(
        PlaceSearchFailure.networkUnavailable,
        'Could not reach place search. Check your connection, or select the '
        'location directly on the map.',
      ),
    );

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await tester.tapAt(
      tester.getTopLeft(find.byType(FlutterMap)) + const Offset(150, 150),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await _settle(tester);

    // The lookup failed, so no name is invented and the point stays usable.
    expect(geocoder.describeCalls, 1);
    expect(find.textContaining('Address unavailable'), findsOneWidget);

    final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await _settle(tester);

    expect(holder.value, isNotNull);
    expect(holder.value!.latitude, isNot(0));
    expect(holder.value!.label, '');
  });

  testWidgets('a search never runs twice at the same time', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false);
    final geocoder = _ControllableSearchService();

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await tester.enterText(find.byType(TextField), 'Aizawl');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(geocoder.searchCalls, 1);
    // Progress is visible while the request is in flight.
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // A second explicit submit while the first is still running must not add
    // another request to the public endpoint.
    await tester.enterText(find.byType(TextField), 'Aizawl');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(geocoder.searchCalls, 1);

    geocoder.pending.first.complete(const [
      PlaceResult(
        latitude: 23.7271,
        longitude: 92.7176,
        displayName: 'Aizawl, Mizoram, India',
      ),
    ]);
    await _settle(tester);

    expect(find.widgetWithText(ListTile, 'Aizawl'), findsOneWidget);
  });

  // --------------------------------------------------
  // GPS ACCURACY
  //
  // A high-accuracy request is a request to the device, not a guarantee, so
  // anything that misses the accuracy target has to be shown and explained
  // instead of being silently placed under the pin.
  // --------------------------------------------------

  testWidgets('an inaccurate fix is explained instead of being applied', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(
      deviceLocation: const DeviceLocation(
        latitude: 23.74,
        longitude: 92.72,
        accuracy: 1500,
      ),
    );
    final geocoder = FakePlaceSearchService(addressLabel: 'Chanmari, Aizawl');

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await tester.tap(find.byTooltip('Use my current location'));
    await _settle(tester);

    // The reading arrived, but it is roughly a kilometre and a half off, so
    // the citizen is told exactly that instead of the pin silently moving.
    expect(find.text('Location may be inaccurate'), findsOneWidget);
    expect(
      find.textContaining('Reported accuracy: about ±1,500 m'),
      findsOneWidget,
    );
    expect(
      find.textContaining('less accurate than the target'),
      findsOneWidget,
    );
    expect(find.text('23.740000, 92.720000'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);

    final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    // Choosing the map over the fix changes nothing at all.
    await tester.tap(find.widgetWithText(TextButton, 'Choose on map'));
    await _settle(tester);

    expect(find.text('Location may be inaccurate'), findsNothing);
    expect(find.text('23.740000, 92.720000'), findsNothing);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(holder.value, isNull);
  });

  testWidgets('an imperfect fix is applied only after the citizen accepts it', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(
      deviceLocation: const DeviceLocation(
        latitude: 23.74,
        longitude: 92.72,
        accuracy: 1500,
      ),
    );
    final geocoder = FakePlaceSearchService(addressLabel: 'Chanmari, Aizawl');

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await tester.tap(find.byTooltip('Use my current location'));
    await _settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Use this location'));
    await _settle(tester);

    // Accepted explicitly, and the message repeats the real accuracy rather
    // than claiming a precise GPS fix.
    expect(find.text('Location may be inaccurate'), findsNothing);
    expect(find.text('23.740000, 92.720000'), findsOneWidget);
    expect(
      find.textContaining('Using the best available location'),
      findsOneWidget,
    );
    expect(find.textContaining('±1,500 m'), findsOneWidget);

    await _flushSnackBar(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Location'));
    await _settle(tester);

    final selection = holder.value;
    expect(selection, isNotNull);
    expect(selection!.latitude, 23.74);
    expect(selection.longitude, 92.72);
    expect(selection.label, 'Chanmari, Aizawl');
  });

  testWidgets('trying again from the dialog repeats the request', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(granted: false)
      ..outcomes.addAll(const [
        // First reading is a coarse network fix...
        DeviceLocation(latitude: 23.74, longitude: 92.72, accuracy: 1500),
        // ...the retry gets a real GPS fix.
        DeviceLocation(latitude: 23.74, longitude: 92.72, accuracy: 9),
      ]);
    final geocoder = FakePlaceSearchService(addressLabel: 'Chanmari, Aizawl');

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    await tester.tap(find.byTooltip('Use my current location'));
    await _settle(tester);

    expect(find.text('Location may be inaccurate'), findsOneWidget);
    expect(service.requestCount, 1);

    await tester.tap(find.widgetWithText(TextButton, 'Try again'));
    await _settle(tester);

    // One request at a time, and the better fix is applied directly.
    expect(service.requestCount, 2);
    expect(find.text('Location may be inaccurate'), findsNothing);
    expect(find.text('23.740000, 92.720000'), findsOneWidget);
    expect(
      find.textContaining('Map centred on your current location'),
      findsOneWidget,
    );
    expect(find.textContaining('accuracy ±9 m'), findsOneWidget);

    await _flushSnackBar(tester);
  });

  testWidgets('approximate-only permission is reported even at 25 m', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(
      granted: true,
      approximatePermission: true,
      deviceLocation: const DeviceLocation(
        latitude: 23.74,
        longitude: 92.72,
        accuracy: 25,
      ),
    );
    final geocoder = FakePlaceSearchService(addressLabel: 'Chanmari, Aizawl');

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    // The start-up read runs but never applies an approximate fix silently.
    expect(service.requestCount, 1);
    expect(find.text('Location may be inaccurate'), findsNothing);
    expect(find.text('23.740000, 92.720000'), findsNothing);

    await tester.tap(find.byTooltip('Use my current location'));
    await _settle(tester);

    expect(find.text('Location may be inaccurate'), findsOneWidget);
    expect(
      find.textContaining('only sharing an approximate location'),
      findsOneWidget,
    );
    // The reported accuracy is shown too, even though it looks acceptable.
    expect(
      find.textContaining('Reported accuracy: about ±25 m'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Choose on map'));
    await _settle(tester);

    expect(find.text('23.740000, 92.720000'), findsNothing);
    expect(holder.value, isNull);
  });

  testWidgets('the start-up read never centres on an unverified fix', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(
      granted: true,
      deviceLocation: const DeviceLocation(
        latitude: 23.74,
        longitude: 92.72,
        accuracy: 1400,
      ),
    );
    final geocoder = FakePlaceSearchService(addressLabel: 'Chanmari, Aizawl');

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    // The opportunistic read happened, without prompting for permission...
    expect(service.requestCount, 1);
    expect(service.lastRequestedPermission, isFalse);
    expect(service.requestedTimeLimits.single, backgroundLocationTimeLimit);
    // ...but an unverified fix never moves the pin or nags on its own.
    expect(find.text('Location may be inaccurate'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.text(
        'Move the map so the pin marks the problem location, or search for '
        'a place',
      ),
      findsOneWidget,
    );

    // Manual selection is untouched by the failed verification.
    await tester.tapAt(
      tester.getTopLeft(find.byType(FlutterMap)) + const Offset(120, 120),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await _settle(tester);

    final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('the start-up read centres silently on an accurate fix', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(
      granted: true,
      deviceLocation: const DeviceLocation(
        latitude: 23.74,
        longitude: 92.72,
        accuracy: 8,
      ),
    );
    final geocoder = FakePlaceSearchService(addressLabel: 'Chanmari, Aizawl');

    await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    expect(service.requestCount, 1);
    expect(service.lastRequestedPermission, isFalse);
    expect(find.text('23.740000, 92.720000'), findsOneWidget);
    expect(find.text('Chanmari, Aizawl'), findsOneWidget);
    // A quiet background read never talks to the citizen.
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Location may be inaccurate'), findsNothing);

    final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('a failed reading offers retry and keeps manual selection', (
    WidgetTester tester,
  ) async {
    final service = FakeLocationService(
      granted: true,
      failure: const LocationServiceException(
        LocationFailure.timeout,
        'Could not get your location in time. You can still choose the '
        'problem location manually on the map.',
      ),
    );
    final geocoder = FakePlaceSearchService(addressLabel: 'Chanmari, Aizawl');

    final holder = await _openPicker(
      tester,
      service: service,
      geocoder: geocoder,
      builder: (service, geocoder) => LocationPickerScreen(
        locationService: service,
        placeSearchService: geocoder,
      ),
    );

    // The silent start-up read failed without nagging: only the explicit
    // request has spoken so far.
    expect(find.byType(SnackBar), findsNothing);
    expect(service.requestCount, 1);

    await tester.tap(find.byTooltip('Use my current location'));
    await _settle(tester);

    // The message keeps pointing at manual selection and offers a retry.
    expect(
      find.textContaining('Could not get your location in time'),
      findsOneWidget,
    );
    expect(find.text('RETRY'), findsOneWidget);
    expect(service.requestCount, 2); // start-up read + explicit read

    // Manual selection still works with the failure on screen.
    await tester.tapAt(
      tester.getTopLeft(find.byType(FlutterMap)) + const Offset(120, 120),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await _settle(tester);

    final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(find.text('RETRY'));
    await _settle(tester);
    expect(service.requestCount, 3);

    // Let the repeated failure message dismiss before confirming: it floats
    // over the bottom panel and would swallow the tap.
    await _flushSnackBar(tester);
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(confirm);
    await _settle(tester);

    expect(find.text('Confirm Location'), findsNothing);
    final selection = holder.value;
    expect(selection, isNotNull);
    expect(selection!.latitude, isNot(0));

    await _flushSnackBar(tester);
  });

  testWidgets('a second GPS request never starts while one is running', (
    WidgetTester tester,
  ) async {
    final pending = Completer<DeviceLocation>();
    final service = FakeLocationService(granted: true, pending: pending);
    final geocoder = FakePlaceSearchService(addressLabel: 'Chanmari, Aizawl');
    final holder = _SelectionHolder();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                holder.value = await Navigator.of(context)
                    .push<LocationSelection>(
                      MaterialPageRoute<LocationSelection>(
                        builder: (_) => LocationPickerScreen(
                          locationService: service,
                          placeSearchService: geocoder,
                        ),
                      ),
                    );
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('Open picker'));
    // The start-up read parks on the pending reading, so its progress
    // spinner runs forever: pumpAndSettle would never return, and frames are
    // pumped by hand instead until the route transition is over.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(service.requestCount, 1);

    // While the start-up read is in flight the control is disabled, so an
    // explicit tap cannot stack a second GPS request on top of it.
    await tester.tap(find.byTooltip('Use my current location'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.requestCount, 1);
    expect(find.textContaining('Finding your location...'), findsOneWidget);

    pending.complete(
      const DeviceLocation(latitude: 23.74, longitude: 92.72, accuracy: 7),
    );
    await _settle(tester);

    expect(service.requestCount, 1);
    expect(find.text('23.740000, 92.720000'), findsOneWidget);
    expect(find.textContaining('Finding your location...'), findsNothing);
  });
}
