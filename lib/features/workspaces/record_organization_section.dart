import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../subscriptions/entitlement_provider.dart';
import '../land_map/providers/land_cloud_provider.dart';
import 'workspace_provider.dart';
import 'field_job_link_picker.dart';

typedef RecordAssignmentQuery = ({int company, String record});

final recordAssignmentProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, RecordAssignmentQuery>((ref, query) async {
      final workspace = ref.watch(workspaceProvider);
      final session = ref.watch(authSessionProvider);
      if (workspace.activeCompanyId != query.company ||
          workspace.isLoading ||
          !session.isVerified) {
        throw Exception('Workspace changed. Reopen the record.');
      }
      final response = await ApiClient.getJson(
        '/organization/records/${query.record}/assignment',
        bearerToken: session.token,
      );
      if (response.statusCode != 200) {
        throw Exception('Record organization is unavailable.');
      }
      final body = jsonDecode(response.body) as Map;
      return Map<String, dynamic>.from(body['data'] as Map? ?? {});
    });

class RecordOrganizationSection extends ConsumerStatefulWidget {
  const RecordOrganizationSection({
    super.key,
    required this.company,
    required this.record,
    required this.canManage,
    this.onChanged,
  });
  final int company;
  final String record;
  final bool canManage;
  final Future<void> Function()? onChanged;

  @override
  ConsumerState<RecordOrganizationSection> createState() =>
      _RecordOrganizationSectionState();
}

class _RecordOrganizationSectionState
    extends ConsumerState<RecordOrganizationSection> {
  bool busy = false;
  String? error;

  Future<void> change(bool team, {bool clear = false}) async {
    if (busy) return;
    final token = ref.read(authSessionProvider).token;
    int? id;
    if (!clear) {
      final selected = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => FieldJobLinkPicker(
            company: widget.company,
            project: !team,
            team: team,
          ),
        ),
      );
      if (!mounted || selected == null) return;
      id = int.tryParse(selected['id'].toString());
      if (id == null) return;
    }
    if (!mounted ||
        widget.company != ref.read(workspaceProvider).activeCompanyId ||
        token != ref.read(authSessionProvider).token) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = await ApiClient.patchJson(
        '/organization/records/${widget.record}/assignment',
        bearerToken: token,
        body: {team ? 'company_team_id' : 'company_project_id': id},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = jsonDecode(response.body);
        throw Exception(
          body is Map
              ? body['message'] ?? 'Unable to save assignment.'
              : 'Unable to save assignment.',
        );
      }
      if (!mounted ||
          widget.company != ref.read(workspaceProvider).activeCompanyId ||
          token != ref.read(authSessionProvider).token) {
        return;
      }
      ref.invalidate(
        recordAssignmentProvider((
          company: widget.company,
          record: widget.record,
        )),
      );
      await widget.onChanged?.call();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    if (workspace.activeCompanyId != widget.company || workspace.isLoading) {
      return const SizedBox.shrink();
    }
    final query = (company: widget.company, record: widget.record);
    final assignment = ref.watch(recordAssignmentProvider(query));
    final permissions = ref.watch(workspacePermissionsProvider).asData?.value;
    final features = ref.watch(entitlementProvider).asData?.value;
    final manageable =
        widget.canManage &&
        ref
                .watch(remoteLandDetailProvider(widget.record))
                .asData
                ?.value
                .canManage ==
            true;
    final manager = manageable && permissions?['organization.manage'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        Text(
          'Record organization',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        assignment.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => TextButton.icon(
            onPressed: () => ref.invalidate(recordAssignmentProvider(query)),
            icon: const Icon(Icons.refresh),
            label: const Text('Organization unavailable. Retry'),
          ),
          data: (data) => Column(
            children: [
              for (final team in [false, true])
                Builder(
                  builder: (context) {
                    final kind = team ? 'team' : 'project';
                    final assigned = data['company_${kind}_id'] != null;
                    final writable =
                        manager &&
                        features?['company.${team ? 'teams' : 'projects'}']
                                ?.allowed ==
                            true &&
                        features?['land.view_and_edit']?.allowed == true;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        team ? Icons.groups_outlined : Icons.folder_outlined,
                        size: 22,
                      ),
                      title: Text(
                        data['${kind}_name']?.toString() ??
                            (assigned
                                ? 'Unavailable $kind'
                                : 'No $kind assigned'),
                      ),
                      subtitle: Text(
                        data['${kind}_archived'] == true
                            ? 'Archived $kind'
                            : team
                            ? 'Team'
                            : 'Project',
                      ),
                      onTap: writable && !busy ? () => change(team) : null,
                      trailing: !writable
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (assigned)
                                  IconButton(
                                    tooltip: 'Unassign $kind',
                                    onPressed: busy
                                        ? null
                                        : () => change(team, clear: true),
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                IconButton(
                                  tooltip: 'Assign $kind',
                                  onPressed: busy ? null : () => change(team),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
            ],
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
