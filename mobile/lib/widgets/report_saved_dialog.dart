import 'package:flutter/material.dart';

import '../models/civic_report.dart';
import '../screens/report_details_screen.dart';

const Color _navy = Color(0xFF102A43);
const Color _muted = Color(0xFF627D98);
const Color _danger = Color(0xFFB3261E);

/// Shows the confirmation for a [report] the backend has accepted.
///
/// This is only shown after the backend confirms the submission, because both
/// of its actions assume the report now exists on the city's records.
Future<void> showReportSavedDialog(BuildContext context, CivicReport report) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ReportSavedDialog(report: report),
  );
}

/// Confirmation shown after a report has been submitted to the backend.
///
/// "Close" dismisses the dialog and leaves the report form. "View report"
/// dismisses the dialog and replaces the report form with the details of the
/// report that was just submitted, so backing out of the details also returns
/// to the previous screen instead of to an empty form.
class ReportSavedDialog extends StatefulWidget {
  const ReportSavedDialog({super.key, required this.report});

  final CivicReport report;

  @override
  State<ReportSavedDialog> createState() => _ReportSavedDialogState();
}

class _ReportSavedDialogState extends State<ReportSavedDialog> {
  /// Guards against a double tap producing two navigations.
  bool _handled = false;

  void _close() {
    if (_handled || !mounted) return;
    _handled = true;

    // Capture the navigator before the dialog route is removed: using the
    // disposed dialog context afterwards would throw.
    final navigator = Navigator.of(context);
    navigator.pop();
    // Leaves the report form, but never pops the application itself when the
    // form happens to be the only route on the stack.
    navigator.maybePop();
  }

  void _viewReport() {
    if (_handled || !mounted) return;
    _handled = true;

    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ReportDetailsScreen(reportId: widget.report.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report submitted'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your report was submitted to the city and is now being reviewed.',
            style: TextStyle(color: _navy, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 12),
          Text(
            widget.report.title,
            style: const TextStyle(
              color: _navy,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Report reference: ${widget.report.id}',
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (widget.report.hasPhoto && !widget.report.hasServerPhoto) ...[
            const SizedBox(height: 12),
            const Text(
              'Your photo could not be uploaded yet. The report was saved, '
              'but the city may not have the evidence image.',
              style: TextStyle(color: _danger, fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _close, child: const Text('Close')),
        FilledButton(onPressed: _viewReport, child: const Text('View report')),
      ],
    );
  }
}
