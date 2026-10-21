import 'package:flutter/material.dart';

import '../models/civic_report.dart';

/// Colour pair used to render a status.
class StatusPalette {
  const StatusPalette(this.foreground, this.background);

  final Color foreground;
  final Color background;

  static StatusPalette forStatus(ReportStatus status) {
    switch (status) {
      case ReportStatus.reported:
        return const StatusPalette(Color(0xFF175CD3), Color(0xFFEFF8FF));
      case ReportStatus.underReview:
        return const StatusPalette(Color(0xFF9A6700), Color(0xFFFFF4D6));
      case ReportStatus.accepted:
        return const StatusPalette(Color(0xFF6941C6), Color(0xFFF4EBFF));
      case ReportStatus.inProgress:
        return const StatusPalette(Color(0xFF0E7090), Color(0xFFE0F7FA));
      case ReportStatus.resolved:
        return const StatusPalette(Color(0xFF027A48), Color(0xFFECFDF3));
      case ReportStatus.needsMoreInformation:
        return const StatusPalette(Color(0xFFB42318), Color(0xFFFEF3F2));
    }
  }

  static IconData iconFor(ReportStatus status) {
    switch (status) {
      case ReportStatus.reported:
        return Icons.mark_email_unread_outlined;
      case ReportStatus.underReview:
        return Icons.search_rounded;
      case ReportStatus.accepted:
        return Icons.verified_outlined;
      case ReportStatus.inProgress:
        return Icons.handyman_outlined;
      case ReportStatus.resolved:
        return Icons.check_circle_outline_rounded;
      case ReportStatus.needsMoreInformation:
        return Icons.help_outline_rounded;
    }
  }
}

/// Small pill that renders a [ReportStatus].
class ReportStatusChip extends StatelessWidget {
  const ReportStatusChip({super.key, required this.status, this.dense = false});

  final ReportStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = StatusPalette.forStatus(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 9 : 11,
        vertical: dense ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            StatusPalette.iconFor(status),
            size: dense ? 12 : 14,
            color: palette.foreground,
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: palette.foreground,
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
