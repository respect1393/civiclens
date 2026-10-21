import 'dart:async';

import 'package:flutter/material.dart';

import '../state/auth_repository.dart';
import '../state/auth_scope.dart';
import 'login_screen.dart';

const Color _navy = Color(0xFF102A43);
const Color _teal = Color(0xFF13B8A6);

/// Chooses between the launch placeholder, the login screen and the existing
/// application.
///
/// * `checking` → [LaunchPlaceholder],
/// * `unauthenticated` → [LoginScreen],
/// * `authenticated` → the existing `HomeScreen`.
///
/// In normal startup `checking` never reaches the screen: `main()` restores
/// the session *before* `runApp`, so the first frame is already either the
/// signed-in app or [LoginScreen] and Android's launch screen covers the whole
/// read. [LaunchPlaceholder] therefore exists only as a non-blank safety net
/// for a status that is still resolving, and it is painted to look exactly
/// like that native launch screen.
///
/// Because the whole subtree is swapped rather than pushed, signing out
/// discards every route that was opened while signed in: the back button can
/// never return to an authenticated screen.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.authenticatedHome});

  /// The existing application, shown once a session exists.
  final Widget authenticatedHome;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthRepository? _auth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `of` (not `read`) so this gate rebuilds when the status changes.
    _auth ??= AuthScope.of(context);
    // Idempotent inside AuthRepository: only the first call does the work, so
    // rebuilds and hot restarts can never race or restore twice. It is a no-op
    // when `main` already restored the session before the first frame.
    unawaited(_auth!.restoreSession());
  }

  @override
  Widget build(BuildContext context) {
    return switch (AuthScope.of(context).status) {
      AuthStatus.checking => const LaunchPlaceholder(),
      AuthStatus.unauthenticated => const LoginScreen(),
      AuthStatus.authenticated => widget.authenticatedHome,
    };
  }
}

/// Holds the screen while the session status is still being resolved.
///
/// Visually identical to Android's launch screen (navy field, centred brand
/// mark) so that even if it does appear it is indistinguishable from the
/// native splash instead of reading as a separate page. Deliberately static —
/// no spinner, no "Restoring your session..." copy and no movement — so it can
/// never animate forever or fail to settle.
class LaunchPlaceholder extends StatelessWidget {
  const LaunchPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      key: Key('launch-placeholder'),
      backgroundColor: _navy,
      body: Center(
        child: Icon(Icons.location_city_rounded, color: _teal, size: 72),
      ),
    );
  }
}
