import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../widget/app_backarrow.dart'; // adjust to your file name/path
import 'workspace_provider.dart';
import 'workspace_page_style.dart';
import 'job_progress_actions.dart';
import 'field_job_form.dart';
import 'job_review_page.dart';
import '../subscriptions/entitlement_provider.dart';

const Color _accent = Color(0xFF245B83); // company accent
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _fieldFill = Color(0xFFF7F7F8);
const Color _greySoft = Color(0xFFF1F3F5);

typedef JobQuery = ({String search, String status, int page});
final fieldJobsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, JobQuery>((ref, query) async {
      final workspace = ref.watch(workspaceProvider);
      final session = ref.watch(authSessionProvider);
      if (workspace.activeCompanyId == null ||
          workspace.isLoading ||
          !session.isVerified) {
        throw Exception('Select an available company workspace.');
      }
      final response = await ApiClient.getJson(
        '/field-jobs',
        bearerToken: session.token,
        queryParameters: {
          'page': query.page,
          'search': query.search,
          if (query.status.isNotEmpty) 'status': query.status,
        },
      );
      if (response.statusCode == 503) {
        throw Exception('Field jobs are not available on this server yet.');
      }
      if (response.statusCode != 200) {
        throw Exception('Unable to load field jobs. Please retry.');
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['data'] is! Map) {
        throw Exception('Unexpected field jobs response.');
      }
      return Map<String, dynamic>.from(body);
    });

String jobStatusLabel(String value) => switch (value) {
  'draft' => 'Draft',
  'assigned' => 'Assigned',
  'in_progress' => 'In progress',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  _ => 'Unknown',
};

String jobAssignmentLabel(Map job) {
  if (job['company_team_id'] != null) {
    return 'Team: ${job['team_name'] ?? 'Unavailable team'}';
  }
  return job['assignee_name']?.toString() ??
      (job['assignee_membership_id'] == null
          ? 'Unassigned'
          : 'Unavailable member');
}

/// Foreground and soft background colour for a job status.
({Color fg, Color bg}) _statusStyle(String status) => switch (status) {
  'assigned' => (fg: const Color(0xFF2B6CB0), bg: const Color(0xFFE8F1FB)),
  'in_progress' => (fg: const Color(0xFFB26A00), bg: const Color(0xFFFFF4E0)),
  'completed' => (fg: const Color(0xFF1B7F4B), bg: const Color(0xFFE6F5EC)),
  'cancelled' => (fg: const Color(0xFFB42318), bg: const Color(0xFFFDECEA)),
  _ => (fg: Colors.black54, bg: _greySoft), // draft / unknown
};

class FieldJobsPage extends ConsumerStatefulWidget {
  const FieldJobsPage({super.key});
  @override
  ConsumerState<FieldJobsPage> createState() => _FieldJobsPageState();
}

class _FieldJobsPageState extends ConsumerState<FieldJobsPage> {
  String search = '';
  String status = '';
  int page = 1;
  Timer? debounce;
  final controller = TextEditingController();
  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  // ── UI helpers ────────────────────────────────────────────────

