import 'dart:math' as math;

import 'package:civiclens_mobile/models/civic_report.dart';
import 'package:civiclens_mobile/widgets/status_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Color _teal = Color(0xFF13B8A6);

CivicReport _report(ReportStatus status) {
  return CivicReport(
    id: 'CL-TEST-0001',
    category: 'Water Supply',
    title: 'Leak in pipe',
    description: 'Water is leaking onto the road next to the junction.',
    locationLabel: 'Main Street',
    latitude: 6.5244,
    longitude: 3.3792,
    createdAt: DateTime(2026, 1, 1, 9),
    status: status,
    statusHistory: [
      StatusEvent(status: status, timestamp: DateTime(2026, 1, 1, 9)),
    ],
  );
}

/// Pumps the timeline inside the same padding the details screen uses
/// (20px list padding + 16px panel padding), on a narrow 320px phone.
Future<void> _pumpTimeline(WidgetTester tester, CivicReport report) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(36),
          children: [StatusTimeline(report: report)],
        ),
      ),
    ),
  );

  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

List<Rect> _nodeRects(WidgetTester tester) {
  return [
    for (var i = 0; i < ReportStatus.pipeline.length; i++)
      tester.getRect(find.byKey(ValueKey('status-node-$i'))),
  ];
}

Color? _nodeColor(WidgetTester tester, int index) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey('status-node-$index')),
  );
  return (container.decoration! as BoxDecoration).color;
}

Color? _connectorColor(WidgetTester tester, String side, int index) {
  final container = tester.widget<Container>(
    find.byKey(ValueKey('status-connector-$index-$side')),
  );
  return container.color;
}

void main() {
  testWidgets(
    'every stage circle shares one horizontal centerline and is evenly spaced',
    (WidgetTester tester) async {
      await _pumpTimeline(tester, _report(ReportStatus.inProgress));

      final nodes = _nodeRects(tester);

      // A one-line label ("Reported") and a two-line label ("In Progress")
      // used to give the cells different heights, which let the default
      // Row alignment push circles onto different centerlines.
      final centerlines = nodes.map((rect) => rect.center.dy).toList();
      final spread =
          centerlines.reduce(math.max) - centerlines.reduce(math.min);
      expect(spread, lessThan(0.01), reason: 'circles must share a centerline');

      // Equal-width cells make the gaps between circle centres identical.
      final xs = nodes.map((rect) => rect.center.dx).toList();
      final gaps = [for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1]];
      for (final gap in gaps) {
        expect(
          (gap - gaps.first).abs(),
          lessThan(0.01),
          reason: 'stages must be evenly spaced, gaps were $gaps',
        );
      }

      // The connector must be the same height everywhere and sit on the same
      // centerline as the circles it joins.
      for (var i = 0; i < ReportStatus.pipeline.length; i++) {
        final left = tester.getRect(
          find.byKey(ValueKey('status-connector-$i-left')),
        );
        expect(left.center.dy, closeTo(nodes.first.center.dy, 0.01));
        expect(left.height, 3);
      }
    },
  );

  testWidgets('labels stay centered beneath their circles when they wrap', (
    WidgetTester tester,
  ) async {
    // 320px is narrow enough for "Under Review" and "In Progress" to wrap.
    await _pumpTimeline(tester, _report(ReportStatus.inProgress));

    expect(tester.takeException(), isNull);

    final nodes = _nodeRects(tester);

    for (var i = 0; i < ReportStatus.pipeline.length; i++) {
      final label = tester.getRect(find.byKey(ValueKey('status-label-$i')));

      expect(
        (label.center.dx - nodes[i].center.dx).abs(),
        lessThan(0.6),
        reason: '${ReportStatus.pipeline[i].label} must sit under its circle',
      );

      // Wrapping must never move the node row itself.
      expect(nodes[i].height, 18);
      expect(label.top, greaterThanOrEqualTo(nodes[i].bottom - 0.01));
    }
  });

  testWidgets('no clipping or horizontal overflow on a narrow phone', (
    WidgetTester tester,
  ) async {
    await _pumpTimeline(tester, _report(ReportStatus.resolved));

    expect(tester.takeException(), isNull);
    expect(find.byType(StatusTimeline), findsOneWidget);

    for (var i = 0; i < ReportStatus.pipeline.length; i++) {
      final node = tester.getRect(find.byKey(ValueKey('status-node-$i')));
      expect(node.left, greaterThanOrEqualTo(0));
      expect(node.right, lessThanOrEqualTo(320));
    }
  });

  testWidgets('a new report highlights only the first stage', (
    WidgetTester tester,
  ) async {
    await _pumpTimeline(tester, _report(ReportStatus.reported));

    expect(_nodeColor(tester, 0), _teal);
    for (var i = 1; i < ReportStatus.pipeline.length; i++) {
      expect(_nodeColor(tester, i), Colors.white);
    }

    // The track after the first circle is still empty.
    expect(_connectorColor(tester, 'right', 0), isNot(_teal));
  });

  testWidgets('an in-progress report fills the track up to its circle', (
    WidgetTester tester,
  ) async {
    await _pumpTimeline(tester, _report(ReportStatus.inProgress));

    for (var i = 0; i <= 3; i++) {
      expect(_nodeColor(tester, i), _teal);
    }
    expect(_nodeColor(tester, 4), Colors.white);

    expect(_connectorColor(tester, 'right', 2), _teal);
    expect(_connectorColor(tester, 'right', 3), isNot(_teal));
  });

  testWidgets('a resolved report fills the whole track', (
    WidgetTester tester,
  ) async {
    await _pumpTimeline(tester, _report(ReportStatus.resolved));

    for (var i = 0; i < ReportStatus.pipeline.length; i++) {
      expect(_nodeColor(tester, i), _teal);
    }

    expect(_connectorColor(tester, 'right', 4), _teal);
  });

  testWidgets('the side branch keeps the timeline at the first stage', (
    WidgetTester tester,
  ) async {
    await _pumpTimeline(tester, _report(ReportStatus.needsMoreInformation));

    expect(_nodeColor(tester, 0), _teal);
    expect(_nodeColor(tester, 1), Colors.white);
    expect(
      find.text('More information has been requested for this report.'),
      findsOneWidget,
    );
  });
}
