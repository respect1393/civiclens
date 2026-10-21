import 'package:flutter/material.dart';

import '../models/civic_report.dart';
import '../services/api_client.dart';
import '../state/auth_repository.dart';
import '../state/auth_scope.dart';
import '../state/report_repository.dart';
import '../state/report_scope.dart';
import '../widgets/report_list_card.dart';
import 'report_details_screen.dart';

const Color _navy = Color(0xFF102A43);
const Color _teal = Color(0xFF13B8A6);
const Color _muted = Color(0xFF627D98);
const Color _danger = Color(0xFFB3261E);

/// The citizen's reports, read live from the municipal backend.
///
/// There is no local report database: the list, the loading state, the empty
/// state and every error all come from the same backend request, so the screen
/// can never show a stale or invented report.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key, this.onReportIssue});

  /// Invoked when the citizen taps "Report an Issue" from the empty state.
  final VoidCallback? onReportIssue;

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  /// Set once a retrieval has been started, so later dependency changes for
  /// this screen instance do not repeat it.
  bool _loadAttempted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeLoad();
  }

  /// Starts the first retrieval. Reading the auth scope here also registers a
  /// dependency, so a late sign-in is picked up and triggers a reload.
  void _maybeLoad() {
    final signedIn = AuthScope.of(context).status == AuthStatus.authenticated;
    if (!signedIn) {
      // Nothing to fetch while signed out; clear anything left over.
      _loadAttempted = false;
      return;
    }
    if (_loadAttempted) return;
    _loadAttempted = true;
    // Deferred to after this frame so a fetch that starts during layout never
    // calls setState in the middle of a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ReportScope.read(context).load();
    });
  }

  Future<void> _onRefresh() => ReportScope.read(context).load();

  @override
  Widget build(BuildContext context) {
    final repository = ReportScope.of(context);
    final signedIn = AuthScope.of(context).status == AuthStatus.authenticated;
    final reports = repository.reports;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F7FA),
        foregroundColor: _navy,
        automaticallyImplyLeading: false,
        title: const Text(
          'My Reports',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _buildBody(repository, reports, signedIn),
    );
  }

  Widget _buildBody(
    ReportRepository repository,
    List<CivicReport> reports,
    bool signedIn,
  ) {
    if (!signedIn) return _buildSignedOut();

    if (repository.isLoading && reports.isEmpty) {
      return _buildLoading();
    }

    final error = repository.lastError;
    if (error != null && reports.isEmpty) {
      return _buildError(error);
    }

    if (reports.isEmpty) return _buildEmpty();

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        itemCount: reports.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final report = reports[index];
          return ReportListCard(
            report: report,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReportDetailsScreen(reportId: report.id),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 18),
            Text(
              'Checking your reports with the city…',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 42, color: _danger),
            const SizedBox(height: 16),
            const Text(
              'Could not load your reports',
              style: TextStyle(
                color: _navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error is ApiException
                  ? error.message
                  : 'We could not reach the city right now. Please try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => ReportScope.read(context).load(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedOut() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Sign in to see the reports you have submitted.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 14, height: 1.6),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.assignment_outlined,
                size: 42,
                color: _navy,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No reports yet',
              style: TextStyle(
                color: _navy,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Reports you submit are sent to the city and will appear here, '
              'with their current status.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 24),
            if (widget.onReportIssue != null)
              FilledButton.icon(
                onPressed: widget.onReportIssue,
                icon: const Icon(Icons.add_a_photo_outlined, size: 19),
                label: const Text('Report an Issue'),
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: _navy,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
