import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../subscriptions/entitlement_provider.dart';
import 'workspace_provider.dart';
import 'workspace_page_style.dart';

List<String> parseCompanyInvitationRoles(dynamic raw) => raw is List
    ? raw
          .whereType<String>()
          .where(
            const [
              'admin',
              'employee',
              'field_operator',
              'reviewer',
              'viewer',
            ].contains,
          )
          .toSet()
          .toList()
    : [];

class CompanyInviteService {
  Future<Map<String, dynamic>> get(
    String path,
    String token, {
    Map<String, dynamic>? query,
  }) async {
    final response = await ApiClient.getJson(
      path,
      bearerToken: token,
      queryParameters: query,
    );
    final body = jsonDecode(response.body);
    if (response.statusCode != 200 || body is! Map) {
      throw Exception('Unable to load invitation options.');
    }
    return Map<String, dynamic>.from(body);
  }

  Future<List<String>> roles(String token, int company) async =>
      parseCompanyInvitationRoles(
        (await get('/companies/$company/members', token))['assignable_roles'],
      );

  Future<List<Map<String, dynamic>>> search(
    String token,
    int company,
    String query,
  ) async {
    final body = await get(
      '/companies/$company/users',
      token,
      query: {'query': query},
    );
    if (body['data'] is! List) {
      throw Exception('Unexpected account search response.');
    }
    return (body['data'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<bool?> invite(String token, int company, int user, String role) async {
    final response = await ApiClient.postJson(
      '/companies/$company/invitations',
      bearerToken: token,
      body: {'user_id': user, 'role': role},
    );
    final body = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to create invitation.'
            : 'Unable to create invitation.',
      );
    }
    final data = body is Map ? body['data'] : null;
    return data is Map && data['email_delivered'] is bool
        ? data['email_delivered'] as bool
        : null;
  }
}

final companyInviteServiceProvider = Provider<CompanyInviteService>(
  (ref) => CompanyInviteService(),
);
final companyInviteRolesProvider = FutureProvider.autoDispose
    .family<List<String>, int>((ref, company) async {
      final session = ref.watch(authSessionProvider);
      final workspace = ref.watch(workspaceProvider);
      if (!session.isVerified ||
          !session.isLoggedIn ||
          workspace.activeCompanyId != company ||
          !canViewCompanyDirectory(workspace, session.user?.role)) {
        throw Exception('Company access changed.');
      }
      return ref
          .read(companyInviteServiceProvider)
          .roles(session.token, company);
    });
typedef InviteSearchQuery = ({int company, String search});
final companyInviteSearchProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, InviteSearchQuery>((ref, query) async {
      final session = ref.watch(authSessionProvider);
      final workspace = ref.watch(workspaceProvider);
      if (!session.isVerified ||
          !session.isLoggedIn ||
          workspace.activeCompanyId != query.company ||
          !canViewCompanyDirectory(workspace, session.user?.role)) {
        throw Exception('Company access changed.');
      }
      if (query.search.length < 2) return [];
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!ref.mounted) return [];
      return ref
          .read(companyInviteServiceProvider)
          .search(session.token, query.company, query.search);
    });

class CompanyInviteForm extends ConsumerStatefulWidget {
  const CompanyInviteForm({super.key, required this.company});
  final int company;
  @override
  ConsumerState<CompanyInviteForm> createState() => _CompanyInviteFormState();
}

class _CompanyInviteFormState extends ConsumerState<CompanyInviteForm> {
  String search = '';
  Map<String, dynamic>? selected;
  String? role;
  String? error;
  bool busy = false;

