import 'dart:async';

import 'package:civiclens_mobile/models/civic_report.dart';
import 'package:civiclens_mobile/screens/my_reports_screen.dart';
import 'package:civiclens_mobile/screens/report_details_screen.dart';
import 'package:civiclens_mobile/services/api_client.dart';
import 'package:civiclens_mobile/state/auth_repository.dart';
import 'package:civiclens_mobile/state/auth_scope.dart';
import 'package:civiclens_mobile/state/report_repository.dart';
import 'package:civiclens_mobile/state/report_scope.dart';
import 'package:civiclens_mobile/widgets/report_status_chip.dart';
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

/// A report as the backend would return it: server origin and a real id.
CivicReport _serverReport(
  String id, {
  required String title,
  ReportStatus status = ReportStatus.inProgress,
  DateTime? createdAt,
}) => CivicReport(
  id: id,
  category: 'Pothole / Road Damage',
  title: title,
  description: 'Held by the city.',
  locationLabel: 'Aizawl',
  latitude: 23.74,
  longitude: 92.73,
  createdAt: createdAt ?? DateTime(2026, 1, 6, 12),
  status: status,
  origin: ReportOrigin.server,
  serverId: id,
);

/// An [AuthRepository] that is already signed in, with the repository wired to
/// it exactly as `main.dart` wires it. The repository is deliberately *not*
/// loaded here: the screen performs that first retrieval itself.
Future<({ReportRepository repository, AuthRepository auth})> _signedIn({
  required FakeReportApiService api,
}) async {
  final auth = buildAuthRepository(seeded: sessionWithToken(freshJwt()));
  await auth.restoreSession();
  final repository = ReportRepository(
    store: FakeReportStore(),
    apiService: api,
    accessToken: () => auth.token,
  );
  return (repository: repository, auth: auth);
}

/// An [AuthRepository] that is signed out, wired the same way.
Future<({ReportRepository repository, AuthRepository auth})> _signedOut({
  required FakeReportApiService api,
}) async {
  final auth = buildAuthRepository();
  await auth.restoreSession();
  final repository = ReportRepository(
    store: FakeReportStore(),
    apiService: api,
    accessToken: () => auth.token,
  );
  return (repository: repository, auth: auth);
}

Future<void> _pump(
  WidgetTester tester, {
  required ReportRepository repository,
  required AuthRepository auth,
  Size viewport = const Size(800, 1600),
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    AuthScope(
      auth: auth,
      child: ReportScope(
        repository: repository,
        child: const MaterialApp(home: MyReportsScreen()),
      ),
    ),
  );
}

