import 'package:flutter/material.dart';

import 'models/civic_report.dart';
import 'screens/auth_gate.dart';
import 'screens/my_reports_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/report_details_screen.dart';
import 'screens/report_issue_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/report_api_service.dart';
import 'services/session_store.dart';
import 'state/auth_repository.dart';
import 'state/auth_scope.dart';
import 'state/report_repository.dart';
import 'state/report_scope.dart';
import 'utils/report_format.dart';
import 'widgets/report_status_chip.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Authentication is wired before the first frame: one API client (base URL
  // comes from ApiConfig, never a hardcoded host), one session store backed by
  // secure storage, and the 401 hook that drops a session the server rejects.
  final apiClient = ApiClient();
  final auth = AuthRepository(
    authService: HttpAuthService(apiClient),
    sessionStore: SecureSessionStore(),
  );
  apiClient.onUnauthorized = auth.handleUnauthorized;

  // Reports live on the backend and are read through the same API client. The
  // token is read lazily so the repository always uses the current session
  // instead of holding credentials. This early load runs before the session is
  // restored, so it starts empty; My Reports re-fetches once signed in.
  final repository = ReportRepository(
    apiService: HttpReportApiService(apiClient),
    accessToken: () => auth.token,
  );
  await repository.load();

  // The saved session is read before the first frame. Android's launch screen
  // covers that wait, so the very first Flutter frame is already either the
  // signed-in app or the login screen: there is no "restoring your session"
  // page and no login flash for a citizen who is already signed in.
  await auth.restoreSession();

  runApp(CivicLensApp(repository: repository, auth: auth));
}

const Color navy = Color(0xFF102A43);
const Color background = Color(0xFFF5F7FA);
const Color teal = Color(0xFF13B8A6);
const Color muted = Color(0xFF627D98);
const Color borderColor = Color(0xFFE4EAF0);
const Color _danger = Color(0xFFB3261E);

class CivicLensApp extends StatelessWidget {
  const CivicLensApp({super.key, required this.repository, required this.auth});

