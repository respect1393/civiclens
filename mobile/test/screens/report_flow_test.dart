import 'package:civiclens_mobile/main.dart';
import 'package:civiclens_mobile/models/civic_report.dart';
import 'package:civiclens_mobile/services/api_client.dart';
import 'package:civiclens_mobile/state/auth_repository.dart';
import 'package:civiclens_mobile/state/report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth.dart';
import '../helpers/fake_report_api_service.dart';
import '../helpers/fake_report_store.dart';

/// See widget_test.dart: bounded settle so runaway frame scheduling fails fast.
Future<void> settleTree(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// Lets a SnackBar's auto-dismiss timer fire so no fake timer is left pending
/// at the end of a test.
Future<void> flushSnackBarTimer(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await settleTree(tester);
}

/// Taps a bottom-navigation destination by its label inside the NavigationBar.
Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settleTree(tester);
}

/// A report as the backend would return it: server origin and a real id.
CivicReport _serverReport(
  String id, {
  required String title,
  String category = 'Water Supply',
  ReportStatus status = ReportStatus.reported,
  DateTime? createdAt,
}) => CivicReport(
  id: id,
  category: category,
  title: title,
  description: 'Continuous water leak near the street.',
  locationLabel: 'Main Road',
  latitude: 12.0,
  longitude: 77.0,
  createdAt: createdAt ?? DateTime(2026, 1, 2, 10),
  status: status,
  origin: ReportOrigin.server,
  serverId: id,
);

void main() {
  late FakeReportApiService api;
  late ReportRepository repository;
  late AuthRepository auth;

  setUp(() async {
    api = FakeReportApiService();
    repository = ReportRepository(
      store: FakeReportStore(),
      apiService: api,
      accessToken: () => 'test-token',
    );
    // Seeded session so AuthGate restores into the app instead of the login
    // screen; these tests cover the report flow, not authentication.
    auth = buildAuthRepository(
      seeded: FakeAuthService.sessionFor('asha.verma@example.com'),
    );
  });

  testWidgets('report form validates required fields and photo evidence', (
    WidgetTester tester,
  ) async {
    // Tall surface so the whole form is on screen without scrolling.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
    await settleTree(tester);

    await tester.tap(find.text('Report an Issue').first);
    await settleTree(tester);
    expect(find.text('Report an Issue'), findsOneWidget);

    // 1. Empty form rejects the missing category.
    await tester.tap(find.text('Submit Report'));
    await settleTree(tester);
    expect(find.text('Please select a category.'), findsOneWidget);
    expect(repository.reportCount, 0);

    // 2. Category + title + description are accepted, photo is still required.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settleTree(tester);
    await tester.tap(find.text('Pothole / Road Damage').last);
    await settleTree(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Large pothole');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'A very deep pothole causing serious risk to cyclists and vehicles.',
    );

    await tester.tap(find.text('Submit Report'));
    await settleTree(tester);
    expect(
      find.text('Please attach at least one photo as evidence.'),
      findsOneWidget,
    );
    // Nothing was persisted because validation did not pass.
    expect(repository.reportCount, 0);
    expect(find.text('Report submitted'), findsNothing);

    await flushSnackBarTimer(tester);
  });

  testWidgets('My Reports shows an empty state before any submission', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
    await settleTree(tester);

    await _selectTab(tester, 'My Reports');

    expect(find.text('No reports yet'), findsOneWidget);
    expect(repository.reportCount, 0);
  });

  group('with a report held by the city', () {
    setUp(() {
      api.onFetch = ({required String token, bool mine = false, String? district}) async => [
        _serverReport('srv-1', title: 'Leak in pipe'),
      ];
    });

    testWidgets('the fetched report appears in My Reports', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await _selectTab(tester, 'My Reports');

      expect(find.text('Leak in pipe'), findsOneWidget);
      expect(find.text('WATER SUPPLY'), findsOneWidget);
      expect(find.text('Reported'), findsOneWidget);
      expect(repository.reportCount, 1);
      expect(api.fetchCalls, hasLength(1));
    });

    testWidgets('report details show id, location and status timeline', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await _selectTab(tester, 'My Reports');
      await tester.tap(find.text('Leak in pipe'));
      await settleTree(tester);

      expect(find.text('Report details'), findsOneWidget);
      expect(find.text('REPORT ID'), findsOneWidget);
      expect(find.text(repository.reports.first.id), findsOneWidget);
      expect(find.text('STATUS HISTORY'), findsOneWidget);
      expect(find.text('No status updates recorded yet.'), findsOneWidget);
    });
  });

  group('deleting a server report', () {
    setUp(() {
      api.onFetch = ({required String token, bool mine = false, String? district}) async => [
        _serverReport('srv-1', title: 'Leak in pipe'),
      ];
    });

    /// Opens the details screen for the fetched report.
    Future<void> openDetails(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await _selectTab(tester, 'My Reports');
      await tester.tap(find.text('Leak in pipe'));
      await settleTree(tester);
      expect(find.text('Report details'), findsOneWidget);
    }

    /// Brings the delete control at the bottom of the list into view.
    Future<void> revealDeleteButton(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Delete Report'));
      await settleTree(tester);
    }

    testWidgets('cancelling the confirmation keeps the report', (
      WidgetTester tester,
    ) async {
      await openDetails(tester);
      await revealDeleteButton(tester);

      await tester.tap(find.text('Delete Report'));
      await settleTree(tester);

      expect(find.text('Delete this report?'), findsOneWidget);
      expect(find.textContaining('Leak in pipe'), findsWidgets);
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await settleTree(tester);

      expect(find.text('Delete this report?'), findsNothing);
      expect(find.text('Report details'), findsOneWidget);
      expect(repository.reportCount, 1);
      expect(api.deleteCalls, isEmpty);
    });

    testWidgets('confirming the delete removes the report', (
      WidgetTester tester,
    ) async {
      await openDetails(tester);
      await revealDeleteButton(tester);

      await tester.tap(find.text('Delete Report'));
      await settleTree(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settleTree(tester);

      expect(api.deleteCalls.single.reportId, 'srv-1');
      expect(repository.reportCount, 0);
      // The citizen lands back on an honest empty list.
      expect(find.text('Report details'), findsNothing);
      expect(find.text('No reports yet'), findsOneWidget);
      expect(find.text('Report deleted'), findsOneWidget);

      await flushSnackBarTimer(tester);
    });

    testWidgets('a failed delete keeps the report and explains why', (
      WidgetTester tester,
    ) async {
      api.onDelete = ({required String token, required String reportId}) async {
        throw ApiException(
          failure: ApiFailure.forbidden,
          message: 'You are not allowed to delete this report.',
        );
      };

      await openDetails(tester);
      await revealDeleteButton(tester);

      await tester.tap(find.text('Delete Report'));
      await settleTree(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settleTree(tester);

      expect(
        find.text(
          "Could not delete this report. It is still on the city's records.",
        ),
        findsOneWidget,
      );
      // Still on the details screen with the report untouched.
      expect(find.text('Report details'), findsOneWidget);
      expect(repository.reportCount, 1);

      await flushSnackBarTimer(tester);
    });
  });
}
