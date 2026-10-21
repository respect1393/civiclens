import 'package:civiclens_mobile/screens/report_issue_screen.dart';
import 'package:civiclens_mobile/services/location_service.dart';
import 'package:civiclens_mobile/services/place_search_service.dart';
import 'package:civiclens_mobile/state/report_repository.dart';
import 'package:civiclens_mobile/state/report_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../helpers/fake_image_picker.dart';
import '../helpers/fake_location_service.dart';
import '../helpers/fake_place_search_service.dart';
import '../helpers/fake_report_api_service.dart';
import '../helpers/fake_report_store.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// Lets a SnackBar's auto-dismiss timer fire so no fake timer is left pending.
///
/// The location-name suggestion bar outlives the default, so those tests pump
/// for longer than the usual five seconds.
Future<void> _flushSnackBar(WidgetTester tester, {int seconds = 5}) async {
  await tester.pump(Duration(seconds: seconds));
  await _settle(tester);
}

Future<ReportRepository> _buildRepository() async {
  final repository = ReportRepository(
    store: FakeReportStore(),
    apiService: FakeReportApiService(),
    accessToken: () => 'test-token',
  );
  await repository.load();
  return repository;
}

Future<ReportRepository> _pumpForm(
  WidgetTester tester, {
  required LocationService locationService,
  PlaceSearchService? placeSearchService,
  ImagePicker? imagePicker,
}) async {
  final repository = await _buildRepository();

  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ReportScope(
      repository: repository,
      child: MaterialApp(
        home: ReportIssueScreen(
          locationService: locationService,
          placeSearchService: placeSearchService,
          imagePicker: imagePicker,
        ),
      ),
    ),
  );
  await _settle(tester);
  return repository;
}

/// Opens the map picker, taps a point on it and confirms the selection.
///
/// [offset] is measured from the top-left corner of the map; two different
/// values give two different reporting points.
Future<void> _choosePointOnMap(
  WidgetTester tester, {
  Offset offset = const Offset(150, 150),
}) async {
  // The entry point is the same section either way: before a point exists it
  // offers to choose one, afterwards it offers to change it.
  var openMap = find.text('Choose problem location');
  if (openMap.evaluate().isEmpty) {
    openMap = find.text('Change location on map');
  }

  // The location section sits below the details the citizen already filled
  // in, so bring it on screen before tapping it.
  await tester.ensureVisible(openMap);
  await _settle(tester);

  await tester.tap(openMap);
  await _settle(tester);

  await tester.tapAt(tester.getTopLeft(find.byType(FlutterMap)) + offset);
  // flutter_map holds the tap for its double-tap timeout; advancing time lets
  // the gesture arena resolve before we settle.
  await tester.pump(const Duration(milliseconds: 500));
  await _settle(tester);

  await tester.tap(find.widgetWithText(FilledButton, 'Confirm Location'));
  await _settle(tester);
}

/// The description field is the second text field on the form.
EditableText _descriptionEditable(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(TextFormField).at(1),
    matching: find.byType(EditableText),
  );
  return tester.widget<EditableText>(finder);
}

/// The title, description and photo the form requires before the location
/// section can even be checked, filled exactly as a citizen would.
Future<void> _fillIssueDetails(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await _settle(tester);
  await tester.tap(find.text('Water Supply'));
  await _settle(tester);

  await tester.enterText(
    find.byType(TextFormField).at(0),
    'Leaking pipe near the market',
  );
  await tester.enterText(
    find.byType(TextFormField).at(1),
    'Water leaks from the pipe every morning and floods the footpath.',
  );
  await _settle(tester);

  await tester.tap(find.text('Add photo evidence *'));
  await _settle(tester);
  await tester.tap(find.text('Choose from gallery'));
  await _settle(tester);
}

/// The confirmation line the form shows once a point has been selected.
String _selectedLine(WidgetTester tester) {
  return tester
      .widget<Text>(find.textContaining('Problem location selected:'))
      .data!;
}

