import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_provider.dart';
import 'workspace_page_style.dart';
import 'team_member_picker.dart';
import 'field_job_link_picker.dart';

class FieldJobService {
  Future<void> save(
    String token, {
    int? job,
    required Map<String, dynamic> payload,
  }) async {
    final response = job == null
        ? await ApiClient.postJson(
            '/field-jobs',
            bearerToken: token,
            body: payload,
          )
        : await ApiClient.patchJson(
            '/field-jobs/$job',
            bearerToken: token,
            body: payload,
          );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body);
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to save job.'
            : 'Unable to save job.',
      );
    }
  }
}

final fieldJobServiceProvider = Provider<FieldJobService>(
  (ref) => FieldJobService(),
);

class FieldJobForm extends ConsumerStatefulWidget {
  const FieldJobForm({
    super.key,
    required this.workspaceId,
    required this.onSaved,
    this.job,
  });
  final int workspaceId;
  final VoidCallback onSaved;
  final Map? job;
  @override
  ConsumerState<FieldJobForm> createState() => _FieldJobFormState();
}

class _FieldJobFormState extends ConsumerState<FieldJobForm> {
  late final String _tokenAtOpen;
  late final int _companyAtOpen;
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  String search = '';
  int page = 1;
  int? assignee;
  String? assigneeName;
  int? teamId;
  String? teamName;
  bool assignmentChanged = false;
  int? projectId;
  int? recordId;
  String? projectName;
  String? recordName;
  bool projectChanged = false;
  bool recordChanged = false;
  bool busy = false;
  String? error;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    _tokenAtOpen = ref.read(authSessionProvider).token;
    _companyAtOpen = widget.workspaceId;
    title.text = widget.job?['title']?.toString() ?? '';
    description.text = widget.job?['description']?.toString() ?? '';
    assignee = (widget.job?['assignee_membership_id'] as num?)?.toInt();
    assigneeName = widget.job?['assignee_name']?.toString();
    teamId = (widget.job?['company_team_id'] as num?)?.toInt();
    teamName = widget.job?['team_name']?.toString();
    projectId = (widget.job?['company_project_id'] as num?)?.toInt();
    recordId = (widget.job?['land_id'] as num?)?.toInt();
    projectName = widget.job?['project_name']?.toString();
    recordName = widget.job?['record_name']?.toString();
  }

  bool get _scopeCurrent {
    if (!mounted) return false;
    final session = ref.read(authSessionProvider);
    return session.isLoggedIn &&
        session.isVerified &&
        session.token == _tokenAtOpen &&
        widget.workspaceId == _companyAtOpen &&
        ref.read(workspaceProvider).activeCompanyId == _companyAtOpen;
  }

  @override
  void dispose() {
    debounce?.cancel();
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !_scopeCurrent || ref.read(workspaceProvider).isLoading) return;
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = ref.read(authSessionProvider);
      if (widget.workspaceId != ref.read(workspaceProvider).activeCompanyId ||
          !session.isVerified) {
        throw Exception(
          'Workspace or session changed. Reopen the form and try again.',
        );
      }
      if (widget.job != null &&
          ['completed', 'cancelled'].contains(widget.job!['status'])) {
        throw Exception('This job is closed.');
      }
      final originalStatus = widget.job?['status']?.toString() ?? 'draft';
      if (originalStatus != 'draft' && assignee == null && teamId == null) {
        throw Exception('Assign a member or team before saving this job.');
      }
      final jobId = widget.job == null
          ? null
          : int.tryParse(widget.job!['id'].toString());
      if (widget.job != null && (jobId == null || jobId <= 0)) {
        throw Exception('Invalid job reference. Reopen the form.');
      }
      final payload = {
        'title': title.text.trim(),
        'description': description.text.trim(),
        if (widget.job == null || assignmentChanged)
          'assignee_membership_id': assignee,
        if (widget.job == null || assignmentChanged) 'company_team_id': teamId,
        if (projectChanged) 'company_project_id': projectId,
        if (recordChanged) 'land_id': recordId,
        'status':
            originalStatus == 'draft' && (assignee != null || teamId != null)
            ? 'assigned'
            : originalStatus,
      };
      await ref
          .read(fieldJobServiceProvider)
          .save(_tokenAtOpen, job: jobId, payload: payload);
      if (!mounted || !_scopeCurrent) return;
      widget.onSaved();
      Navigator.pop(context);
    } catch (failure) {
      if (mounted && _scopeCurrent) {
        setState(() {
          error = failure.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickTeam() async {
    if (!_scopeCurrent || busy) return;
    final item = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => FieldJobLinkPicker(
          company: widget.workspaceId,
          project: false,
          team: true,
        ),
      ),
    );
    if (!mounted || !_scopeCurrent || item == null) return;
    final id = int.tryParse(item['id'].toString());
    if (id == null) return;
    setState(() {
      teamId = id;
      teamName = item['name']?.toString();
      assignee = null;
      assigneeName = null;
      assignmentChanged = true;
    });
  }

  Future<void> pickLink(bool project) async {
    if (!_scopeCurrent || busy) return;
    final token = ref.read(authSessionProvider).token;
    final item = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) =>
            FieldJobLinkPicker(company: widget.workspaceId, project: project),
      ),
    );
    if (!mounted ||
        item == null ||
        !_scopeCurrent ||
        widget.workspaceId != ref.read(workspaceProvider).activeCompanyId ||
        token != ref.read(authSessionProvider).token) {
      return;
    }
    final id = int.tryParse(item['id'].toString());
    if (id == null) return;
    setState(() {
      if (project) {
        projectId = id;
        projectName = item['name']?.toString();
        projectChanged = true;
      } else {
        recordId = id;
        recordName = item['name']?.toString();
        recordChanged = true;
      }
    });
  }

  Widget linkedItem(bool project) {
    final id = project ? projectId : recordId;
    final name = project ? projectName : recordName;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(project ? Icons.folder_outlined : Icons.map_outlined),
      title: Text(project ? 'Project' : 'Record'),
      subtitle: Text(name ?? (id == null ? 'Not linked' : 'Current #$id')),
      onTap: busy ? null : () => pickLink(project),
      trailing: id == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: project ? 'Unlink project' : 'Unlink record',
              onPressed: busy
                  ? null
                  : () => setState(() {
                      if (project) {
                        projectId = null;
                        projectName = null;
                        projectChanged = true;
                      } else {
                        recordId = null;
                        recordName = null;
                        recordChanged = true;
                      }
                    }),
              icon: const Icon(Icons.close, size: 18),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionProvider);
    final workspace = ref.watch(workspaceProvider);
    final available = _scopeCurrent && !workspace.isLoading;
    final query = (search: search, page: page);
    final results = available && search.length >= 2
        ? ref.watch(memberSearchProvider(query))
        : null;
    return PopScope(
      canPop: !busy,
      child: WorkspaceScaffold(
        company: true,
        appBar: AppBar(
          title: Text(widget.job == null ? 'New field job' : 'Edit field job'),
        ),
        body: !available
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _scopeCurrent
                        ? 'Workspace access is refreshing. Your form is kept.'
                        : 'Workspace or account changed. Reopen the field job form.',
                  ),
                ),
              )
            : SafeArea(
                child: Form(
                  key: form,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Job details',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: title,
                        enabled: !busy,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 150,
                        decoration: const InputDecoration(
                          labelText: 'Job title',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a job title'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: description,
                        enabled: !busy,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 5000,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 24),
                      Text(
                        'Project & record',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      linkedItem(true),
                      linkedItem(false),
                      const Divider(height: 32),
                      Text(
                        'Assignment',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.groups_outlined),
                        title: Text(
                          teamId == null
                              ? 'Assign a team'
                              : (teamName ?? 'Team #$teamId'),
                        ),
                        subtitle: teamId == null
                            ? null
                            : const Text('Team assignment'),
                        onTap: busy ? null : pickTeam,
                        trailing: teamId == null
                            ? const Icon(Icons.chevron_right)
                            : IconButton(
                                tooltip: 'Clear team',
                                onPressed: busy
                                    ? null
                                    : () => setState(() {
                                        teamId = null;
                                        teamName = null;
                                        assignmentChanged = true;
                                      }),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(
                          assigneeName ??
                              (teamId == null
                                  ? 'Unassigned'
                                  : 'Assigned to team'),
                        ),
                        subtitle: Text(
                          assignee == null && teamId == null
                              ? 'Draft'
                              : 'Assigned',
                        ),
                        trailing: assignee == null
                            ? null
                            : IconButton(
                                tooltip: 'Clear assignee',
                                onPressed: busy
                                    ? null
                                    : () => setState(() {
                                        assignee = null;
                                        assigneeName = null;
                                        assignmentChanged = true;
                                      }),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                      ),
                      TextField(
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'Find company member',
                          hintText: 'Name or email',
                          prefixIcon: Icon(Icons.search),
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
                      if (results != null)
                        results.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (_, _) => TextButton(
                            onPressed: () =>
                                ref.invalidate(memberSearchProvider(query)),
                            child: const Text('Retry member search'),
                          ),
                          data: (data) {
                            final items = (data['data'] as List? ?? [])
                                .whereType<Map>();
                            return Column(
                              children: [
                                if (items.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('No matching members.'),
                                  ),
                                for (final member in items)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      member['name']?.toString() ?? '',
                                    ),
                                    subtitle: Text(
                                      member['email']?.toString() ?? '',
                                    ),
                                    trailing: assignee == member['id']
                                        ? const Icon(
                                            Icons.check_circle_outline,
                                            size: 20,
                                          )
                                        : null,
                                    onTap: busy
                                        ? null
                                        : () => setState(() {
                                            assignee = (member['id'] as num)
                                                .toInt();
                                            assigneeName = member['name']
                                                ?.toString();
                                            teamId = null;
                                            teamName = null;
                                            assignmentChanged = true;
                                          }),
                                  ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      tooltip: 'Previous members',
                                      onPressed: !busy && page > 1
                                          ? () => setState(() => page--)
                                          : null,
                                      icon: const Icon(Icons.chevron_left),
                                    ),
                                    Text('Page $page'),
                                    IconButton(
                                      tooltip: 'Next members',
                                      onPressed:
                                          !busy &&
                                              page <
                                                  ((data['last_page'] as num?)
                                                          ?.toInt() ??
                                                      1)
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
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: busy ? null : save,
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(
                          busy
                              ? 'Saving...'
                              : widget.job == null
                              ? 'Create job'
                              : 'Save changes',
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
