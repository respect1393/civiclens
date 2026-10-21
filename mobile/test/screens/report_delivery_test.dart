import 'package:civiclens_mobile/screens/report_issue_screen.dart';
import 'package:civiclens_mobile/services/api_client.dart';
import 'package:civiclens_mobile/services/location_service.dart';
import 'package:civiclens_mobile/services/report_api_service.dart';
import 'package:civiclens_mobile/state/report_repository.dart';
import 'package:civiclens_mobile/state/report_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Pumps until [finder] shows up without waiting for the tree to go quiet.
///
/// The submit button keeps its spinner running while the save dialog is open,
/// so [WidgetTester.pumpAndSettle] would never return there.
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<ReportRepository> _pumpForm(
  WidgetTester tester, {
  required ReportApiService api,
  String? token,
}) async {
  final repository = ReportRepository(
    store: FakeReportStore(),
    apiService: api,
    accessToken: () => token,
  );
  await repository.load();

  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ReportScope(
      repository: repository,
      child: MaterialApp(
        home: ReportIssueScreen(
          locationService: FakeLocationService(
            granted: true,
            deviceLocation: const DeviceLocation(
              latitude: 6.5244,
              longitude: 3.3792,
              accuracy: 8,
            ),
          ),
          placeSearchService: FakePlaceSearchService(
            addressLabel: 'Kulikawn, Aizawl',
          ),
          imagePicker: FakeImagePicker(file: fakePhoto()),
        ),
      ),
    ),
  );
  await _settle(tester);
  return repository;
}

/// Fills and submits the form the way a citizen would, leaving the
/// confirmation dialog on screen.
Future<void> _submitReport(WidgetTester tester) async {
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

  await tester.tap(find.text('Use my current location'));
  await _settle(tester);

  await tester.tap(find.text('Submit Report'));
}

void main() {
  testWidgets('a delivered report is confirmed as submitted', (
    WidgetTester tester,
  ) async {
    final api = FakeReportApiService();
    final repository = await _pumpForm(tester, api: api, token: 'token-1');

    await _submitReport(tester);
    await _waitFor(tester, find.text('Report submitted'));

    expect(find.text('Report submitted'), findsOneWidget);
    expect(find.textContaining('Report reference:'), findsOneWidget);
    expect(api.createCalls.single.token, 'token-1');
    expect(repository.reports.single.isServerBacked, isTrue);

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await _settle(tester);
  });

  testWidgets('an ambiguous delivery failure never claims nothing was sent', (
    WidgetTester tester,
  ) async {
    final api = FakeReportApiService(
      onCreate: ({required token, required report}) => throw ApiException(
        failure: ApiFailure.network,
        message: 'Could not reach the server. Check your connection.',
      ),
    );
    final repository = await _pumpForm(tester, api: api, token: 'token-1');

    await _submitReport(tester);
    await _waitFor(tester, find.textContaining('could not confirm'));

    // The request may have landed, so the app must not assert nothing was
    // sent; it points the citizen at My Reports instead. Nothing is shown as
    // submitted and the list stays empty.
    expect(find.textContaining('could not confirm'), findsOneWidget);
    expect(find.textContaining('Nothing was sent'), findsNothing);
    expect(find.text('Report submitted'), findsNothing);
    expect(repository.reportCount, 0);
  });

  testWidgets('a definite rejection is reported as not submitted', (
    WidgetTester tester,
  ) async {
    final api = FakeReportApiService(
      onCreate: ({required token, required report}) => throw ApiException(
        failure: ApiFailure.badRequest,
        message: 'The city rejected the report.',
      ),
    );
    final repository = await _pumpForm(tester, api: api, token: 'token-1');

    await _submitReport(tester);
    await _waitFor(
      tester,
      find.textContaining('Your report could not be submitted'),
    );

    expect(
      find.textContaining('Your report could not be submitted'),
      findsOneWidget,
    );
    expect(find.text('Report submitted'), findsNothing);
    expect(repository.reportCount, 0);
  });
}