/// Pumps until [finder] shows up without waiting for the tree to go quiet.
///
/// The submit button keeps its spinner running while the save dialog is
/// open, so [WidgetTester.pumpAndSettle] would never return there; a bounded
/// number of frames is what this step actually needs.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 50,
}) async {
  for (var i = 0; i < maxPumps && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  // Give the dialog time to finish entering before it is touched.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('device location', () {
    testWidgets('a denied permission explains itself and saves nothing', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(
        granted: false,
        failure: const LocationServiceException(
          LocationFailure.permissionDenied,
          'Location permission was denied. You can still choose the problem '
          'location manually on the map.',
        ),
      );

      await _pumpForm(tester, locationService: fake);

      await tester.tap(find.text('Use my current location'));
      await _settle(tester);

      expect(fake.requestCount, 1);
      expect(
        find.textContaining('Location permission was denied'),
        findsOneWidget,
      );
      // No coordinates may be invented when the request fails.
      expect(find.textContaining('Problem location selected'), findsNothing);
      expect(find.text('Choose problem location'), findsOneWidget);

      await _flushSnackBar(tester);
    });

    testWidgets('a permanently denied permission points to settings', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(
        failure: const LocationServiceException(
          LocationFailure.permissionDeniedForever,
          'Location permission is permanently denied. Enable it in your '
          'device settings, or choose the problem location manually on '
          'the map.',
        ),
      );

      await _pumpForm(tester, locationService: fake);

      await tester.tap(find.text('Use my current location'));
      await _settle(tester);

      expect(find.textContaining('permanently denied'), findsOneWidget);
      expect(find.textContaining('Problem location selected'), findsNothing);

      await _flushSnackBar(tester);
    });

    testWidgets('disabled location services are reported clearly', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(
        failure: const LocationServiceException(
          LocationFailure.servicesDisabled,
          'Location services are disabled. Enable them, or choose the '
          'problem location manually on the map.',
        ),
      );

      await _pumpForm(tester, locationService: fake);

      await tester.tap(find.text('Use my current location'));
      await _settle(tester);

      expect(
        find.textContaining('Location services are disabled'),
        findsOneWidget,
      );
      expect(find.textContaining('Problem location selected'), findsNothing);

      await _flushSnackBar(tester);
    });

    testWidgets('a timed-out request never blocks the form', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(
        failure: const LocationServiceException(
          LocationFailure.timeout,
          'Could not get your location in time. You can still choose the '
          'problem location manually on the map.',
        ),
      );

      await _pumpForm(tester, locationService: fake);

      await tester.tap(find.text('Use my current location'));
      await _settle(tester);

      expect(
        find.textContaining('Could not get your location in time'),
        findsOneWidget,
      );
      expect(find.textContaining('Problem location selected'), findsNothing);
      // The button must be usable again.
      expect(find.text('Use my current location'), findsOneWidget);

      await _flushSnackBar(tester);
    });

    testWidgets('a granted permission stores the returned coordinates', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(
        granted: true,
        deviceLocation: const DeviceLocation(
          latitude: 6.5244,
          longitude: 3.3792,
          accuracy: 8,
        ),
      );

      await _pumpForm(tester, locationService: fake);

      await tester.tap(find.text('Use my current location'));
      await _settle(tester);

      expect(
        find.textContaining('Problem location selected: 6.524400, 3.379200'),
        findsOneWidget,
      );
    });
  });

  group('description focus', () {
    testWidgets(
      'closing the photo sheet does not reopen the keyboard on description',
      (WidgetTester tester) async {
        final fake = FakeLocationService();
        await _pumpForm(tester, locationService: fake);

        final descriptionFocus = _descriptionEditable(tester).focusNode;

        // The citizen is typing a description...
        await tester.tap(find.byType(TextFormField).at(1));
        await _settle(tester);
        expect(FocusManager.instance.primaryFocus, descriptionFocus);

        // ...then opens and dismisses the photo sheet without choosing.
        await tester.tap(find.text('Add photo evidence *'));
        await _settle(tester);
        expect(find.text('Add photo evidence'), findsOneWidget);

        await tester.tapAt(const Offset(8, 8));
        await _settle(tester);

        // Regression for the reported bug: the previously focused field must
        // not be restored, which used to reopen the keyboard.
        expect(FocusManager.instance.primaryFocus, isNot(descriptionFocus));
      },
    );

    testWidgets('starting a photo pick releases the keyboard immediately', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService();
      await _pumpForm(tester, locationService: fake);

      final descriptionFocus = _descriptionEditable(tester).focusNode;

      await tester.tap(find.byType(TextFormField).at(1));
      await _settle(tester);
      expect(FocusManager.instance.primaryFocus, descriptionFocus);

      await tester.tap(find.text('Add photo evidence *'));
      await _settle(tester);
      await tester.tap(find.text('Choose from gallery'));
      await tester.pump();

      // The keyboard is dismissed as soon as the pick starts, so the field
      // cannot be restored (and the keyboard reopened) when the system
      // picker returns.
      expect(FocusManager.instance.primaryFocus, isNot(descriptionFocus));
    });

    testWidgets(
      'an invalid description is only focused after an explicit submit',
      (WidgetTester tester) async {
        final fake = FakeLocationService();
        await _pumpForm(tester, locationService: fake);

        final descriptionFocus = _descriptionEditable(tester).focusNode;

        // Category + a long-enough title, but a description that is too short.
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await _settle(tester);
        await tester.tap(find.text('Water Supply'));
        await _settle(tester);

        await tester.enterText(
          find.byType(TextFormField).at(0),
          'Large pothole near the junction',
        );
        await tester.enterText(find.byType(TextFormField).at(1), 'Too short');
        await _settle(tester);

        // Typing focuses the field itself; leaving it (keyboard dismissed)
        // must not trigger any automatic focusing elsewhere.
        await tester.tap(find.byType(TextFormField).at(0));
        await _settle(tester);
        expect(FocusManager.instance.primaryFocus, isNot(descriptionFocus));

        await tester.tap(find.text('Submit Report'));
        await _settle(tester);

        // Now, and only now, the invalid field is focused.
        expect(FocusManager.instance.primaryFocus, descriptionFocus);
        expect(
          find.text('Please provide a little more detail.'),
          findsOneWidget,
        );
        expect(find.text('Report saved locally'), findsNothing);
      },
    );
  });

  group('manual location picker', () {
    testWidgets('a point chosen on the map is returned to the report form', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(granted: false);
      await _pumpForm(tester, locationService: fake);

      await tester.tap(find.text('Choose problem location'));
      await _settle(tester);

      // Opening the picker must not read the device location on its own.
      expect(fake.requestCount, 0);
      expect(find.text('Choose problem location'), findsOneWidget);

      final confirm = find.widgetWithText(FilledButton, 'Confirm Location');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      // Choose a point away from the search overlay and centre marker.
      final map = find.byType(FlutterMap);
      await tester.tapAt(tester.getTopLeft(map) + const Offset(400, 400));
      // flutter_map holds the tap for its double-tap timeout; advancing
      // time lets the gesture arena resolve before we settle.
      await tester.pump(const Duration(milliseconds: 500));
      await _settle(tester);

      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

      await tester.tap(confirm);
      await _settle(tester);

      // Back on the form with the chosen coordinates, still without any
      // device-location request.
      expect(find.textContaining('Problem location selected:'), findsOneWidget);
      expect(fake.requestCount, 0);
    });
  });

  group('location name and landmark', () {
    testWidgets('a confirmed point fills the location name automatically', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService(addressLabel: 'Kulikawn, Aizawl');

      await _pumpForm(
        tester,
        locationService: fake,
        placeSearchService: geocoder,
      );

      await _choosePointOnMap(tester);

      // The citizen never has to type a name the map already knows.
      expect(find.text('Kulikawn, Aizawl'), findsOneWidget);
      expect(find.textContaining('Problem location selected:'), findsOneWidget);
    });

    testWidgets('a hand written location name is never overwritten', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService(addressLabel: 'Kulikawn, Aizawl');

      await _pumpForm(
        tester,
        locationService: fake,
        placeSearchService: geocoder,
      );

      await _choosePointOnMap(tester);
      expect(find.text('Kulikawn, Aizawl'), findsOneWidget);

      // The citizen replaces the suggestion with their own wording...
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'Near the market gate',
      );
      await _settle(tester);

      // ...then moves the point, which must not destroy what they typed.
      await _choosePointOnMap(tester, offset: const Offset(320, 260));

      expect(find.text('Near the market gate'), findsOneWidget);
      expect(
        find.textContaining('Your location name was kept'),
        findsOneWidget,
      );

      // The new name is only offered, never forced.
      await tester.tap(find.text('Use suggestion'));
      await _settle(tester);

      expect(find.text('Kulikawn, Aizawl'), findsOneWidget);

      await _flushSnackBar(tester, seconds: 7);
    });

    testWidgets('clearing the location name hands it back to the map', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService(addressLabel: 'Kulikawn, Aizawl');

      await _pumpForm(
        tester,
        locationService: fake,
        placeSearchService: geocoder,
      );

      await _choosePointOnMap(tester);
      expect(find.text('Kulikawn, Aizawl'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(2), '');
      await _settle(tester);

      await _choosePointOnMap(tester, offset: const Offset(320, 260));

      // An untouched field follows the map again.
      expect(find.text('Kulikawn, Aizawl'), findsOneWidget);
      expect(find.textContaining('Your location name was kept'), findsNothing);
    });

    testWidgets('a landmark survives a new point and warns it may be stale', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService(addressLabel: 'Kulikawn, Aizawl');

      await _pumpForm(
        tester,
        locationService: fake,
        placeSearchService: geocoder,
      );

      await _choosePointOnMap(tester);

      await tester.enterText(
        find.byType(TextFormField).at(3),
        'Near the community hall',
      );
      await _settle(tester);
      expect(
        find.textContaining('check that this landmark still applies'),
        findsNothing,
      );

      await _choosePointOnMap(tester, offset: const Offset(320, 260));

      // The landmark is kept, but the point moved under it.
      expect(find.text('Near the community hall'), findsOneWidget);
      expect(
        find.textContaining('check that this landmark still applies'),
        findsOneWidget,
      );

      // Reviewing it clears the hint.
      await tester.enterText(
        find.byType(TextFormField).at(3),
        'Beside the water tank',
      );
      await _settle(tester);
      expect(
        find.textContaining('check that this landmark still applies'),
        findsNothing,
      );
    });
  });

  group('reopening the map', () {
    testWidgets('cancelling keeps the selection and every form field', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(
        granted: true,
        deviceLocation: const DeviceLocation(
          latitude: 6.5244,
          longitude: 3.3792,
          accuracy: 8,
        ),
      );
      final geocoder = FakePlaceSearchService(addressLabel: 'Kulikawn, Aizawl');

      await _pumpForm(
        tester,
        locationService: fake,
        placeSearchService: geocoder,
        imagePicker: FakeImagePicker(file: fakePhoto()),
      );

      await _fillIssueDetails(tester);

      await tester.tap(find.text('Use my current location'));
      await _settle(tester);

      expect(
        _selectedLine(tester),
        'Problem location selected: 6.524400, 3.379200',
      );
      expect(find.text('Kulikawn, Aizawl'), findsOneWidget);

      await tester.tap(find.text('Change location on map'));
      await _settle(tester);

      // The picker opens on the stored point instead of the whole world, and
      // the point is already confirmable — no re-finding is demanded.
      expect(find.text('6.524400, 3.379200'), findsOneWidget);
      expect(find.text('Kulikawn, Aizawl'), findsOneWidget);
      // The form underneath still holds the same name while the map is open.
      expect(
        find.text('Kulikawn, Aizawl', skipOffstage: false),
        findsNWidgets(2),
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm Location'),
            )
            .onPressed,
        isNotNull,
      );

      await tester.pageBack();
      await _settle(tester);

      // Nothing was lost by looking at the map again.
      expect(
        _selectedLine(tester),
        'Problem location selected: 6.524400, 3.379200',
      );
      expect(find.text('Kulikawn, Aizawl'), findsOneWidget);
      expect(fake.requestCount, 1);
    });

    testWidgets('confirming a new point updates the coordinates only', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService(addressLabel: 'Kulikawn, Aizawl');

      final repository = await _pumpForm(
        tester,
        locationService: fake,
        placeSearchService: geocoder,
        imagePicker: FakeImagePicker(file: fakePhoto()),
      );

      await _fillIssueDetails(tester);
      await _choosePointOnMap(tester);

      final firstSelection = _selectedLine(tester);
      expect(firstSelection, startsWith('Problem location selected:'));

      await tester.tap(find.text('Change location on map'));
      await _settle(tester);
      await tester.tapAt(
        tester.getTopLeft(find.byType(FlutterMap)) + const Offset(320, 260),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm Location'));
      await _settle(tester);

      // The coordinates follow the pin...
      expect(_selectedLine(tester), isNot(firstSelection));
      // ...and everything else the citizen already filled in stays exactly as
      // it was.
      expect(find.text('Leaking pipe near the market'), findsOneWidget);
      expect(
        find.text(
          'Water leaks from the pipe every morning and floods the footpath.',
        ),
        findsOneWidget,
      );
      expect(find.text('Photo attached'), findsOneWidget);
      expect(find.text('Kulikawn, Aizawl'), findsOneWidget);
      expect(repository.reportCount, 0);
    });
  });

  group('submission', () {
    testWidgets('a saved report keeps the location name and landmark', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService(addressLabel: 'Kulikawn, Aizawl');
      final picker = FakeImagePicker(file: fakePhoto());

      final repository = await _pumpForm(
        tester,
        locationService: fake,
        placeSearchService: geocoder,
        imagePicker: picker,
      );

      await _fillIssueDetails(tester);
      expect(picker.pickCalls, 1);
      expect(find.text('Photo attached'), findsOneWidget);

      await _choosePointOnMap(tester);
      expect(find.text('Kulikawn, Aizawl'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(3),
        'Near the community hall',
      );
      await _settle(tester);

      await tester.tap(find.text('Submit Report'));
      await _waitFor(tester, find.text('Report submitted'));

      expect(find.text('Report submitted'), findsOneWidget);
      expect(repository.reportCount, 1);

      final report = repository.reports.first;
      expect(report.locationLabel, 'Kulikawn, Aizawl');
      expect(report.landmark, 'Near the community hall');
      expect(report.hasCoordinates, isTrue);

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await _settle(tester);
    });

    testWidgets('a report is saved without a landmark when none was given', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService(addressLabel: 'Kulikawn, Aizawl');
      final picker = FakeImagePicker(file: fakePhoto());

      final repository = await _pumpForm(
        tester,
        locationService: fake,
        placeSearchService: geocoder,
        imagePicker: picker,
      );

      await _fillIssueDetails(tester);
      await _choosePointOnMap(tester);

      await tester.tap(find.text('Submit Report'));
      await _waitFor(tester, find.text('Report submitted'));

      expect(find.text('Report submitted'), findsOneWidget);

      final report = repository.reports.first;
      expect(report.locationLabel, 'Kulikawn, Aizawl');
      expect(report.landmark, isNull);
      expect(report.landmarkOrNull, isNull);

      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await _settle(tester);
    });

    testWidgets('a missing location name is reported last, if at all needed', (
      WidgetTester tester,
    ) async {
      final fake = FakeLocationService(granted: false);
      final geocoder = FakePlaceSearchService(addressLabel: 'Kulikawn, Aizawl');
      final picker = FakeImagePicker(file: fakePhoto());

      final repository = await _pumpForm(
        tester,
        locationService: fake,
        placeSearchService: geocoder,
        imagePicker: picker,
      );

      await _fillIssueDetails(tester);
      await _choosePointOnMap(tester);

      // The citizen clears the suggested name and never types a replacement.
      await tester.enterText(find.byType(TextFormField).at(2), '');
      await _settle(tester);

      await tester.tap(find.text('Submit Report'));
      await _settle(tester);

      expect(
        find.textContaining('Please enter a location name'),
        findsOneWidget,
      );
      expect(find.text('Report saved locally'), findsNothing);
      expect(repository.reportCount, 0);
    });
  });
}
