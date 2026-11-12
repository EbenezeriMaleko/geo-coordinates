import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'workspace_provider.dart';
import 'workspace_page_style.dart';
import 'company_invite_form.dart';
import 'company_member_editor.dart';
import 'company_ownership_page.dart';
import '../subscriptions/entitlement_provider.dart';

class CompanyDirectoryService {
  Future<List<Map<String, dynamic>>> list(
    String token,
    int company,
    bool pending,
  ) async {
    final response = await ApiClient.getJson(
      '/companies/$company/${pending ? 'invitations' : 'members'}',
      bearerToken: token,
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load company directory.');
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['data'] is! List) {
      throw Exception('Unexpected company directory response.');
    }
    return (body['data'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

final companyDirectoryServiceProvider = Provider<CompanyDirectoryService>(
  (ref) => CompanyDirectoryService(),
);
typedef CompanyDirectoryQuery = ({int company, bool pending});
final companyDirectoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, CompanyDirectoryQuery>((
      ref,
      query,
    ) async {
      final session = ref.watch(authSessionProvider);
      final workspace = ref.watch(workspaceProvider);
      if (!session.isLoggedIn ||
          !session.isVerified ||
          workspace.activeCompanyId != query.company ||
          !canViewCompanyDirectory(workspace, session.user?.role)) {
        throw Exception('Company directory access is unavailable.');
      }
      return ref
          .read(companyDirectoryServiceProvider)
          .list(session.token, query.company, query.pending);
    });

class CompanyMembersPage extends ConsumerStatefulWidget {
  const CompanyMembersPage({super.key});
  @override
  ConsumerState<CompanyMembersPage> createState() => _CompanyMembersPageState();
}

class _CompanyMembersPageState extends ConsumerState<CompanyMembersPage> {
  late final int? company = ref.read(workspaceProvider).activeCompanyId;
  bool pending = false;
  String search = '';
  int page = 1;
  final searchController = TextEditingController();
  Future<void> editMember(Map<String, dynamic> member) async {
    final token = ref.read(authSessionProvider).token;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CompanyMemberEditor(company: company!, member: member),
      ),
    );
    if (!mounted ||
        changed != true ||
        company != ref.read(workspaceProvider).activeCompanyId ||
        token != ref.read(authSessionProvider).token) {
      return;
    }
    await refreshCompanyAccess(token, 'Company membership updated.');
  }

  Future<void> transferOwnership() async {
    final token = ref.read(authSessionProvider).token;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CompanyOwnershipPage(company: company!),
      ),
    );
    if (!mounted ||
        changed != true ||
        token != ref.read(authSessionProvider).token ||
        company != ref.read(workspaceProvider).activeCompanyId) {
      return;
    }
    await refreshCompanyAccess(token, 'Company ownership transferred.');
  }

