import 'package:civiclens_mobile/models/civic_report.dart';
import 'package:civiclens_mobile/screens/report_details_screen.dart';
import 'package:civiclens_mobile/state/report_repository.dart';
import 'package:civiclens_mobile/state/report_scope.dart';
import 'package:civiclens_mobile/widgets/report_saved_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_report_api_service.dart';
import '../helpers/fake_report_store.dart';

CivicReport _buildReport() {
  return CivicReport(
    id: 'CL-TEST-0042',
    category: 'Pothole / Road Damage',
    title: 'Large pothole near the junction',
    description: 'Deep pothole that damages cars at night.',
    locationLabel: 'Main Street',
    latitude: 6.5244,
    longitude: 3.3792,
    createdAt: DateTime(2026, 1, 2, 10),
  );
}

/// Reproduces the real stack: home -> report form -> success dialog, with the
/// repository available so the details screen can resolve the report.
///
/// Returns the report that was actually persisted.
Future<CivicReport> _pumpFlow(WidgetTester tester) async {
  final seed = _buildReport();
  final repository = ReportRepository(
    store: FakeReportStore(),
    apiService: FakeReportApiService(),
    accessToken: () => 'test-token',
  );
  await repository.load();

  // Tall surface so the report ID panel below the fold is laid out.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await repository.submitReport(
    category: seed.category,
    title: seed.title,
    description: seed.description,
    locationLabel: seed.locationLabel,
    latitude: seed.latitude,
    longitude: seed.longitude,
  );

  await tester.pumpWidget(
    ReportScope(
      repository: repository,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Builder(
                      builder: (formContext) => Center(
                        child: FilledButton(
                          onPressed: () => showReportSavedDialog(
                            formContext,
                            repository.reports.first,
                          ),
                          child: const Text('Submit Report'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Report an Issue'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  await tester.tap(find.text('Report an Issue'));
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  await tester.tap(find.text('Submit Report'));
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );

  return repository.reports.first;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

void main() {
  testWidgets('Close dismisses the dialog and returns to the previous screen', (
    WidgetTester tester,
  ) async {
    await _pumpFlow(tester);

    expect(find.text('Report submitted'), findsOneWidget);
    expect(find.text('Submit Report'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await _settle(tester);

    expect(find.text('Report submitted'), findsNothing);
    // The report form itself must be gone, not just the dialog.
    expect(find.text('Submit Report'), findsNothing);
    expect(find.text('Report an Issue'), findsOneWidget);
  });

  testWidgets(
    'View report opens the details of the report that was just saved',
    (WidgetTester tester) async {
      final report = await _pumpFlow(tester);

      await tester.tap(find.text('View report'));
      await _settle(tester);

      expect(find.text('Report submitted'), findsNothing);
      // The form must not be left underneath the details screen.
      expect(find.text('Submit Report'), findsNothing);

      expect(find.text('Report details'), findsOneWidget);
      expect(find.text(report.id), findsOneWidget);
      expect(find.text('Large pothole near the junction'), findsOneWidget);

      // Exactly one details route, even after the animation settled.
      expect(find.byType(ReportDetailsScreen), findsOneWidget);
    },
  );

  testWidgets('the dialog reports the identifier of the saved report', (
    WidgetTester tester,
  ) async {
    final report = await _pumpFlow(tester);

    expect(find.text('Report reference: ${report.id}'), findsOneWidget);
  });
}