  Widget _statusChip(String value) {
    final s = _statusStyle(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        jobStatusLabel(value),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: s.fg,
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = status == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() {
          status = value;
          page = 1;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _accent : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? _accent : _cardBorder),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _jobCard(Map job, VoidCallback onTap) {
    final statusValue = job['status']?.toString() ?? '';
    final style = _statusStyle(statusValue);
    final isTeam = job['company_team_id'] != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: style.bg,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedTask01,
                    color: style.fg,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job['title']?.toString() ?? 'Untitled job',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _statusChip(statusValue),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          HugeIcon(
                            icon: isTeam
                                ? HugeIcons.strokeRoundedUserGroup
                                : HugeIcons.strokeRoundedUser,
                            color: Colors.black45,
                            size: 15,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              jobAssignmentLabel(job),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (job['company_project_id'] != null ||
                          job['land_id'] != null) ...[
                        const SizedBox(height: 8),
                        if (job['company_project_id'] != null)
                          Text(
                            job['project_name']?.toString() ??
                                'Unavailable project',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        if (job['land_id'] != null)
                          Text(
                            job['record_name']?.toString() ??
                                'Unavailable record',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black45,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 10, left: 6),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: Colors.black26,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    dynamic icon,
    String label,
    String value, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: HugeIcon(icon: icon, color: _accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Colors.black45,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Job details sheet. Same actions and conditions as before.
  void _showJobSheet({
    required Map job,
    required Map body,
    required JobQuery query,
    required bool mayManage,
    required bool mayProgress,
  }) {
    final workspace = ref.read(workspaceProvider);
    final statusValue = job['status']?.toString() ?? '';
    final description = job['description']?.toString().trim() ?? '';
    final canEdit =
        mayManage &&
        body['can_manage'] == true &&
        body['can_write'] == true &&
        !['completed', 'cancelled'].contains(job['status']);

    final details = <Widget>[
      _detailRow(
        job['company_team_id'] != null
            ? HugeIcons.strokeRoundedUserGroup
            : HugeIcons.strokeRoundedUser,
        'Assigned to',
        jobAssignmentLabel(job),
      ),
      if (job['company_team_id'] != null && job['team_leader_name'] != null)
        _detailRow(
          HugeIcons.strokeRoundedStar,
          'Team lead',
          job['team_leader_name'].toString(),
        ),
      if (job['company_project_id'] != null)
        _detailRow(
          HugeIcons.strokeRoundedFolder01,
          'Project',
          job['project_name']?.toString() ?? 'Unavailable project',
          subtitle: job['project_archived'] == true
              ? 'Archived project'
              : 'Linked project',
        ),
      if (job['land_id'] != null)
        _detailRow(
          HugeIcons.strokeRoundedLocation01,
          'Record',
          job['record_name']?.toString() ?? 'Unavailable record',
          subtitle: job['record_available'] == true
              ? 'Linked record'
              : 'Record no longer available',
        ),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                job['title']?.toString() ?? 'Field job',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _statusChip(statusValue),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _pageBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DESCRIPTION',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description.isNotEmpty ? description : 'No description',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: description.isNotEmpty
                            ? Colors.black87
                            : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < details.length; i++) ...[
                details[i],
                if (i != details.length - 1)
                  const Divider(height: 1, color: Color(0xFFEEF1F4)),
              ],
              if (canEdit)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => FieldJobForm(
                              workspaceId: workspace.activeCompanyId!,
                              job: job,
                              onSaved: () =>
                                  ref.invalidate(fieldJobsProvider(query)),
                            ),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        side: const BorderSide(color: _accent),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedEdit02,
                        color: _accent,
                        size: 18,
                      ),
                      label: const Text(
                        'Edit and assign',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              if (job['status'] == 'completed')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => JobReviewPage(
                              job: job,
                              company: workspace.activeCompanyId!,
                              manager: body['can_manage'] == true,
                              writable: body['can_write'] == true,
                              canSubmit:
                                  body['can_manage'] == true ||
                                  body['membership_id'] != null &&
                                      body['membership_id'] ==
                                          job['assignee_membership_id'],
                              onChanged: () =>
                                  ref.invalidate(fieldJobsProvider(query)),
                            ),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        side: const BorderSide(color: _accent),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedTask01,
                        color: _accent,
                        size: 18,
                      ),
                      label: const Text(
                        'Review and approval',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              JobProgressActions(
                job: job,
                workspaceId: workspace.activeCompanyId,
                writable:
                    (mayManage || mayProgress) && body['can_write'] == true,
                manager: mayManage && body['can_manage'] == true,
                membership: (body['membership_id'] as num?)?.toInt(),
                onChanged: () => ref.invalidate(fieldJobsProvider(query)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: HugeIcon(
            icon: search.isNotEmpty
                ? HugeIcons.strokeRoundedSearch01
                : HugeIcons.strokeRoundedTask01,
            color: _accent,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'No field jobs found',
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    ),
  );

  Widget _pager(int last) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: page > 1 ? () => setState(() => page--) : null,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
              Flexible(
                child: Text(
                  'Page $page of $last',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: page < last ? () => setState(() => page++) : null,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final baseTheme = Theme.of(context);
    final permissions =
        ref.watch(workspacePermissionsProvider).asData?.value ??
        const <String, bool>{};
    final mayManage = permissions['jobs.manage'] == true;
    final mayProgress = permissions['jobs.progress'] == true;
    ref.listen(workspaceProvider.select((s) => s.activeCompanyId), (_, _) {
      debounce?.cancel();
      controller.clear();
      setState(() {
        search = '';
        page = 1;
      });
    });
    final query = (search: search, status: status, page: page);
    final jobs = workspace.activeCompanyId == null
        ? null
        : ref.watch(fieldJobsProvider(query));
    Future<void> refresh() async {
      ref.invalidate(workspaceAccessSnapshotProvider);
      ref.invalidate(fieldJobsProvider(query));
      try {
        await ref.read(fieldJobsProvider(query).future);
      } catch (_) {}
    }

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: _accent),
      ),
      child: WorkspaceScaffold(
        company: workspace.activeCompanyId != null,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leading: const AppBackButton(),
          title: const Text(
            'Field jobs',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Refresh jobs',
              onPressed: workspace.activeCompanyId == null ? null : refresh,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedRefresh,
                color: workspace.activeCompanyId == null
                    ? Colors.black26
                    : Colors.black87,
                size: 22,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: ColoredBox(
          color: _pageBackground,
          child: SafeArea(
            child: jobs == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedTask01,
                            color: Colors.black26,
                            size: 40,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Select a company from your Profile to view field jobs.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      // Header: workspace, search, status filters
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.business_outlined,
                                  size: 16,
                                  color: _accent,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    workspace.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _accent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                hintText: 'Search jobs',
                                hintStyle: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black45,
                                ),
                                filled: true,
                                fillColor: _fieldFill,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                prefixIcon: const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: HugeIcon(
                                    icon: HugeIcons.strokeRoundedSearch01,
                                    color: Colors.black45,
                                    size: 20,
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: _cardBorder,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: _cardBorder,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: _accent,
                                    width: 1.6,
                                  ),
                                ),
                              ),
                              onChanged: (value) {
                                debounce?.cancel();
                                debounce = Timer(
                                  const Duration(milliseconds: 350),
                                  () {
                                    if (mounted) {
                                      setState(() {
                                        search = value.trim();
                                        page = 1;
                                      });
                                    }
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _filterChip('All statuses', ''),
                                  for (final value in const [
                                    'draft',
                                    'assigned',
                                    'in_progress',
                                    'completed',
                                    'cancelled',
                                  ])
                                    _filterChip(jobStatusLabel(value), value),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: _cardBorder),
                      Expanded(
                        child: jobs.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const HugeIcon(
                                    icon: HugeIcons.strokeRoundedWifiOff01,
                                    color: Colors.black26,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    error.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton.tonal(
                                    onPressed: refresh,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          data: (body) {
                            final data = body['data'] as Map;
                            final items = (data['data'] as List? ?? [])
                                .whereType<Map>()
                                .toList();
                            final last =
                                (data['last_page'] as num?)?.toInt() ?? 1;
                            final total =
                                (data['total'] as num?)?.toInt() ??
                                items.length;
                            final canCreate =
                                mayManage &&
                                body['can_manage'] == true &&
                                body['can_write'] == true;
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    12,
                                    16,
                                    0,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$total ${total == 1 ? 'job' : 'jobs'}',
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ),
                                      if (canCreate)
                                        FilledButton.icon(
                                          onPressed: () =>
                                              Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) => FieldJobForm(
                                                    workspaceId: workspace
                                                        .activeCompanyId!,
                                                    onSaved: () =>
                                                        ref.invalidate(
                                                          fieldJobsProvider(
                                                            query,
                                                          ),
                                                        ),
                                                  ),
                                                ),
                                              ),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: _accent,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          icon: const HugeIcon(
                                            icon: HugeIcons
                                                .strokeRoundedAddCircle,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'New job',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: RefreshIndicator(
                                    onRefresh: refresh,
                                    child: ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        16,
                                        24,
                                      ),
                                      children: [
                                        if (items.isEmpty)
                                          _emptyState()
                                        else
                                          for (final job in items)
                                            _jobCard(
                                              job,
                                              () => _showJobSheet(
                                                job: job,
                                                body: body,
                                                query: query,
                                                mayManage: mayManage,
                                                mayProgress: mayProgress,
                                              ),
                                            ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (last > 1) _pager(last),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
