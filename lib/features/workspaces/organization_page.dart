import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_provider.dart';
import 'workspace_page_style.dart';
import '../subscriptions/entitlement_provider.dart';
import 'team_member_picker.dart';

typedef OrganizationQuery = ({
  String kind,
  String search,
  String status,
  int page,
  int? team,
});

final organizationPageProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, OrganizationQuery>((ref, query) async {
      final workspace = ref.watch(workspaceProvider);
      final session = ref.watch(authSessionProvider);
      if (workspace.activeCompanyId == null ||
          workspace.isLoading ||
          !session.isVerified) {
        throw Exception('Select an available company workspace.');
      }
      final response = await ApiClient.getJson(
        query.team == null
            ? '/organization/${query.kind}'
            : '/organization/teams/${query.team}/members',
        bearerToken: session.token,
        queryParameters: {
          'page': query.page,
          if (query.team == null) ...{
            'search': query.search,
            'status': query.status,
          },
        },
        tag: 'organization_read',
      );
      if (response.statusCode == 503) {
        throw Exception(
          'Projects and teams are not available on this server yet.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Unable to load company information. Please retry.');
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['data'] is! Map) {
        throw Exception('Unexpected server response.');
      }
      return Map<String, dynamic>.from(body['data'] as Map);
    });

class OrganizationPage extends ConsumerStatefulWidget {
  const OrganizationPage({super.key, this.teamId, this.teamName});
  final int? teamId;
  final String? teamName;
  @override
  ConsumerState<OrganizationPage> createState() => _OrganizationPageState();
}

