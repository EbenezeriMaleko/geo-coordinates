import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../widget/app_backarrow.dart'; // adjust to your file name/path
import 'workspace_provider.dart';
import 'workspace_page_style.dart';
import 'company_invite_form.dart';
import 'company_member_editor.dart';
import 'company_ownership_page.dart';
import '../subscriptions/entitlement_provider.dart';

const Color _accent = Color(0xFF001F3F); // company accent
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _fieldFill = Color(0xFFF7F7F8);
const Color _amber = Color(0xFFB26A00);
const Color _amberSoft = Color(0xFFFFF4E0);
const Color _green = Color(0xFF1B7F4B);
const Color _greenSoft = Color(0xFFE6F5EC);

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

  // ── Logic (unchanged) ─────────────────────────────────────────

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

  // ── UI helpers ────────────────────────────────────────────────

  void _selectTab(bool isPending) {
    if (pending == isPending) return;
    setState(() {
      pending = isPending;
      page = 1;
      search = '';
      searchController.clear();
    });
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts[0][0].toUpperCase();
  }

  Widget _chip(String text, Color fg, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
    ),
  );

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _accent : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _memberCard(Map<String, dynamic> item) {
    final user = item['user'] is Map ? item['user'] as Map : const {};
    final name = user['name']?.toString() ?? 'Unavailable account';
    final email = user['email']?.toString();
    final isOwner = item['role'] == 'owner';
    final expiry = DateTime.tryParse(item['expires_at']?.toString() ?? '');
    final error = Theme.of(context).colorScheme.error;

    String? expiryText;
    Color expiryColor = Colors.black54;
    if (pending && expiry != null) {
      final local = expiry.toLocal();
      final date = MaterialLocalizations.of(context).formatMediumDate(local);
      if (local.isBefore(DateTime.now())) {
        expiryText = 'Expired on $date';
        expiryColor = error;
      } else if (local.difference(DateTime.now()).inDays <= 3) {
        expiryText = 'Expires soon · $date';
        expiryColor = _amber;
      } else {
        expiryText = 'Expires $date';
      }
    }

    final Widget statusChip;
    if (pending) {
      statusChip = _chip('Pending acceptance', _amber, _amberSoft);
    } else if (item['status'] == 'active') {
      statusChip = _chip('Active', _green, _greenSoft);
    } else {
      statusChip = _chip('Inactive', Colors.black54, const Color(0xFFF1F3F5));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isOwner ? _accent : _accent.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(name),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isOwner ? Colors.white : _accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    if (email != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isOwner) ...[
                                const HugeIcon(
                                  icon: HugeIcons.strokeRoundedCrown,
                                  color: _accent,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                companyRoleLabel(item['role']?.toString()),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: _accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        statusChip,
                      ],
                    ),
                  ],
                ),
              ),
              if (!pending && !isOwner)
                Material(
                  color: _accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => editMember(Map<String, dynamic>.from(item)),
                    child: const Tooltip(
                      message: 'Edit member access',
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Center(
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedEdit02,
                            color: _accent,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (expiryText != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFEEF1F4)),
            const SizedBox(height: 10),
            Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedCalendar03,
                  color: expiryColor,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Text(
                  expiryText,
                  style: TextStyle(fontSize: 12.5, color: expiryColor),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() {
    final searching = search.isNotEmpty;
    return Padding(
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
              icon: searching
                  ? HugeIcons.strokeRoundedSearch01
                  : pending
                  ? HugeIcons.strokeRoundedMail01
                  : HugeIcons.strokeRoundedUserGroup,
              color: _accent,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            searching
                ? 'No matching accounts'
                : pending
                ? 'No pending invitations'
                : 'No members found',
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          if (!searching && !pending) ...[
            const SizedBox(height: 6),
            const Text(
              'Invite people to join your company workspace.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pager(int current, int last) {
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
                tooltip: 'Previous directory page',
                onPressed: current > 1
                    ? () => setState(() => page = current - 1)
                    : null,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowLeft01,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
              Flexible(
                child: Text(
                  'Page $current of $last',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next directory page',
                onPressed: current < last
                    ? () => setState(() => page = current + 1)
                    : null,
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
    final session = ref.watch(authSessionProvider);
    final baseTheme = Theme.of(context);
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

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: _accent),
      ),
      child: WorkspaceScaffold(
        company: true,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          leading: const AppBackButton(),
          title: const Text(
            'Company members',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              tooltip: 'Invite company member',
              onPressed: available ? invite : null,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedUserAdd01,
                color: available ? Colors.black87 : Colors.black26,
                size: 22,
              ),
            ),
            IconButton(
              tooltip: 'Refresh directory',
              onPressed: available ? refresh : null,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedRefresh,
                color: available ? Colors.black87 : Colors.black26,
                size: 22,
              ),
            ),
            if (available &&
                canTransferCompanyOwnership(workspace, session.user?.role))
              PopupMenuButton<String>(
                tooltip: 'Company actions',
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedMoreVertical,
                  color: Colors.black87,
                  size: 22,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (_) => transferOwnership(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'transfer',
                    child: Row(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedExchange01,
                          color: Colors.black87,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Text('Transfer ownership'),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: ColoredBox(
          color: _pageBackground,
          child: !available
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedShield01,
                          color: Colors.black26,
                          size: 40,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Company or access changed. Reopen the directory from your company workspace.',
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
                    // Header: workspace, tabs, search
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
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F3F5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                _segment(
                                  'Members',
                                  !pending,
                                  () => _selectTab(false),
                                ),
                                _segment(
                                  'Pending invitations',
                                  pending,
                                  () => _selectTab(true),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: searchController,
                            decoration: InputDecoration(
                              hintText: 'Search name or email',
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
                              suffixIcon: search.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: () => setState(() {
                                        searchController.clear();
                                        search = '';
                                        page = 1;
                                      }),
                                      icon: const HugeIcon(
                                        icon: HugeIcons.strokeRoundedCancel01,
                                        color: Colors.black45,
                                        size: 18,
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
                            onChanged: (value) => setState(() {
                              search = value.trim().toLowerCase();
                              page = 1;
                            }),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: _cardBorder),
                    Expanded(
                      child: result!.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, _) => Center(
                          child: Padding(
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
                                const Text(
                                  'Unable to load directory',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
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
                          final noun = pending
                              ? (matches.length == 1
                                    ? 'invitation'
                                    : 'invitations')
                              : (matches.length == 1 ? 'member' : 'members');
                          return Column(
                            children: [
                              Expanded(
                                child: RefreshIndicator(
                                  onRefresh: refresh,
                                  child: ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      14,
                                      16,
                                      24,
                                    ),
                                    children: [
                                      if (visible.isEmpty)
                                        _emptyState()
                                      else ...[
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            4,
                                            0,
                                            4,
                                            10,
                                          ),
                                          child: Text(
                                            '${matches.length} $noun',
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                        for (final item in visible)
                                          _memberCard(item),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              if (last > 1) _pager(current, last),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}