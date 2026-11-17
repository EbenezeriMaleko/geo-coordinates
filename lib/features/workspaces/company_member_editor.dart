import '../widget/plan_access_lock.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../subscriptions/entitlement_provider.dart';
import 'company_invite_form.dart';
import 'workspace_page_style.dart';
import 'workspace_provider.dart';

class CompanyMemberService {
  Future<void> change(
    String token,
    int company,
    int membership,
    Map<String, dynamic>? changes,
  ) async {
    final path = '/companies/$company/members/$membership';
    final response = changes == null
        ? await ApiClient.deleteJson(path, bearerToken: token)
        : await ApiClient.patchJson(path, bearerToken: token, body: changes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body);
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to update membership.'
            : 'Unable to update membership.',
      );
    }
  }
}

final companyMemberServiceProvider = Provider<CompanyMemberService>(
  (ref) => CompanyMemberService(),
);

class CompanyMemberEditor extends ConsumerStatefulWidget {
  const CompanyMemberEditor({
    super.key,
    required this.company,
    required this.member,
  });
  final int company;
  final Map<String, dynamic> member;
  @override
  ConsumerState<CompanyMemberEditor> createState() =>
      _CompanyMemberEditorState();
}

class _CompanyMemberEditorState extends ConsumerState<CompanyMemberEditor> {
  late final String token = ref.read(authSessionProvider).token;
  late bool active = widget.member['status'] == 'active';
  late String? role = widget.member['role']?.toString();
  bool busy = false;
  bool confirming = false;
  String? error;
  bool get wasActive => widget.member['status'] == 'active';
  bool get owner => widget.member['role'] == 'owner';

  bool get available {
    final session = ref.read(authSessionProvider);
    final workspace = ref.read(workspaceProvider);
    return !owner &&
        session.isLoggedIn &&
        session.isVerified &&
        session.token == token &&
        workspace.activeCompanyId == widget.company &&
        canViewCompanyDirectory(workspace, session.user?.role);
  }

  Future<void> submit({bool remove = false}) async {
    if (busy || confirming || !available) return;
    final id = int.tryParse(widget.member['id'].toString());
    if (id == null) return;
    final changes = <String, dynamic>{
      if (role != widget.member['role']) 'role': role,
      if (active != wasActive) 'status': active ? 'active' : 'inactive',
    };
    if (!remove && changes.isEmpty) return;
    final featureAllowed =
        ref
            .read(entitlementProvider)
            .asData
            ?.value['company.employee_management']
            ?.allowed ==
        true;
    if (!remove &&
        (changes.containsKey('role') || changes['status'] == 'active') &&
        !featureAllowed) {
      return;
    }
    if (!remove && (active || changes.containsKey('role'))) {
      final roles =
          ref.read(companyInviteRolesProvider(widget.company)).asData?.value ??
          [];
      if (!roles.contains(role) &&
          !(wasActive && role == widget.member['role'])) {
        return;
      }
    }
    confirming = true;
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            remove ? 'Remove company member?' : 'Update company access?',
          ),
          content: Text(
            remove
                ? 'This removes company membership, not the account or saved company records.'
                : 'Role: ${companyRoleLabel(role)}\nAccess: ${active ? 'Active' : 'Inactive'}',
          ),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(remove ? 'Remove member' : 'Update access'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      );
    } finally {
      confirming = false;
    }
    if (!mounted || confirmed != true || !available) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(companyMemberServiceProvider)
          .change(token, widget.company, id, remove ? null : changes);
      if (!mounted || !available) return;
      Navigator.pop(context, true);
    } catch (failure) {
      if (mounted && available) {
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
    ref.watch(authSessionProvider);
    ref.watch(workspaceProvider);
    final allowed = available;
    final options = allowed
        ? ref.watch(companyInviteRolesProvider(widget.company))
        : null;
    final access = allowed ? ref.watch(entitlementProvider) : null;
    final canExpand =
        access?.asData?.value['company.employee_management']?.allowed == true;
    final choices = {
      ...?options?.asData?.value,
      if (wasActive && !owner && widget.member['role'] is String)
        widget.member['role'] as String,
    }.toList();
    final currentRole = choices.contains(role) ? role : null;
    final user = widget.member['user'] is Map
        ? widget.member['user'] as Map
        : const {};
    final changed = role != widget.member['role'] || active != wasActive;
    final canSave =
        changed &&
        (!active || currentRole != null) &&
        (role == widget.member['role'] ||
            (canExpand && options?.asData?.value.contains(role) == true)) &&
        (!active || wasActive || canExpand);
    return PopScope(
      canPop: !busy,
      child: WorkspaceScaffold(
        company: true,
        appBar: AppBar(title: const Text('Member access')),
        body: !allowed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    owner
                        ? 'Ownership must be transferred before changing this membership.'
                        : 'Company or session changed. Reopen the member.',
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    user['name']?.toString() ?? 'Company member',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (user['email'] != null) Text(user['email'].toString()),
                  const SizedBox(height: 24),
                  if (options?.isLoading == true)
                    const Center(child: CircularProgressIndicator())
                  else if (options?.hasError == true)
                    TextButton(
                      onPressed: () => ref.invalidate(
                        companyInviteRolesProvider(widget.company),
                      ),
                      child: const Text('Unable to load roles. Retry'),
                    ),
                  PlanAccessLock(
                    locked:
                        !busy &&
                        access
                                ?.asData
                                ?.value['company.employee_management']
                                ?.allowed ==
                            false,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(currentRole),
                      initialValue: currentRole,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Company role',
                      ),
                      items: [
                        for (final value in choices)
                          DropdownMenuItem(
                            value: value,
                            child: Text(companyRoleLabel(value)),
                          ),
                      ],
                      onChanged: canExpand && !busy && options?.hasValue == true
                          ? (value) => setState(() => role = value)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  PlanAccessLock(
                    locked:
                        !busy &&
                        !wasActive &&
                        access
                                ?.asData
                                ?.value['company.employee_management']
                                ?.allowed ==
                            false,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active access'),
                      value: active,
                      onChanged: !busy && (wasActive || canExpand)
                          ? (value) => setState(() => active = value)
                          : null,
                    ),
                  ),
                  if (!canExpand) ...[
                    Text(
                      access?.isLoading == true
                          ? 'Checking employee-management access...'
                          : access?.hasError == true
                          ? 'Unable to verify employee-management access. Refresh to retry.'
                          : 'Role changes and activation require employee-management access. Deactivation and removal remain available.',
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              ref.invalidate(entitlementProvider);
                              ref.invalidate(workspaceAccessSnapshotProvider);
                            },
                      child: const Text('Refresh access'),
                    ),
                  ],
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
                    onPressed: !busy && canSave ? submit : null,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(busy ? 'Saving...' : 'Save changes'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => submit(remove: true),
                    icon: const Icon(Icons.person_remove_outlined, size: 18),
                    label: const Text('Remove member'),
                  ),
                ],
              ),
      ),
    );
  }
}