  final ReportRepository repository;
  final AuthRepository auth;

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      auth: auth,
      child: ReportScope(
        repository: repository,
        child: MaterialApp(
          title: 'CIVICLENS',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: background,
            colorScheme: ColorScheme.fromSeed(
              seedColor: teal,
              primary: navy,
              surface: Colors.white,
            ),
            fontFamily: 'Roboto',
          ),
          home: AuthGate(authenticatedHome: const HomeScreen()),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _myReportsLoadAttempted = false;
  String? _exploreSelectedDistrict;

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming in a future milestone.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openReportScreen() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReportIssueScreen()));
  }

  void _openReportDetails(CivicReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportDetailsScreen(reportId: report.id),
      ),
    );
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
    if (index == 1) {
      // Explore: district-scoped reports within the user's own state.
      final user = AuthScope.of(context).user;
      ReportScope.read(context).load(mine: false, district: user?.district);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AuthScope.of(context);

    if (auth.status != AuthStatus.authenticated) return;

    if (!_myReportsLoadAttempted) {
      _myReportsLoadAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ReportScope.read(context).load(mine: true);
      });
    }
  }

  void _loadExplore() {
    final user = AuthScope.of(context).user;
    final defaultDistrict = user?.district;
    setState(() => _exploreSelectedDistrict = defaultDistrict);
    ReportScope.read(context).load(
      mine: false,
      district: defaultDistrict,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildHome(),
            _buildExplore(),
            MyReportsScreen(onReportIssue: _openReportScreen),
            const ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        backgroundColor: Colors.white,
        indicatorColor: teal.withValues(alpha: 0.13),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: 'My Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildHome() {
    final repository = ReportScope.of(context);
    final userReports = repository.reports;
    final recent = userReports.take(2).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildHeader(),
              const SizedBox(height: 30),
              _buildWelcome(),
              const SizedBox(height: 24),
              _buildReportCard(),
              const SizedBox(height: 20),
              _buildSummaryCard(repository),
              const SizedBox(height: 28),
              _buildSectionHeading(
                'Recent activity',
                recent.isNotEmpty
                    ? 'Your latest reports'
                    : 'No reports submitted yet',
              ),
              const SizedBox(height: 16),
              if (recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Submit a report from the report screen to see it here.',
                    style: TextStyle(color: muted, fontSize: 13, height: 1.5),
                  ),
                )
              else
                for (final report in recent) ...[
                  _buildReportSummaryCard(report),
                  const SizedBox(height: 12),
                ],
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'TAP A REPORT TO SEE ITS FULL DETAILS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              _buildSectionHeading(
                'Your community',
                'Small actions. Real change.',
              ),
              const SizedBox(height: 16),
              _buildCommunityCard(),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(
            color: navy,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.location_city_rounded, color: teal, size: 27),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CIVICLENS',
                style: TextStyle(
                  color: navy,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'YOUR CITY. YOUR VOICE.',
                style: TextStyle(
                  color: muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _showComingSoon('Notifications'),
          tooltip: 'Notifications',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: navy,
            side: const BorderSide(color: borderColor),
          ),
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }

  Widget _buildWelcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'A better city starts',
          style: TextStyle(
            color: navy,
            fontSize: 29,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const Text(
          'with you.',
          style: TextStyle(
            color: teal,
            fontSize: 29,
            height: 1.2,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'See a civic problem? Report it, share the evidence, '
          'and help your community move forward.',
          style: TextStyle(color: muted, fontSize: 14, height: 1.6),
        ),
      ],
    );
  }

  Widget _buildReportCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: navy,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.campaign_rounded, color: teal, size: 28),
          ),
          const SizedBox(height: 18),
          const Text(
            'SPOT SOMETHING WRONG?',
            style: TextStyle(
              color: teal,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your reports',
            style: TextStyle(
              color: navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Report potholes, broken streetlights, water issues '
            'and other civic problems.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openReportScreen,
              icon: const Icon(Icons.add_a_photo_outlined, size: 19),
              label: const Text('Report an Issue'),
              style: FilledButton.styleFrom(
                backgroundColor: teal,
                foregroundColor: navy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
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

  Widget _buildSummaryCard(ReportRepository repository) {
    final counts = repository.statusCounts;
    final total = repository.reportCount;
    final active =
        (counts[ReportStatus.underReview] ?? 0) +
        (counts[ReportStatus.accepted] ?? 0) +
        (counts[ReportStatus.inProgress] ?? 0);
    final resolved = counts[ReportStatus.resolved] ?? 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _selectTab(2),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.insights_rounded, color: teal, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Your reports with the city',
                      style: TextStyle(
                        color: navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: muted,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _statBlock('Saved', '$total'),
                  _statBlock('Active', '$active'),
                  _statBlock('Resolved', '$resolved'),
                ],
              ),
              if (total == 0) ...[
                const SizedBox(height: 12),
                const Text(
                  'No reports submitted yet. Your first report will appear here.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statBlock(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: navy,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSectionHeading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: navy,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
      ],
    );
  }

  Widget _buildCommunityCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFE5FAF6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.groups_rounded, color: teal, size: 30),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Change begins locally',
                  style: TextStyle(
                    color: navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Help make civic problems visible to everyone.',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: muted),
        ],
      ),
    );
  }

  Widget _buildReportSummaryCard(CivicReport report) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _openReportDetails(report),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  categoryIcon(report.category),
                  color: navy,
                  size: 25,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.category.toUpperCase(),
                            style: const TextStyle(
                              color: muted,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      report.title,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: muted,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            displayLocationName(report),
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    if (report.landmarkOrNull != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.near_me_outlined,
                            size: 13,
                            color: muted,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              report.landmarkOrNull!,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    ReportStatusChip(status: report.status, dense: true),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: muted,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExplore() {
    final authState = AuthScope.of(context);
    final user = authState.user;
    final repository = ReportScope.of(context);

    if (authState.status != AuthStatus.authenticated) {
      return _buildExploreSignedOut();
    }

    final userState = user?.state;

    if (userState == null || userState.isEmpty) {
      return _buildExploreEmpty(
        'Location not set',
        'Your state is not registered, so Explore cannot show reports. '
        'Update your profile to start exploring.',
      );
    }

    if (repository.isLoading && repository.reports.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (repository.lastError != null && repository.reports.isEmpty) {
      return _buildExploreError(repository.lastError!);
    }

    final reports = repository.reports;
    if (reports.isEmpty) {
      return _buildExploreEmpty(
        'No reports found',
        'No reports match the selected district in $userState.',
      );
    }

    // Collect available districts from loaded reports for the selector.
    final availableDistricts = <String>{};
    for (final report in reports) {
      if (report.district != null && report.district!.isNotEmpty) {
        availableDistricts.add(report.district!);
      }
    }
    final sortedDistricts = availableDistricts.toList()..sort();

    final selectedDistrict = _exploreSelectedDistrict;
    final isShowingAll = selectedDistrict == null;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildExploreHeader(userState),
              const SizedBox(height: 20),
              _buildDistrictSelector(
                state: userState,
                districts: sortedDistricts,
                selected: selectedDistrict,
                showingAll: isShowingAll,
              ),
              const SizedBox(height: 24),
              _buildExploreSectionHeading(
                'Reports in ${selectedDistrict ?? userState}',
                '${reports.length} report${reports.length == 1 ? '' : 's'}',
              ),
              const SizedBox(height: 16),
              ...reports.map((report) => _buildExploreReportCard(report)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildExploreSignedOut() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 42, color: muted),
            SizedBox(height: 16),
            Text(
              'Sign in to explore',
              style: TextStyle(color: navy, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Please sign in to see reports in your area.',
              style: TextStyle(color: muted, fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExploreHeader(String state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Explore your city',
          style: TextStyle(
            color: navy,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Discovering reports in $state',
          style: TextStyle(color: muted, fontSize: 13, height: 1.6),
        ),
      ],
    );
  }

  Widget _buildDistrictSelector({
    required String state,
    required List<String> districts,
    required String? selected,
    required bool showingAll,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 18, color: muted),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Show reports in',
                  style: TextStyle(color: navy, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: Text('All districts in $state'),
                selected: showingAll,
                onSelected: (picked) {
                  setState(() => _exploreSelectedDistrict = null);
                  ReportScope.read(context).load(mine: false);
                },
              ),
              for (final district in districts)
                FilterChip(
                  label: Text(district),
                  selected: selected == district,
                  onSelected: (picked) {
                    setState(() => _exploreSelectedDistrict = district);
                    ReportScope.read(context).load(mine: false, district: district);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExploreSectionHeading(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: navy,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(subtitle, style: TextStyle(color: muted, fontSize: 12)),
      ],
    );
  }

  Widget _buildExploreReportCard(CivicReport report) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _openReportDetails(report),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  categoryIcon(report.category),
                  color: navy,
                  size: 25,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.category.toUpperCase(),
                            style: const TextStyle(
                              color: muted,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      report.title,
                      style: const TextStyle(
                        color: navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: muted,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            report.district != null && report.district!.isNotEmpty
                                ? report.district!
                                : report.locationLabel,
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ReportStatusChip(status: report.status, dense: true),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: muted,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExploreEmpty(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: teal.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.map_outlined, size: 42, color: navy),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: navy,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 14, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExploreError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 42, color: _danger),
            const SizedBox(height: 16),
            const Text(
              'Could not load reports',
              style: TextStyle(color: navy, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Please try again later.',
              style: TextStyle(color: muted, fontSize: 14, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loadExplore,
              style: FilledButton.styleFrom(
                backgroundColor: teal,
                foregroundColor: navy,
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

