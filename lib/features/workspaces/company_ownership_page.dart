import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'company_invite_form.dart';
import 'workspace_provider.dart';
import 'workspace_page_style.dart';

List<Map<String, dynamic>> ownershipCandidates(
  List<Map<String, dynamic>> members,
) => members
    .where(
      (member) =>
          member['status'] == 'active' &&
          member['role'] != 'owner' &&
          int.tryParse(member['id'].toString()) != null,
    )
    .toList();

class CompanyOwnershipService {
  Future<List<Map<String, dynamic>>> candidates(
    String token,
    int company,
  ) async {
    final body = await CompanyInviteService().get(
      '/companies/$company/members',
      token,
    );
    if (body['data'] is! List) throw Exception('Unexpected member response.');
    return ownershipCandidates(
      (body['data'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
  }

  Future<void> transfer(String token, int company, int membership) async {
    final response = await ApiClient.postJson(
      '/companies/$company/transfer-ownership',
      bearerToken: token,
      body: {'membership_id': membership},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body);
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to transfer ownership.'
            : 'Unable to transfer ownership.',
      );
    }
  }
}

final companyOwnershipServiceProvider = Provider<CompanyOwnershipService>(
  (ref) => CompanyOwnershipService(),
);
final companyOwnershipCandidatesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, company) async {
      final session = ref.watch(authSessionProvider);
      final workspace = ref.watch(workspaceProvider);
      if (!session.isLoggedIn ||
          !session.isVerified ||
          workspace.activeCompanyId != company ||
          !canTransferCompanyOwnership(workspace, session.user?.role)) {
        throw Exception('Ownership transfer is unavailable.');
      }
      return ref
          .read(companyOwnershipServiceProvider)
          .candidates(session.token, company);
    });

class CompanyOwnershipPage extends ConsumerStatefulWidget {
  const CompanyOwnershipPage({super.key, required this.company});
  final int company;
  @override
  ConsumerState<CompanyOwnershipPage> createState() =>
      _CompanyOwnershipPageState();
}

class _CompanyOwnershipPageState extends ConsumerState<CompanyOwnershipPage> {
  late final token = ref.read(authSessionProvider).token;
  String search = '';
  int? selected;
  bool busy = false;
  bool confirming = false;
  String? error;
  bool get available {
    final session = ref.read(authSessionProvider);
    final workspace = ref.read(workspaceProvider);
    return session.isLoggedIn &&
        session.isVerified &&
        session.token == token &&
        workspace.activeCompanyId == widget.company &&
        canTransferCompanyOwnership(workspace, session.user?.role);
  }

  Future<void> transfer(Map<String, dynamic> member) async {
    if (busy || confirming || !available) return;
    final id = int.tryParse(member['id'].toString());
    if (id == null) return;
    final name = member['user'] is Map
        ? member['user']['name']?.toString() ?? 'This member'
        : 'This member';
    confirming = true;
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Transfer company ownership?'),
          content: Text(
            '$name will become the company owner. The current owner will become a company administrator. Saved company records will remain unchanged.',
          ),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Transfer ownership'),
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
          .read(companyOwnershipServiceProvider)
          .transfer(token, widget.company, id);
      if (!mounted ||
          token != ref.read(authSessionProvider).token ||
          widget.company != ref.read(workspaceProvider).activeCompanyId) {
        return;
      }
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
    final workspace = ref.watch(workspaceProvider);
    final allowed = available;
    final options = allowed
        ? ref.watch(companyOwnershipCandidatesProvider(widget.company))
        : null;
    return PopScope(
      canPop: !busy,
      child: WorkspaceScaffold(
        company: true,
        appBar: AppBar(title: const Text('Transfer ownership')),
        body: !allowed
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Only the current owner or a platform administrator can transfer ownership. Reopen this page if your workspace changed.',
                  ),
                ),
              )
            : options!.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: TextButton.icon(
                    onPressed: () => ref.invalidate(
                      companyOwnershipCandidatesProvider(widget.company),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Unable to load members. Retry'),
                  ),
                ),
                data: (raw) {
                  final members = ownershipCandidates(raw);
                  final visible = members.where((member) {
                    final user = member['user'] is Map
                        ? member['user'] as Map
                        : const {};
                    return '${user['name'] ?? ''} ${user['email'] ?? ''}'
                        .toLowerCase()
                        .contains(search);
                  }).toList();
                  final target = members
                      .where(
                        (member) =>
                            int.tryParse(member['id'].toString()) == selected,
                      )
                      .firstOrNull;
                  return SafeArea(
                    child: Column(
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
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: TextField(
                            enabled: !busy,
                            decoration: const InputDecoration(
                              hintText: 'Search name or email',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (value) => setState(() {
                              search = value.trim().toLowerCase();
                              selected = null;
                            }),
                          ),
                        ),
                        Expanded(
                          child: visible.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Text(
                                      members.isEmpty
                                          ? 'No other active members are eligible. Invite and activate a member first.'
                                          : 'No matching members.',
                                    ),
                                  ),
                                )
                              : RadioGroup<int>(
                                  groupValue: selected,
                                  onChanged: (value) {
                                    if (!busy) setState(() => selected = value);
                                  },
                                  child: ListView.builder(
                                    itemCount: visible.length,
                                    itemBuilder: (context, index) {
                                      final member = visible[index];
                                      final user = member['user'] is Map
                                          ? member['user'] as Map
                                          : const {};
                                      return RadioListTile<int>(
                                        value: int.parse(
                                          member['id'].toString(),
                                        ),
                                        enabled: !busy,
                                        title: Text(
                                          user['name']?.toString() ?? 'Member',
                                        ),
                                        subtitle: Text(
                                          '${user['email'] ?? ''}\n${companyRoleLabel(member['role']?.toString())}',
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: !busy && target != null
                                  ? () => transfer(target)
                                  : null,
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              label: Text(
                                busy ? 'Transferring...' : 'Transfer ownership',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