  Future<void> send(List<String> roles, String selectedRole) async {
    if (busy || selected == null || !roles.contains(selectedRole)) return;
    final user = int.tryParse(selected!['id'].toString());
    if (user == null) return;
    final session = ref.read(authSessionProvider);
    final workspace = ref.read(workspaceProvider);
    if (!session.isLoggedIn ||
        !session.isVerified ||
        workspace.activeCompanyId != widget.company ||
        !canViewCompanyDirectory(workspace, session.user?.role) ||
        ref
                .read(entitlementProvider)
                .asData
                ?.value['company.employee_management']
                ?.allowed !=
            true) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final delivered = await ref
          .read(companyInviteServiceProvider)
          .invite(session.token, widget.company, user, selectedRole);
      if (!mounted ||
          session.token != ref.read(authSessionProvider).token ||
          widget.company != ref.read(workspaceProvider).activeCompanyId) {
        return;
      }
      Navigator.pop(
        context,
        delivered == true
            ? 'Invitation created and email delivered.'
            : delivered == false
            ? 'Invitation created. Email delivery failed; the user can still accept it in the app.'
            : 'Invitation created. Email delivery is not confirmed.',
      );
    } catch (failure) {
      if (mounted &&
          session.token == ref.read(authSessionProvider).token &&
          widget.company == ref.read(workspaceProvider).activeCompanyId) {
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
    final session = ref.watch(authSessionProvider);
    final available =
        session.isLoggedIn &&
        session.isVerified &&
        workspace.activeCompanyId == widget.company &&
        canViewCompanyDirectory(workspace, session.user?.role);
    final access = ref.watch(entitlementProvider);
    final allowed =
        available &&
        access.asData?.value['company.employee_management']?.allowed == true;
    final options = available
        ? ref.watch(companyInviteRolesProvider(widget.company))
        : null;
    final roles = options?.asData?.value ?? <String>[];
    final selectedRole = roles.contains(role) ? role : roles.firstOrNull;
    final query = (company: widget.company, search: search);
    final results = allowed && search.length >= 2 && selected == null
        ? ref.watch(companyInviteSearchProvider(query))
        : null;
    return PopScope(
      canPop: !busy,
      child: WorkspaceScaffold(
        company: true,
        appBar: AppBar(title: const Text('Invite company member')),
        body: !available
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Company or session changed. Reopen the invitation form.',
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    workspace.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 16),
                  if (!allowed) ...[
                    Text(
                      access.isLoading
                          ? 'Checking invitation access...'
                          : access.hasError
                          ? 'Unable to verify invitation access.'
                          : 'Invitations are not available with your current company access.',
                    ),
                    TextButton(
                      onPressed: () {
                        ref.invalidate(entitlementProvider);
                        ref.invalidate(workspaceAccessSnapshotProvider);
                      },
                      child: const Text('Refresh access'),
                    ),
                  ],
                  TextField(
                    enabled: allowed && !busy,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Find account',
                      hintText: 'Name or email',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() {
                      search = value.trim();
                      selected = null;
                      error = null;
                    }),
                  ),
                  if (results != null)
                    results.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, _) => TextButton(
                        onPressed: () =>
                            ref.invalidate(companyInviteSearchProvider(query)),
                        child: const Text('Unable to find accounts. Retry'),
                      ),
                      data: (users) => Column(
                        children: [
                          if (users.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('No matching accounts.'),
                            ),
                          for (final user in users)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.person_outline),
                              title: Text(
                                user['name']?.toString() ?? 'Account',
                              ),
                              subtitle: Text(user['email']?.toString() ?? ''),
                              trailing: const Icon(Icons.add),
                              onTap: busy
                                  ? null
                                  : () => setState(() => selected = user),
                            ),
                        ],
                      ),
                    ),
                  if (selected != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(
                        selected!['name']?.toString() ?? 'Selected account',
                      ),
                      subtitle: Text(selected!['email']?.toString() ?? ''),
                      trailing: IconButton(
                        tooltip: 'Clear selected account',
                        onPressed: busy
                            ? null
                            : () => setState(() => selected = null),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (options?.isLoading == true)
                    const Center(child: CircularProgressIndicator())
                  else if (options?.hasError == true)
                    TextButton(
                      onPressed: () => ref.invalidate(
                        companyInviteRolesProvider(widget.company),
                      ),
                      child: const Text('Unable to load roles. Retry'),
                    )
                  else if (roles.isEmpty)
                    const Text(
                      'No invitation roles are enabled in the company plan.',
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      key: ValueKey(selectedRole),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Company role',
                      ),
                      items: [
                        for (final value in roles)
                          DropdownMenuItem(
                            value: value,
                            child: Text(companyRoleLabel(value)),
                          ),
                      ],
                      onChanged: allowed && !busy
                          ? (value) => setState(() => role = value)
                          : null,
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
                    onPressed:
                        allowed &&
                            !busy &&
                            selected != null &&
                            selectedRole != null
                        ? () => send(roles, selectedRole)
                        : null,
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: Text(busy ? 'Sending...' : 'Send invitation'),
                  ),
                ],
              ),
      ),
    );
  }
}
