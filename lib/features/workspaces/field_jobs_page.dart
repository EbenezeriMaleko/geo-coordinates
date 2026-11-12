import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_provider.dart';
import 'workspace_page_style.dart';
import 'job_progress_actions.dart';
import 'field_job_form.dart';
import 'job_review_page.dart';
import '../subscriptions/entitlement_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
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

    return WorkspaceScaffold(
      company: workspace.activeCompanyId != null,
      appBar: AppBar(
        title: const Text('Field jobs'),
        actions: [
          IconButton(
            tooltip: 'Refresh jobs',
            onPressed: workspace.activeCompanyId == null ? null : refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: jobs == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Select a company workspace to view field jobs.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workspace.label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: 'Search jobs',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
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
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('All statuses'),
                            ),
                            for (final value in [
                              'draft',
                              'assigned',
                              'in_progress',
                              'completed',
                              'cancelled',
                            ])
                              DropdownMenuItem(
                                value: value,
                                child: Text(jobStatusLabel(value)),
                              ),
                          ],
                          onChanged: (value) => setState(() {
                            status = value ?? '';
                            page = 1;
                          }),
                        ),
                      ],
                    ),
                  ),
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
                              const Icon(Icons.cloud_off_outlined, size: 28),
                              const SizedBox(height: 12),
                              Text(
                                error.toString().replaceFirst(
                                  'Exception: ',
                                  '',
                                ),
                                textAlign: TextAlign.center,
                              ),
                              TextButton.icon(
                                onPressed: refresh,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
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
                        final last = (data['last_page'] as num?)?.toInt() ?? 1;
                        return Column(
                          children: [
                            if (mayManage &&
                                body['can_manage'] == true &&
                                body['can_write'] == true)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => FieldJobForm(
                                          workspaceId:
                                              workspace.activeCompanyId!,
                                          onSaved: () => ref.invalidate(
                                            fieldJobsProvider(query),
                                          ),
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('New job'),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: refresh,
                                child: ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  itemCount: items.isEmpty ? 1 : items.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    if (items.isEmpty) {
                                      return const Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text(
                                          'No field jobs found.',
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    }
                                    final job = items[index];
                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                      leading: const Icon(
                                        Icons.assignment_outlined,
                                        size: 22,
                                      ),
                                      title: Text(
                                        job['title']?.toString() ??
                                            'Untitled job',
                                      ),
                                      subtitle: Text(
                                        '${jobStatusLabel(job['status']?.toString() ?? '')}\n${jobAssignmentLabel(job)}',
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right,
                                        size: 18,
                                      ),
                                      onTap: () => showModalBottomSheet<void>(
                                        context: context,
                                        isScrollControlled: true,
                                        showDragHandle: true,
                                        builder: (context) => SafeArea(
                                          child: SingleChildScrollView(
                                            padding: const EdgeInsets.fromLTRB(
                                              24,
                                              0,
                                              24,
                                              24,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  job['title']?.toString() ??
                                                      'Field job',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleLarge,
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  jobStatusLabel(
                                                    job['status']?.toString() ??
                                                        '',
                                                  ),
                                                ),
                                                const Divider(height: 28),
                                                Text(
                                                  job['description']
                                                              ?.toString()
                                                              .trim()
                                                              .isNotEmpty ==
                                                          true
                                                      ? job['description']
                                                            .toString()
                                                      : 'No description',
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  'Assigned to: ${jobAssignmentLabel(job)}',
                                                ),
                                                if (job['company_team_id'] !=
                                                        null &&
                                                    job['team_leader_name'] !=
                                                        null)
                                                  Text(
                                                    'Team lead: ${job['team_leader_name']}',
                                                  ),
                                                if (job['company_project_id'] !=
                                                    null)
                                                  ListTile(
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    leading: const Icon(
                                                      Icons.folder_outlined,
                                                    ),
                                                    title: Text(
                                                      job['project_name']
                                                              ?.toString() ??
                                                          'Unavailable project',
                                                    ),
                                                    subtitle: Text(
                                                      job['project_archived'] ==
                                                              true
                                                          ? 'Archived project'
                                                          : 'Linked project',
                                                    ),
                                                  ),
                                                if (job['land_id'] != null)
                                                  ListTile(
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    leading: const Icon(
                                                      Icons.map_outlined,
                                                    ),
                                                    title: Text(
                                                      job['record_name']
                                                              ?.toString() ??
                                                          'Unavailable record',
                                                    ),
                                                    subtitle: Text(
                                                      job['record_available'] ==
                                                              true
                                                          ? 'Linked record'
                                                          : 'Record no longer available',
                                                    ),
                                                  ),
                                                if (mayManage &&
                                                    body['can_manage'] ==
                                                        true &&
                                                    body['can_write'] == true &&
                                                    ![
                                                      'completed',
                                                      'cancelled',
                                                    ].contains(job['status']))
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 16,
                                                        ),
                                                    child: OutlinedButton.icon(
                                                      onPressed: () {
                                                        Navigator.of(
                                                          context,
                                                        ).pop();
                                                        Navigator.of(
                                                          this.context,
                                                        ).push(
                                                          MaterialPageRoute<
                                                            void
                                                          >(
                                                            builder: (_) => FieldJobForm(
                                                              workspaceId: workspace
                                                                  .activeCompanyId!,
                                                              job: job,
                                                              onSaved: () => ref
                                                                  .invalidate(
                                                                    fieldJobsProvider(
                                                                      query,
                                                                    ),
                                                                  ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                      icon: const Icon(
                                                        Icons.edit_outlined,
                                                        size: 18,
                                                      ),
                                                      label: const Text(
                                                        'Edit and assign',
                                                      ),
                                                    ),
                                                  ),
                                                if (job['status'] ==
                                                    'completed')
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 16,
                                                        ),
                                                    child: OutlinedButton.icon(
                                                      onPressed: () {
                                                        Navigator.of(
                                                          context,
                                                        ).pop();
                                                        Navigator.of(
                                                          this.context,
                                                        ).push(
                                                          MaterialPageRoute<
                                                            void
                                                          >(
                                                            builder: (_) => JobReviewPage(
                                                              job: job,
                                                              company: workspace
                                                                  .activeCompanyId!,
                                                              manager:
                                                                  body['can_manage'] ==
                                                                  true,
                                                              writable:
                                                                  body['can_write'] ==
                                                                  true,
                                                              canSubmit:
                                                                  body['can_manage'] ==
                                                                      true ||
                                                                  body['membership_id'] !=
                                                                          null &&
                                                                      body['membership_id'] ==
                                                                          job['assignee_membership_id'],
                                                              onChanged: () =>
                                                                  ref.invalidate(
                                                                    fieldJobsProvider(
                                                                      query,
                                                                    ),
                                                                  ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                      icon: const Icon(
                                                        Icons
                                                            .fact_check_outlined,
                                                        size: 18,
                                                      ),
                                                      label: const Text(
                                                        'Review and approval',
                                                      ),
                                                    ),
                                                  ),
                                                JobProgressActions(
                                                  job: job,
                                                  workspaceId:
                                                      workspace.activeCompanyId,
                                                  writable:
                                                      (mayManage ||
                                                          mayProgress) &&
                                                      body['can_write'] == true,
                                                  manager:
                                                      mayManage &&
                                                      body['can_manage'] ==
                                                          true,
                                                  membership:
                                                      (body['membership_id']
                                                              as num?)
                                                          ?.toInt(),
                                                  onChanged: () =>
                                                      ref.invalidate(
                                                        fieldJobsProvider(
                                                          query,
                                                        ),
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'Previous page',
                                  onPressed: page > 1
                                      ? () => setState(() => page--)
                                      : null,
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Flexible(child: Text('Page $page of $last')),
                                IconButton(
                                  tooltip: 'Next page',
                                  onPressed: page < last
                                      ? () => setState(() => page++)
                                      : null,
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