void main() {
  testWidgets('a signed-in citizen fetches and lists server reports', (
    tester,
  ) async {
    final api = FakeReportApiService(
      onFetch: ({required String token, bool mine = false, String? district}) async => [
        _serverReport('srv-1', title: 'Pothole on Hill Road'),
      ],
    );
    final env = await _signedIn(api: api);

    await _pump(tester, repository: env.repository, auth: env.auth);
    await settleTree(tester);

    // The retrieval ran once, with the signed-in citizen's bearer token.
    expect(api.fetchCalls, hasLength(1));
    expect(api.fetchCalls.single.token, env.auth.token);

    // The server record is listed with the status the server reported.
    expect(find.text('Pothole on Hill Road'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(env.repository.reportCount, 1);
    expect(env.repository.findById('srv-1'), isNotNull);
  });

  testWidgets('an empty backend shows the empty state, not an error', (
    tester,
  ) async {
    final api = FakeReportApiService();
    final env = await _signedIn(api: api);

    await _pump(tester, repository: env.repository, auth: env.auth);
    await settleTree(tester);

    expect(find.text('No reports yet'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(env.repository.reportCount, 0);
  });

  testWidgets('a failed fetch explains itself and offers a retry', (
    tester,
  ) async {
    var attempts = 0;
    final api = FakeReportApiService(
      onFetch: ({required String token, bool mine = false, String? district}) async {
        attempts += 1;
        if (attempts == 1) {
          throw ApiException(
            failure: ApiFailure.network,
            message: 'No connection to the city right now.',
          );
        }
        return [_serverReport('srv-3', title: 'Clogged drain')];
      },
    );
    final env = await _signedIn(api: api);

    await _pump(tester, repository: env.repository, auth: env.auth);
    await settleTree(tester);

    expect(find.text('No connection to the city right now.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await settleTree(tester);

    expect(find.text('Clogged drain'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('No connection to the city right now.'), findsNothing);
    expect(attempts, 2);
  });

  testWidgets('while fetching, the retrieval is the whole state', (
    tester,
  ) async {
    final gate = Completer<List<CivicReport>>();
    final api = FakeReportApiService(
      onFetch: ({required String token, bool mine = false, String? district}) => gate.future,
    );
    final env = await _signedIn(api: api);

    await _pump(tester, repository: env.repository, auth: env.auth);
    // One frame for the build, one to apply the state set after it.
    await tester.pump();

    expect(find.text('Checking your reports with the city…'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsNothing);

    gate.complete([_serverReport('srv-5', title: 'Clogged drain')]);
    await settleTree(tester);

    expect(find.text('Checking your reports with the city…'), findsNothing);
    expect(find.text('Clogged drain'), findsOneWidget);
    expect(find.text('No reports yet'), findsNothing);
  });

  testWidgets('signed out, the backend is never called', (tester) async {
    final api = FakeReportApiService(
      onFetch: ({required String token, bool mine = false, String? district}) async => [
        _serverReport('srv-1', title: 'Should never appear'),
      ],
    );
    final env = await _signedOut(api: api);

    await _pump(tester, repository: env.repository, auth: env.auth);
    await settleTree(tester);

    expect(api.fetchCalls, isEmpty);
    expect(env.auth.status, AuthStatus.unauthenticated);
    expect(
      find.text('Sign in to see the reports you have submitted.'),
      findsOneWidget,
    );
    expect(find.text('Should never appear'), findsNothing);
  });

  testWidgets('pull to refresh asks the city again', (tester) async {
    var fetches = 0;
    final api = FakeReportApiService(
      onFetch: ({required String token, bool mine = false, String? district}) async {
        fetches += 1;
        final base = [
          for (var i = 0; i < 6; i++)
            _serverReport(
              'srv-$i',
              title: 'Civic report $i',
              createdAt: DateTime(2026, 1, 1).add(Duration(hours: i)),
            ),
        ];
        if (fetches == 1) return base;
        return [
          ...base,
          _serverReport(
            'srv-9',
            title: 'Newest on server',
            createdAt: DateTime(2026, 1, 9),
          ),
        ];
      },
    );
    final env = await _signedIn(api: api);

    // A short viewport so the fetched list overflows and can overscroll.
    await _pump(
      tester,
      repository: env.repository,
      auth: env.auth,
      viewport: const Size(800, 500),
    );
    await settleTree(tester);
    expect(api.fetchCalls, hasLength(1));
    expect(find.text('Newest on server'), findsNothing);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await settleTree(tester);

    expect(find.text('Newest on server'), findsOneWidget);
    expect(api.fetchCalls, hasLength(2));
  });

  testWidgets('a server report opens with its status and no invented history', (
    tester,
  ) async {
    final api = FakeReportApiService(
      onFetch: ({required String token, bool mine = false, String? district}) async => [
        _serverReport('srv-6', title: 'Pothole on Hill Road'),
      ],
    );
    final env = await _signedIn(api: api);

    await _pump(tester, repository: env.repository, auth: env.auth);
    await settleTree(tester);

    await tester.tap(find.text('Pothole on Hill Road'));
    await settleTree(tester);

    final details = find.byType(ReportDetailsScreen);
    expect(details, findsOneWidget);
    expect(
      find.descendant(of: details, matching: find.byType(ReportStatusChip)),
      findsOneWidget,
    );
    // The status shown is the server's own, with no invented local history.
    expect(
      find.descendant(
        of: details,
        matching: find.text('No status updates recorded yet.'),
      ),
      findsOneWidget,
    );
  });
}