  Future<void> refreshCompanyAccess(String token, String message) async {
    ref.invalidate(
      companyDirectoryProvider((company: company!, pending: false)),
    );
    ref.invalidate(
      companyDirectoryProvider((company: company!, pending: true)),
    );
    ref.invalidate(companyInviteRolesProvider(company!));
    ref.invalidate(companyOwnershipCandidatesProvider(company!));
    await ref.read(workspaceProvider.notifier).refresh();
    if (!mounted || token != ref.read(authSessionProvider).token) return;
    ref.invalidate(entitlementProvider);
    ref.invalidate(workspaceAccessSnapshotProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> invite() async {
    final token = ref.read(authSessionProvider).token;
    if (!await checkFeatureAccess(
          context,
          ref,
          'company.employee_management',
        ) ||
        !mounted ||
        company != ref.read(workspaceProvider).activeCompanyId ||
        token != ref.read(authSessionProvider).token) {
      return;
    }
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => CompanyInviteForm(company: company!)),
    );
    if (!mounted ||
        message == null ||
        company != ref.read(workspaceProvider).activeCompanyId ||
        token != ref.read(authSessionProvider).token) {
      return;
    }
    ref.invalidate(
      companyDirectoryProvider((company: company!, pending: true)),
    );
    ref.invalidate(
      companyDirectoryProvider((company: company!, pending: false)),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final session = ref.watch(authSessionProvider);
    final available =
        session.isLoggedIn &&
        session.isVerified &&
        company != null &&
        workspace.activeCompanyId == company &&
        canViewCompanyDirectory(workspace, session.user?.role);
    final query = (company: company ?? 0, pending: pending);
    final result = available
        ? ref.watch(companyDirectoryProvider(query))
        : null;
    Future<void> refresh() async {
      ref.invalidate(companyDirectoryProvider(query));
      try {
        await ref.read(companyDirectoryProvider(query).future);
      } catch (_) {}
    }

    return WorkspaceScaffold(
      company: true,
      appBar: AppBar(
        title: const Text('Company members'),
        actions: [
          if (available &&
              canTransferCompanyOwnership(workspace, session.user?.role))
            PopupMenuButton<String>(
              tooltip: 'Company actions',
              onSelected: (_) => transferOwnership(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'transfer',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.swap_horiz, size: 20),
                    title: Text('Transfer ownership'),
                  ),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Invite company member',
            onPressed: available ? invite : null,
            icon: const Icon(Icons.person_add_outlined),
          ),
          IconButton(
            tooltip: 'Refresh directory',
            onPressed: available ? refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !available
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Company or access changed. Reopen the directory from your company workspace.',
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
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                DefaultTabController(
                  length: 2,
                  initialIndex: pending ? 1 : 0,
                  child: TabBar(
                    onTap: (index) => setState(() {
                      pending = index == 1;
                      page = 1;
                      search = '';
                      searchController.clear();
                    }),
                    tabs: const [
                      Tab(text: 'Members'),
                      Tab(text: 'Pending invitations'),
                    ],
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search name or email',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() {
                      search = value.trim().toLowerCase();
                      page = 1;
                    }),
                  ),
                ),
                Expanded(
                  child: result!.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => Center(
                      child: TextButton.icon(
                        onPressed: refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Unable to load directory. Retry'),
                      ),
                    ),
                    data: (items) {
                      final matches = items.where((item) {
                        final user = item['user'] is Map
                            ? item['user'] as Map
                            : const {};
                        return '${user['name'] ?? ''} ${user['email'] ?? ''}'
                            .toLowerCase()
                            .contains(search);
                      }).toList();
                      final last = ((matches.length + 19) ~/ 20).clamp(
                        1,
                        1000000,
                      );
                      final current = page.clamp(1, last);
                      final visible = matches
                          .skip((current - 1) * 20)
                          .take(20)
                          .toList();
                      return Column(
                        children: [
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: refresh,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                itemCount: visible.isEmpty ? 1 : visible.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  if (visible.isEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 40,
                                      ),
                                      child: Text(
                                        search.isNotEmpty
                                            ? 'No matching accounts.'
                                            : pending
                                            ? 'No pending invitations.'
                                            : 'No members found.',
                                      ),
                                    );
                                  }
                                  final item = visible[index];
                                  final user = item['user'] is Map
                                      ? item['user'] as Map
                                      : const {};
                                  final expiry = DateTime.tryParse(
                                    item['expires_at']?.toString() ?? '',
                                  );
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                user['name']?.toString() ??
                                                    'Unavailable account',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                            ),
                                            if (!pending &&
                                                item['role'] != 'owner')
                                              IconButton(
                                                tooltip: 'Edit member access',
                                                onPressed: () => editMember(
                                                  Map<String, dynamic>.from(
                                                    item,
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons
                                                      .manage_accounts_outlined,
                                                  size: 22,
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (user['email'] != null)
                                          Text(user['email'].toString()),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                              companyRoleLabel(
                                                item['role']?.toString(),
                                              ),
                                            ),
                                            Text(
                                              pending
                                                  ? 'Pending acceptance'
                                                  : item['status'] == 'active'
                                                  ? 'Active'
                                                  : 'Inactive',
                                              style: TextStyle(
                                                color: pending
                                                    ? const Color(0xFF925F16)
                                                    : const Color(0xFF667085),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (pending && expiry != null)
                                          Text(
                                            'Expires ${MaterialLocalizations.of(context).formatMediumDate(expiry.toLocal())}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                      ],
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
                                tooltip: 'Previous directory page',
                                onPressed: current > 1
                                    ? () => setState(() => page = current - 1)
                                    : null,
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Flexible(
                                child: Text(
                                  'Page $current of $last (${matches.length})',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Next directory page',
                                onPressed: current < last
                                    ? () => setState(() => page = current + 1)
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
    );
  }
}
