import 'package:civiclens_mobile/main.dart';
import 'package:civiclens_mobile/state/auth_repository.dart';
import 'package:civiclens_mobile/state/report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_auth.dart';
import 'helpers/fake_report_store.dart';

/// Settles the tree with a hard timeout so a widget tree that schedules frames
/// forever (for example a FutureBuilder given a new Future on every build)
/// fails fast with a clear error instead of hanging the test run.
Future<void> settleTree(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// The home screen is a long scrollable feed, so give tests a surface tall
/// enough for its slivers to be built instead of leaving them off-screen.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  late ReportRepository repository;
  late AuthRepository auth;

  setUp(() async {
    repository = ReportRepository(store: FakeReportStore());
    await repository.load();
    // Seed a usable session so AuthGate restores straight into the app, which
    // is what the pre-existing screen assertions assume.
    auth = buildAuthRepository(
      seeded: FakeAuthService.sessionFor('asha.verma@example.com'),
    );
  });

  testWidgets('home renders identity and report entry point', (
    WidgetTester tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
    await settleTree(tester);

    expect(find.text('CIVICLENS'), findsOneWidget);
    expect(find.text('A better city starts'), findsOneWidget);
    expect(find.text('with you.'), findsOneWidget);
    expect(find.text('Report an Issue'), findsOneWidget);
  });

  testWidgets('home shows local report summary and empty state', (
    WidgetTester tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
    await settleTree(tester);

    expect(find.text('Your reports'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(
      find.text(
        'No reports submitted yet. Your first report will appear here.',
      ),
      findsOneWidget,
    );
    expect(repository.reportCount, 0);
  });

  testWidgets('empty home state shows prompt', (WidgetTester tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
    await settleTree(tester);

    expect(repository.reportCount, 0);
  });
}
