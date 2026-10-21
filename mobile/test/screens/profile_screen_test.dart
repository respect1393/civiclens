import 'dart:io';

import 'package:civiclens_mobile/models/auth_session.dart';
import 'package:civiclens_mobile/models/auth_user.dart';
import 'package:civiclens_mobile/screens/profile_screen.dart';
import 'package:civiclens_mobile/services/profile_store.dart';
import 'package:civiclens_mobile/state/auth_repository.dart';
import 'package:civiclens_mobile/state/auth_scope.dart';
import 'package:civiclens_mobile/state/report_repository.dart';
import 'package:civiclens_mobile/state/report_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../helpers/fake_auth.dart';
import '../helpers/fake_image_picker.dart';
import '../helpers/fake_profile_store.dart';
import '../helpers/fake_report_store.dart';

/// A valid 1x1 transparent PNG, so the avatar can point at a real file that
/// the image decoder accepts if it ever gets the chance to run.
final List<int> _onePixelPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

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

Future<void> flushSnackBarTimer(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await settleTree(tester);
}

/// A picker that fails the way a device with no camera access would.
class _ThrowingImagePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async => throw StateError('No picker is available on this device.');
}

void main() {
  late ReportRepository repository;
  late Directory tempDir;
  late File avatarFile;

  setUp(() async {
    repository = ReportRepository(store: FakeReportStore());
    await repository.load();

    // Real I/O must happen outside the widget test's fake-async zone, where
    // dart:io futures never complete.
    tempDir = await Directory.systemTemp.createTemp('civiclens_profile_test');
    avatarFile = File('${tempDir.path}/avatar.png');
    await avatarFile.writeAsBytes(_onePixelPng);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<AuthRepository> authWith(AuthSession session) async {
    final auth = buildAuthRepository(store: FakeSessionStore(session));
    await auth.restoreSession();
    return auth;
  }

  Future<void> pumpProfile(
    WidgetTester tester, {
    required AuthRepository auth,
    required ProfileStore profileStore,
    ImagePicker? imagePicker,
  }) async {
    await tester.pumpWidget(
      AuthScope(
        auth: auth,
        child: ReportScope(
          repository: repository,
          child: MaterialApp(
            home: ProfileScreen(
              profileStore: profileStore,
              imagePicker: imagePicker,
            ),
          ),
        ),
      ),
    );
    await settleTree(tester);
  }

  group('profile header', () {
    testWidgets('shows the citizen picture, name and location', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = await authWith(sessionWithToken(freshJwt()));

      await pumpProfile(
        tester,
        auth: auth,
        profileStore: FakeProfileStore(),
        imagePicker: FakeImagePicker(),
      );

      // Identity is presented once, at the top: picture, name, district/state.
      expect(find.byKey(const Key('profile-default-avatar')), findsOneWidget);
      expect(find.text('Asha Verma'), findsOneWidget);
      expect(find.text('Bengaluru Urban, Karnataka'), findsOneWidget);
      expect(find.text('asha.verma@example.com'), findsOneWidget);

      // The old branding block and the redundant account-details card are gone.
      expect(find.text('CIVICLENS'), findsNothing);
      expect(find.text('Name'), findsNothing);
      expect(find.text('Email'), findsNothing);
      expect(find.text('Not set'), findsNothing);
    });

    testWidgets('handles an account with no district or state', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = await authWith(
        const AuthSession(
          token: 'test-token',
          user: AuthUser(
            id: 'user-9',
            name: 'Ravi Kumar',
            email: 'ravi@example.com',
          ),
        ),
      );

      await pumpProfile(
        tester,
        auth: auth,
        profileStore: FakeProfileStore(),
        imagePicker: FakeImagePicker(),
      );

      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Location not set'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers sign out and no local admin controls', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = await authWith(sessionWithToken(freshJwt()));

      await pumpProfile(
        tester,
        auth: auth,
        profileStore: FakeProfileStore(),
        imagePicker: FakeImagePicker(),
      );

      expect(find.text('Signed in on this device'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Sign out'), findsOneWidget);
      // The local admin demo and device-report count are gone: reports live
      // with the backend now.
      expect(find.text('Open admin demo mode'), findsNothing);
      expect(find.text('Reports saved on this device'), findsNothing);
    });
  });

  group('profile picture', () {
    testWidgets('shows a saved picture instead of the default avatar', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = await authWith(sessionWithToken(freshJwt()));

      await pumpProfile(
        tester,
        auth: auth,
        profileStore: FakeProfileStore(initialAvatar: avatarFile),
        imagePicker: FakeImagePicker(),
      );

      expect(find.byKey(const Key('profile-avatar-image')), findsOneWidget);
      expect(find.byKey(const Key('profile-default-avatar')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unreadable picture reference falls back to the default', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = await authWith(sessionWithToken(freshJwt()));
      final profileStore = FakeProfileStore()..failReads = true;

      await pumpProfile(
        tester,
        auth: auth,
        profileStore: profileStore,
        imagePicker: FakeImagePicker(),
      );

      expect(find.byKey(const Key('profile-default-avatar')), findsOneWidget);
      expect(find.byKey(const Key('profile-avatar-image')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Edit pill opens the picker and saves a chosen picture', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = await authWith(sessionWithToken(freshJwt()));
      final profileStore = FakeProfileStore();
      final picker = FakeImagePicker(file: fakePhoto(name: 'portrait.png'));

      await pumpProfile(
        tester,
        auth: auth,
        profileStore: profileStore,
        imagePicker: picker,
      );

      await tester.tap(find.widgetWithText(InkWell, 'Edit'));
      await settleTree(tester);
      expect(find.text('Choose from gallery'), findsOneWidget);

      await tester.tap(find.text('Choose from gallery'));
      await settleTree(tester);

      expect(picker.pickCalls, 1);
      expect(profileStore.saveCount, 1);
      // Only the reference is kept; the picture itself lives in its own file.
      expect(profileStore.avatar!.path, endsWith('avatar.png'));
      expect(find.byKey(const Key('profile-avatar-image')), findsOneWidget);
      expect(find.byKey(const Key('profile-default-avatar')), findsNothing);
    });

    testWidgets('backing out of the picker keeps the current picture', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = await authWith(sessionWithToken(freshJwt()));
      final profileStore = FakeProfileStore();
      final picker = FakeImagePicker(file: null);

      await pumpProfile(
        tester,
        auth: auth,
        profileStore: profileStore,
        imagePicker: picker,
      );

      await tester.tap(find.widgetWithText(InkWell, 'Edit'));
      await settleTree(tester);
      await tester.tap(find.text('Choose from gallery'));
      await settleTree(tester);

      expect(picker.pickCalls, 1);
      expect(profileStore.saveCount, 0);
      expect(profileStore.avatar, isNull);
      expect(find.byKey(const Key('profile-default-avatar')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing picker keeps the picture and explains why', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = await authWith(sessionWithToken(freshJwt()));
      final profileStore = FakeProfileStore(initialAvatar: avatarFile);

      await pumpProfile(
        tester,
        auth: auth,
        profileStore: profileStore,
        imagePicker: _ThrowingImagePicker(),
      );

      await tester.tap(find.widgetWithText(InkWell, 'Edit'));
      await settleTree(tester);
      await tester.tap(find.text('Choose from gallery'));
      await settleTree(tester);

      expect(
        find.text('Could not update your profile picture. Please try again.'),
        findsOneWidget,
      );
      // The previous picture survived the failure.
      expect(find.byKey(const Key('profile-avatar-image')), findsOneWidget);
      expect(profileStore.saveCount, 0);

      await flushSnackBarTimer(tester);
    });

    testWidgets('a failed save keeps the current picture and explains why', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = await authWith(sessionWithToken(freshJwt()));
      final profileStore = FakeProfileStore()..failWrites = true;
      final picker = FakeImagePicker(file: fakePhoto());

      await pumpProfile(
        tester,
        auth: auth,
        profileStore: profileStore,
        imagePicker: picker,
      );

      await tester.tap(find.widgetWithText(InkWell, 'Edit'));
      await settleTree(tester);
      await tester.tap(find.text('Choose from gallery'));
      await settleTree(tester);

      expect(profileStore.saveCount, 0);
      expect(
        find.text('Could not update your profile picture. Please try again.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('profile-default-avatar')), findsOneWidget);

      await flushSnackBarTimer(tester);
    });

    testWidgets('removing the picture returns to the default avatar', (
      WidgetTester tester,
    ) async {
      useTallSurface(tester);
      final auth = await authWith(sessionWithToken(freshJwt()));
      final profileStore = FakeProfileStore(initialAvatar: avatarFile);

      await pumpProfile(
        tester,
        auth: auth,
        profileStore: profileStore,
        imagePicker: FakeImagePicker(),
      );

      expect(find.byKey(const Key('profile-avatar-image')), findsOneWidget);

      await tester.tap(find.widgetWithText(InkWell, 'Edit'));
      await settleTree(tester);
      await tester.tap(find.text('Remove picture'));
      await settleTree(tester);

      expect(profileStore.clearCount, 1);
      expect(profileStore.avatar, isNull);
      expect(find.byKey(const Key('profile-default-avatar')), findsOneWidget);
      expect(find.byKey(const Key('profile-avatar-image')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
