import 'package:flutter/widgets.dart';

import 'report_repository.dart';

/// Exposes a [ReportRepository] to the widget tree and rebuilds dependents
/// whenever the repository notifies a change.
class ReportScope extends InheritedNotifier<ReportRepository> {
  const ReportScope({
    super.key,
    required ReportRepository repository,
    required super.child,
  }) : super(notifier: repository);

  static ReportRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ReportScope>();
    assert(scope != null, 'No ReportScope found in the widget tree.');
    return scope!.notifier!;
  }

  /// Reads the repository without subscribing to rebuilds.
  static ReportRepository read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ReportScope>();
    assert(scope != null, 'No ReportScope found in the widget tree.');
    return scope!.notifier!;
  }
}
