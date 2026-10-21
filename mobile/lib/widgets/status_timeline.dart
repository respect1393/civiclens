import 'package:flutter/material.dart';

import '../models/civic_report.dart';
import '../utils/report_format.dart';
import 'report_status_chip.dart';

const Color _navy = Color(0xFF102A43);
const Color _teal = Color(0xFF13B8A6);
const Color _muted = Color(0xFF627D98);
const Color _border = Color(0xFFE4EAF0);

/// Diameter of a stage circle. The node row keeps this height so wrapping
/// labels below cannot move the circles or the connecting line.
const double _nodeSize = 18;

/// Horizontal progress indicator across the main status pipeline plus the
/// recorded history with timestamps.
class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.report});

  final CivicReport report;

  @override
  Widget build(BuildContext context) {
    final pipeline = ReportStatus.pipeline;
    final currentIndex = pipeline.indexOf(report.status);
    final isBranch = report.status == ReportStatus.needsMoreInformation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProgress(pipeline, currentIndex, isBranch),
        if (isBranch) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: StatusPalette.forStatus(ReportStatus.needsMoreInformation)
                  .background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.help_outline_rounded,
                  size: 18,
                  color: StatusPalette.forStatus(
                    ReportStatus.needsMoreInformation,
                  ).foreground,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'More information has been requested for this report.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'STATUS HISTORY',
          style: TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        if (report.statusHistory.isEmpty)
          const Text(
            'No status updates recorded yet.',
            style: TextStyle(color: _muted, fontSize: 12),
          )
        else
          ...report.statusHistory.reversed.map(
            (event) => _buildHistoryRow(event),
          ),
      ],
    );
  }

  Widget _buildProgress(
    List<ReportStatus> pipeline,
    int currentIndex,
    bool isBranch,
  ) {
    final activeIndex = isBranch ? 0 : currentIndex;
    final lastIndex = pipeline.length - 1;

    // Every stage is an equal-width [Expanded] cell holding a fixed-height
    // node row plus its label:
    //
    // * the outer Row is top aligned, so a label that wraps to two lines can
    //   never push its circle onto a different centerline from its neighbours;
    // * each cell draws the connector on *both* sides of its circle, so all
    //   five circles sit in the exact middle of equal-width cells and are
    //   spaced evenly, and the line runs through the circle centres;
    // * the node row has a fixed height, so label wrapping cannot move the
    //   circles or the connecting line.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < pipeline.length; i++)
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: _nodeSize,
                  child: Row(
                    children: [
                      Expanded(
                        child: _connector(
                          key: ValueKey('status-connector-$i-left'),
                          filled: i <= activeIndex,
                        ),
                      ),
                      Container(
                        key: ValueKey('status-node-$i'),
                        height: _nodeSize,
                        width: _nodeSize,
                        decoration: BoxDecoration(
                          color: i <= activeIndex ? _teal : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i <= activeIndex ? _teal : _border,
                            width: 2,
                          ),
                        ),
                        child: i <= activeIndex
                            ? const Icon(Icons.check, size: 12, color: _navy)
                            : null,
                      ),
                      Expanded(
                        child: _connector(
                          key: ValueKey('status-connector-$i-right'),
                          // The segment after the last node is only part of
                          // the progress track once that node is reached.
                          filled: i < lastIndex
                              ? (i + 1) <= activeIndex
                              : i <= activeIndex,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  pipeline[i].label,
                  key: ValueKey('status-label-$i'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: i <= activeIndex ? _navy : _muted,
                    fontSize: 9,
                    fontWeight: i <= activeIndex
                        ? FontWeight.w800
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _connector({required Key key, required bool filled}) {
    return Container(key: key, height: 3, color: filled ? _teal : _border);
  }

  Widget _buildHistoryRow(StatusEvent event) {
    final palette = StatusPalette.forStatus(event.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            height: 12,
            width: 12,
            decoration: BoxDecoration(
              color: palette.foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.status.label,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDateTime(event.timestamp),
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                if (event.note != null && event.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    event.note!,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
