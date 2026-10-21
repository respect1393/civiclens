import 'dart:async';

import 'package:civiclens_mobile/main.dart';
import 'package:civiclens_mobile/services/api_client.dart';
import 'package:civiclens_mobile/state/report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth.dart';
import '../helpers/fake_report_store.dart';

/// Bounded settle, mirroring the other widget tests: a tree that schedules
/// frames forever must fail fast instead of hanging the run.
Future<void> settleTree(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

ApiException _unauthorized() => ApiException(
  failure: ApiFailure.unauthorized,
  message: 'Incorrect email or password.',
  statusCode: 401,
);

void main() {
  late ReportRepository repository;

  setUp(() async {
    repository = ReportRepository(store: FakeReportStore());
    await repository.load();
  });

  group('session restoration', () {
    testWidgets('holds a branded placeholder while the saved session is read', (
      WidgetTester tester,
    ) async {
      final store = FakeSessionStore()..gate = Completer<void>();
      final auth = buildAuthRepository(store: store);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await tester.pump();

      // The placeholder must not read as a separate "restoring your session"
      // page: it is the native launch screen carried over into Flutter, and it
      // must not flash the login screen or leave a blank surface either.
      expect(find.byKey(const Key('launch-placeholder')), findsOneWidget);
      expect(find.text('Restoring your session...'), findsNothing);
      expect(find.text('Welcome back'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);

      store.gate!.complete();
      await settleTree(tester);

      expect(find.byKey(const Key('launch-placeholder')), findsNothing);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('restoring before the first frame lands on the app', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      // `main()` awaits restoreSession() before runApp(), so a signed-in
      // citizen never sees the placeholder or a login flash on startup.
      final auth = buildAuthRepository(
        store: FakeSessionStore(sessionWithToken(freshJwt())),
      );
      await auth.restoreSession();

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      expect(find.byKey(const Key('launch-placeholder')), findsNothing);
      expect(find.text('Welcome back'), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('a saved session goes straight to the app, no login flash', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = buildAuthRepository(seeded: sessionWithToken(freshJwt()));

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);
    });

    testWidgets('an expired saved session lands on the login screen', (
      WidgetTester tester,
    ) async {
      final store = FakeSessionStore(sessionWithToken(expiredJwt()));
      final auth = buildAuthRepository(store: store);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      expect(find.text('Welcome back'), findsOneWidget);
      expect(store.session, isNull);
    });
  });

  group('sign in', () {
    testWidgets('rejects an empty form', (WidgetTester tester) async {
      final auth = buildAuthRepository();

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settleTree(tester);

      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
    });

    testWidgets('rejects a malformed email before calling the backend', (
      WidgetTester tester,
    ) async {
      final service = FakeAuthService();
      final auth = buildAuthRepository(service: service);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
      await tester.enterText(find.byType(TextFormField).at(1), 'sup3rsecret');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settleTree(tester);

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(service.loginCalls, isEmpty);
    });

    testWidgets('a good sign-in reveals the app and stores the session', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final store = FakeSessionStore();
      final auth = buildAuthRepository(store: store);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'asha.verma@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'sup3rsecret');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settleTree(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);
      expect(store.session, isNotNull);
      // The password never reaches storage.
      expect(
        store.session!.toJson().toString(),
        isNot(contains('sup3rsecret')),
      );
    });

    testWidgets('bad credentials show a banner and keep the citizen out', (
      WidgetTester tester,
    ) async {
      final service = FakeAuthService(
        onLogin: ({required email, required password}) =>
            Future.error(_unauthorized()),
      );
      final store = FakeSessionStore();
      final auth = buildAuthRepository(service: service, store: store);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'asha.verma@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settleTree(tester);

      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(store.session, isNull);
    });

    testWidgets('an unreachable backend explains itself instead of hanging', (
      WidgetTester tester,
    ) async {
      final service = FakeAuthService(
        onLogin: ({required email, required password}) => Future.error(
          ApiException(
            failure: ApiFailure.network,
            message: 'Could not reach the server. Check your connection and try again.',
          ),
        ),
      );
      final auth = buildAuthRepository(service: service);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'asha.verma@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'sup3rsecret');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settleTree(tester);

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });
  });

  group('registration', () {
    Future<void> openRegister(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(TextButton, 'Create an account'));
      await settleTree(tester);
    }

    testWidgets('is reachable from the login screen and validates its fields', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = buildAuthRepository();

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await openRegister(tester);
      expect(find.text('Create your account'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await settleTree(tester);

      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(find.text('Create a password.'), findsOneWidget);
      expect(find.text('Select your state.'), findsOneWidget);
      expect(find.text('Enter your district.'), findsOneWidget);
    });

    testWidgets('a short password and mismatched confirmation are rejected', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final service = FakeAuthService();
      final auth = buildAuthRepository(service: service);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);
      await openRegister(tester);

      await tester.enterText(find.byType(TextFormField).at(2), 'short');
      await tester.enterText(find.byType(TextFormField).at(3), 'different');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await settleTree(tester);

      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(service.registerCalls, isEmpty);
    });

    testWidgets('the back control returns to sign in without a request', (
      WidgetTester tester,
    ) async {
      final service = FakeAuthService();
      final auth = buildAuthRepository(service: service);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);
      await openRegister(tester);

      await tester.tap(find.byTooltip('Back to sign in'));
      await settleTree(tester);

      expect(find.text('Welcome back'), findsOneWidget);
      expect(service.registerCalls, isEmpty);
    });

    testWidgets('a complete form signs the citizen in', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final store = FakeSessionStore();
      final service = FakeAuthService();
      final auth = buildAuthRepository(service: service, store: store);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);
      await openRegister(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Asha Verma');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'asha.verma@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'sup3rsecret');
      await tester.enterText(find.byType(TextFormField).at(3), 'sup3rsecret');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await settleTree(tester);
      await tester.tap(find.text('Andhra Pradesh').last);
      await settleTree(tester);
      await tester.enterText(find.byType(TextFormField).at(4), 'Visakhapatnam');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await settleTree(tester);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Create your account'), findsNothing);
      expect(store.session, isNotNull);
      expect(service.registerCalls.single.state, 'Andhra Pradesh');
      expect(service.registerCalls.single.district, 'Visakhapatnam');
    });

    testWidgets('a duplicate email is highlighted on the email field', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final service = FakeAuthService(
        onRegister:
            ({
              required name,
              required email,
              required password,
              required state,
              required district,
            }) => Future.error(
              ApiException(
                failure: ApiFailure.badRequest,
                message: 'An account with this email already exists.',
                statusCode: 400,
                fieldErrors: const {
                  'email': 'This email is already registered.',
                },
              ),
            ),
      );
      final auth = buildAuthRepository(service: service);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);
      await openRegister(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'Asha Verma');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'taken@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'sup3rsecret');
      await tester.enterText(find.byType(TextFormField).at(3), 'sup3rsecret');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await settleTree(tester);
      await tester.tap(find.text('Andhra Pradesh').last);
      await settleTree(tester);
      await tester.enterText(find.byType(TextFormField).at(4), 'Visakhapatnam');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await settleTree(tester);

      expect(
        find.text('An account with this email already exists.'),
        findsOneWidget,
      );
      expect(find.text('This email is already registered.'), findsOneWidget);
      expect(find.text('Create your account'), findsOneWidget);
    });
  });

  group('sign out', () {
    testWidgets('Profile shows the account and signing out returns to login', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final store = FakeSessionStore(sessionWithToken(freshJwt()));
      final auth = buildAuthRepository(store: store);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await settleTree(tester);

      // The header carries the citizen's identity in one place: picture,
      // name, district and state, plus the account email.
      expect(find.text('Asha Verma'), findsOneWidget);
      expect(find.text('Bengaluru Urban, Karnataka'), findsOneWidget);
      expect(find.text('asha.verma@example.com'), findsOneWidget);
      expect(find.byKey(const Key('profile-default-avatar')), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await settleTree(tester);

      // Confirmation is required: nothing is cleared until it is accepted.
      expect(find.text('Sign out?'), findsOneWidget);
      expect(store.session, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
      await settleTree(tester);

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(store.session, isNull);
    });

    testWidgets('cancelling the confirmation keeps the citizen signed in', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final store = FakeSessionStore(sessionWithToken(freshJwt()));
      final auth = buildAuthRepository(store: store);

      await tester.pumpWidget(CivicLensApp(repository: repository, auth: auth));
      await settleTree(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Profile'),
        ),
      );
      await settleTree(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
      await settleTree(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settleTree(tester);

      expect(find.text('Welcome back'), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(store.session, isNotNull);
    });
  });
}
