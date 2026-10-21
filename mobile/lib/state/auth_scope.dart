import 'package:flutter/widgets.dart';

import 'auth_repository.dart';

/// Exposes the [AuthRepository] to the widget tree and rebuilds dependents
/// whenever the authentication status changes.
///
/// Mirrors [ReportScope] so the app keeps a single, familiar pattern for
/// app-wide state.
class AuthScope extends InheritedNotifier<AuthRepository> {
  const AuthScope({
    super.key,
    required AuthRepository auth,
    required super.child,
  }) : super(notifier: auth);

  /// Reads the repository and subscribes to its changes.
  static AuthRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'No AuthScope found in the widget tree.');
    return scope!.notifier!;
  }

  /// Reads the repository without subscribing to rebuilds.
  static AuthRepository read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'No AuthScope found in the widget tree.');
    return scope!.notifier!;
  }
}
