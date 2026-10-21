import 'package:flutter/material.dart';

import '../models/civic_report.dart';
import '../state/report_scope.dart';
import '../utils/report_format.dart';
import '../widgets/report_status_chip.dart';
import '../widgets/report_thumbnail.dart';
import '../widgets/status_timeline.dart';

const Color _navy = Color(0xFF102A43);
const Color _teal = Color(0xFF13B8A6);
const Color _muted = Color(0xFF627D98);
const Color _border = Color(0xFFE4EAF0);
const Color _danger = Color(0xFFB3261E);

class ReportDetailsScreen extends StatefulWidget {
  const ReportDetailsScreen({super.key, required this.reportId});

  final String reportId;

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  /// True while a delete is being confirmed by the backend, so the button
  /// cannot fire a second delete for the same report.
  bool _isDeleting = false;

  /// Shows the confirmation dialog and deletes only when the citizen confirms.
  ///
  /// Cancelling or dismissing leaves the report untouched.
  Future<void> _confirmDelete(CivicReport report) async {
    if (_isDeleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this report?'),
        content: Text(
          '"${report.title}" will be deleted from the city\'s records. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _delete(report);
  }

  Future<void> _delete(CivicReport report) async {
    setState(() => _isDeleting = true);

    try {
      await ReportScope.read(context).deleteReport(report.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not delete this report. It is still on the city\'s '
            'records.',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Report deleted')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ReportScope.of(context);
    final report = repository.findById(widget.reportId);

    if (report == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F7FA),
          foregroundColor: _navy,
          title: const Text(
            'Report details',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: _buildMissing(),
      );
    }

    final coordinates = displayCoordinates(report);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FA),
        foregroundColor: _navy,
        title: const Text(
          'Report details',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          ReportStatusChip(status: report.status),
          const SizedBox(height: 16),
          Text(
            report.category.toUpperCase(),
            style: const TextStyle(
              color: _muted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            report.title,
            style: const TextStyle(
              color: _navy,
              fontSize: 24,
              height: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Reported on ${formatDateTime(report.createdAt)}',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          ReportPhotoPanel(report: report),
          const SizedBox(height: 24),
          _section('Description'),
          _panel(
            Text(
              report.description.isEmpty
                  ? 'No description was provided.'
                  : report.description,
              style: const TextStyle(color: _navy, fontSize: 14, height: 1.6),
            ),
          ),
          const SizedBox(height: 24),
          _section('Location'),
          _panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(
                  Icons.location_on_outlined,
                  displayLocationName(report),
                ),
                if (report.landmarkOrNull != null) ...[
                  const SizedBox(height: 10),
                  _infoRow(Icons.near_me_outlined, report.landmarkOrNull!),
                ],
                const SizedBox(height: 10),
                _infoRow(
                  Icons.my_location_rounded,
                  coordinates ??
                      'No coordinates were recorded for this report.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _section('Tracking'),
          _panel(StatusTimeline(report: report)),
          const SizedBox(height: 24),
          _section('Report ID'),
          _panel(
            SelectableText(
              report.id,
              style: const TextStyle(
                color: _navy,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _isDeleting ? null : () => _confirmDelete(report),
              icon: _isDeleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: Text(_isDeleting ? 'Deleting...' : 'Delete Report'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _danger,
                side: const BorderSide(color: _danger),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissing() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 42, color: _muted),
            const SizedBox(height: 16),
            const Text(
              'Report not found',
              style: TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This report is no longer available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _panel(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _infoRow(IconData icon, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _teal),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: _navy, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}