class _OrganizationPageState extends ConsumerState<OrganizationPage> {
  String kind = 'projects';
  String search = '';
  String status = 'active';
  int page = 1;
  Timer? debounce;
  final controller = TextEditingController();
  bool removingMember = false;
  Future<void> setTeamLeader(OrganizationQuery query, int? membershipId) async {
    final company = ref.read(workspaceProvider).activeCompanyId;
    final token = ref.read(authSessionProvider).token;
    if (company == null || widget.teamId == null || removingMember) return;
    setState(() => removingMember = true);
    try {
      if (company != ref.read(workspaceProvider).activeCompanyId ||
          token != ref.read(authSessionProvider).token) {
        throw Exception('Workspace or session changed. Please retry.');
      }
      final response = await ApiClient.patchJson(
        '/organization/teams/${widget.teamId}',
        bearerToken: token,
        body: {'leader_membership_id': membershipId},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = jsonDecode(response.body);
        throw Exception(
          body is Map
              ? body['message'] ?? 'Unable to update team lead.'
              : 'Unable to update team lead.',
        );
      }
      if (!mounted ||
          company != ref.read(workspaceProvider).activeCompanyId ||
          token != ref.read(authSessionProvider).token) {
        return;
      }
      ref.invalidate(organizationPageProvider(query));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Team lead updated.')));
    } catch (failure) {
      if (mounted &&
          company == ref.read(workspaceProvider).activeCompanyId &&
          token == ref.read(authSessionProvider).token) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => removingMember = false);
    }
  }

  Future<void> removeMember(OrganizationQuery query, Map member) async {
    final company = ref.read(workspaceProvider).activeCompanyId;
    final token = ref.read(authSessionProvider).token;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove team member?'),
        content: Text(
          '${member['name'] ?? 'This member'} will leave this team. Their company membership and records stay unchanged.',
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove from team'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => removingMember = true);
    try {
      if (company != ref.read(workspaceProvider).activeCompanyId ||
          token != ref.read(authSessionProvider).token) {
        throw Exception('Workspace or session changed. Please retry.');
      }
      final response = await ApiClient.deleteJson(
        '/organization/teams/${widget.teamId}/members/${member['id']}',
        bearerToken: token,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Unable to remove this member. Refresh and check company access.',
        );
      }
      if (!mounted) return;
      ref.invalidate(organizationPageProvider(query));
      setState(() => page = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member removed from team.')),
      );
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => removingMember = false);
    }
  }

  Future<void> editItem(
    OrganizationQuery query, {
    Map? item,
    bool? archive,
  }) async {
    final company = ref.read(workspaceProvider).activeCompanyId;
    final token = ref.read(authSessionProvider).token;
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final description = TextEditingController(
      text: item?['description']?.toString() ?? '',
    );
    var busy = false;
    String? error;
    final form = GlobalKey<FormState>();
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: Text(
              archive != null
                  ? (archive ? 'Archive item?' : 'Reactivate item?')
                  : '${item == null ? 'Create' : 'Edit'} ${query.kind == 'projects' ? 'project' : 'team'}',
            ),
            content: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (archive == null) ...[
                      TextFormField(
                        controller: name,
                        autofocus: true,
                        maxLength: 150,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: description,
                        maxLength: 5000,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                        ),
                      ),
                    ] else
                      Text(
                        archive
                            ? 'Existing records will remain unchanged.'
                            : 'Reactivation is subject to the current plan allowance.',
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (!form.currentState!.validate()) return;
                            update(() {
                              busy = true;
                              error = null;
                            });
                            try {
                              if (company !=
                                      ref
                                          .read(workspaceProvider)
                                          .activeCompanyId ||
                                  token !=
                                      ref.read(authSessionProvider).token) {
                                throw Exception(
                                  'Workspace or session changed. Close and try again.',
                                );
                              }
                              final payload = archive == null
                                  ? <String, dynamic>{
                                      'name': name.text.trim(),
                                      'description': description.text.trim(),
                                    }
                                  : <String, dynamic>{'archived': archive};
                              final response = item == null
                                  ? await ApiClient.postJson(
                                      '/organization/${query.kind}',
                                      body: payload,
                                      bearerToken: token,
                                    )
                                  : await ApiClient.patchJson(
                                      '/organization/${query.kind}/${item['id']}',
                                      body: payload,
                                      bearerToken: token,
                                    );
                              if (response.statusCode < 200 ||
                                  response.statusCode >= 300) {
                                final body = jsonDecode(response.body);
                                throw Exception(
                                  body is Map
                                      ? body['message'] ?? 'Unable to save.'
                                      : 'Unable to save.',
                                );
                              }
                              if (!mounted || !dialogContext.mounted) return;
                              ref.invalidate(organizationPageProvider(query));
                              Navigator.pop(dialogContext);
                            } catch (failure) {
                              if (dialogContext.mounted) {
                                update(() {
                                  error = failure.toString().replaceFirst(
                                    'Exception: ',
                                    '',
                                  );
                                  busy = false;
                                });
                              }
                            }
                          },
                    child: Text(
                      busy
                          ? 'Saving...'
                          : archive != null
                          ? 'Confirm'
                          : 'Save',
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await navigator.push(route);
    // A pop resolves before the closing animation removes the form's fields.
    await route.completed;
    name.dispose();
    description.dispose();
  }

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
    final mayWrite = permissions['organization.manage'] == true;
    final mayReduce = permissions['organization.reduce'] == true;
    ref.listen(workspaceProvider.select((s) => s.activeCompanyId), (_, _) {
      debounce?.cancel();
      controller.clear();
      setState(() {
        page = 1;
        search = '';
      });
      if (widget.teamId != null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    final query = (
      kind: kind,
      search: search,
      status: status,
      page: page,
      team: widget.teamId,
    );
    final response = workspace.activeCompanyId == null
        ? null
        : ref.watch(organizationPageProvider(query));
    Future<void> refresh() async {
      ref.invalidate(organizationPageProvider(query));
      try {
        await ref.read(organizationPageProvider(query).future);
      } catch (_) {}
    }

    return WorkspaceScaffold(
      company: workspace.activeCompanyId != null,
      appBar: AppBar(
        title: Text(widget.teamName ?? 'Projects & Teams'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: workspace.activeCompanyId == null ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: workspace.activeCompanyId == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Select a company in Settings → Workspace to view projects and teams.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        workspace.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  if (widget.teamId == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<String>(
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: 'projects',
                                  label: Text('Projects'),
                                ),
                                ButtonSegment(
                                  value: 'teams',
                                  label: Text('Teams'),
                                ),
                              ],
                              selected: {kind},
                              onSelectionChanged: (value) => setState(() {
                                kind = value.first;
                                page = 1;
                              }),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              hintText: 'Search $kind',
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 20,
                              ),
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
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              border: InputBorder.none,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'active',
                                child: Text('Active'),
                              ),
                              DropdownMenuItem(
                                value: 'archived',
                                child: Text('Archived'),
                              ),
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('All statuses'),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              status = value ?? 'active';
                              page = 1;
                            }),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: response!.when(
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
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: refresh,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      data: (data) {
                        final pagination =
                            data[widget.teamId == null ? 'items' : 'members']
                                as Map? ??
                            {};
                        final items = (pagination['data'] as List? ?? [])
                            .whereType<Map>()
                            .toList();
                        final last =
                            (pagination['last_page'] as num?)?.toInt() ?? 1;
                        return Column(
                          children: [
                            if (widget.teamId != null &&
                                data['can_write'] == true &&
                                mayWrite)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => TeamMemberPicker(
                                          team: widget.teamId!,
                                          onAdded: () => ref.invalidate(
                                            organizationPageProvider(query),
                                          ),
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.person_add_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Add member'),
                                  ),
                                ),
                              ),
                            if (widget.teamId == null &&
                                data['can_write'] == true &&
                                mayWrite)
                              Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: FilledButton.icon(
                                    onPressed: () => editItem(query),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: Text(
                                      kind == 'projects'
                                          ? 'New project'
                                          : 'New team',
                                    ),
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
                                    vertical: 12,
                                  ),
                                  itemCount: items.isEmpty ? 1 : items.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    if (items.isEmpty) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 40,
                                        ),
                                        child: Text(
                                          'No results found.',
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    }
                                    final item = items[index];
                                    final archived =
                                        item['archived_at'] != null;
                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                      leading: Icon(
                                        widget.teamId != null
                                            ? Icons.person_outline
                                            : kind == 'teams'
                                            ? Icons.groups_outlined
                                            : Icons.folder_outlined,
                                        size: 22,
                                      ),
                                      title: Text(
                                        item['name']?.toString() ?? 'Unnamed',
                                      ),
                                      subtitle: Text(
                                        widget.teamId != null
                                            ? '${item['email'] ?? ''}${item['active'] == false ? ' · Inactive' : ''}${(data['team'] as Map?)?['leader_membership_id'] == item['id'] ? ' · Team lead' : ''}'
                                            : '${archived ? 'Archived' : 'Active'}${kind == 'teams' ? ' · ${item['members_count'] ?? 0} members' : ''}${item['description'] == null ? '' : '\n${item['description']}'}',
                                      ),
                                      trailing:
                                          widget.teamId != null &&
                                              data['can_manage'] == true &&
                                              mayReduce
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (data['can_write'] == true &&
                                                    mayWrite)
                                                  IconButton(
                                                    tooltip:
                                                        (data['team']
                                                                as Map?)?['leader_membership_id'] ==
                                                            item['id']
                                                        ? 'Remove team lead'
                                                        : 'Set team lead',
                                                    onPressed:
                                                        removingMember ||
                                                            (item['active'] ==
                                                                    false &&
                                                                (data['team']
                                                                        as Map?)?['leader_membership_id'] !=
                                                                    item['id'])
                                                        ? null
                                                        : () => setTeamLeader(
                                                            query,
                                                            (data['team']
                                                                        as Map?)?['leader_membership_id'] ==
                                                                    item['id']
                                                                ? null
                                                                : (item['id']
                                                                          as num)
                                                                      .toInt(),
                                                          ),
                                                    icon: Icon(
                                                      (data['team']
                                                                  as Map?)?['leader_membership_id'] ==
                                                              item['id']
                                                          ? Icons.star
                                                          : Icons.star_border,
                                                      size: 20,
                                                    ),
                                                  ),
                                                IconButton(
                                                  tooltip: 'Remove from team',
                                                  onPressed: removingMember
                                                      ? null
                                                      : () => removeMember(
                                                          query,
                                                          item,
                                                        ),
                                                  icon: const Icon(
                                                    Icons
                                                        .person_remove_outlined,
                                                    size: 20,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : widget.teamId == null &&
                                                data['can_manage'] == true &&
                                                mayReduce
                                          ? PopupMenuButton<String>(
                                              tooltip: 'Manage item',
                                              onSelected: (action) => editItem(
                                                query,
                                                item: item,
                                                archive: action == 'edit'
                                                    ? null
                                                    : !archived,
                                              ),
                                              itemBuilder: (_) => [
                                                if (data['can_write'] == true &&
                                                    mayWrite)
                                                  const PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text('Edit'),
                                                  ),
                                                if (!archived ||
                                                    data['can_write'] == true &&
                                                        mayWrite)
                                                  PopupMenuItem(
                                                    value: 'archive',
                                                    child: Text(
                                                      archived
                                                          ? 'Reactivate'
                                                          : 'Archive',
                                                    ),
                                                  ),
                                              ],
                                            )
                                          : widget.teamId == null &&
                                                kind == 'teams'
                                          ? const Icon(
                                              Icons.chevron_right,
                                              size: 18,
                                            )
                                          : null,
                                      onTap:
                                          widget.teamId == null &&
                                              kind == 'teams'
                                          ? () => Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    OrganizationPage(
                                                      teamId:
                                                          (item['id'] as num)
                                                              .toInt(),
                                                      teamName: item['name']
                                                          ?.toString(),
                                                    ),
                                              ),
                                            )
                                          : null,
                                    );
                                  },
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    tooltip: 'Previous page',
                                    onPressed: page > 1
                                        ? () => setState(() => page--)
                                        : null,
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  Flexible(
                                    child: Text(
                                      'Page $page of $last',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Next page',
                                    onPressed: page < last
                                        ? () => setState(() => page++)
                                        : null,
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
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
