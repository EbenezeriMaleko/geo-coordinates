import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../widget/app_backarrow.dart'; // adjust to your file name/pat
import 'company_invite_form.dart';
import 'workspace_provider.dart';
import 'workspace_page_style.dart';

const Color _accent = Color(0xFF197568); // company accent
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _fieldFill = Color(0xFFF7F7F8);
const Color _amber = Color(0xFFB26A00);
const Color _amberSoft = Color(0xFFFFF4E0);

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

  // ── Logic (unchanged apart from the confirmation UI) ──────────

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
      confirmed = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _TransferSheet(name: name),
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

  // ── UI helpers ────────────────────────────────────────────────

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts[0][0].toUpperCase();
  }

  Widget _warningBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _amberSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedAlert02,
            color: _amber,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ownership transfer',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _amber,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Choose an active member to become the new owner. The current owner will become a company administrator.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberCard(Map<String, dynamic> member) {
    final user = member['user'] is Map ? member['user'] as Map : const {};
    final name = user['name']?.toString() ?? 'Member';
    final email = user['email']?.toString() ?? '';
    final id = int.parse(member['id'].toString());
    final isSelected = selected == id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : () => setState(() => selected = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? _accent.withValues(alpha: 0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? _accent : _cardBorder,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _accent,
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
                    if (email.isNotEmpty) ...[
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        companyRoleLabel(member['role']?.toString()),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? _accent : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? _accent : Colors.black26,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? const HugeIcon(
                        icon: HugeIcons.strokeRoundedTick02,
                        color: Colors.white,
                        size: 14,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(bool noEligible) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
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
              icon: noEligible
                  ? HugeIcons.strokeRoundedUserGroup
                  : HugeIcons.strokeRoundedSearch01,
              color: _accent,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            noEligible ? 'No eligible members' : 'No matching members',
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          if (noEligible) ...[
            const SizedBox(height: 6),
            const Text(
              'No other active members are eligible. Invite and activate a member first.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.4, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar(Map<String, dynamic>? target) {
    final scheme = Theme.of(context).colorScheme;
    final targetName = target?['user'] is Map
        ? (target!['user']['name']?.toString() ?? 'this member')
        : 'this member';
    final canSend = !busy && target != null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedAlert02,
                        color: scheme.error,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: scheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (target != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'New owner: $targetName',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canSend ? () => transfer(target) : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : HugeIcon(
                          icon: HugeIcons.strokeRoundedExchange01,
                          color: canSend ? Colors.white : Colors.black38,
                          size: 18,
                        ),
                  label: Text(
                    busy ? 'Transferring...' : 'Transfer ownership',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
    ref.watch(authSessionProvider);
    final workspace = ref.watch(workspaceProvider);
    final baseTheme = Theme.of(context);
    final allowed = available;
    final options = allowed
        ? ref.watch(companyOwnershipCandidatesProvider(widget.company))
        : null;

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: _accent),
      ),
      child: PopScope(
        canPop: !busy,
        child: WorkspaceScaffold(
          company: true,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            leading: const AppBackButton(),
            title: const Text(
              'Transfer ownership',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
          ),
          body: ColoredBox(
            color: _pageBackground,
            child: !allowed
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
                            'Only the current owner or a platform administrator can transfer ownership. Reopen this page if your workspace changed.',
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
                : options!.when(
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
                              'Unable to load members',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: () => ref.invalidate(
                                companyOwnershipCandidatesProvider(
                                  widget.company,
                                ),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
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
                                int.tryParse(member['id'].toString()) ==
                                selected,
                          )
                          .firstOrNull;
                      return Column(
                        children: [
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
                                  enabled: !busy,
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
                                    disabledBorder: OutlineInputBorder(
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
                                    selected = null;
                                  }),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: _cardBorder),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                              children: [
                                _warningBanner(),
                                if (visible.isEmpty)
                                  _emptyState(members.isEmpty)
                                else ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      0,
                                      4,
                                      10,
                                    ),
                                    child: Text(
                                      '${visible.length} eligible ${visible.length == 1 ? 'member' : 'members'}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                  for (final member in visible)
                                    _memberCard(member),
                                ],
                              ],
                            ),
                          ),
                          _bottomBar(target),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Confirmation sheet ─────────────────────────────────────────────

class _TransferSheet extends StatelessWidget {
  const _TransferSheet({required this.name});
  final String name;

  Widget _point(dynamic icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: HugeIcon(icon: icon, color: _accent, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD5DCE5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: _amberSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const HugeIcon(
                icon: HugeIcons.strokeRoundedExchange01,
                color: _amber,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Transfer company ownership?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _pageBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _cardBorder),
              ),
              child: Column(
                children: [
                  _point(
                    HugeIcons.strokeRoundedCrown,
                    '$name will become the company owner.',
                  ),
                  _point(
                    HugeIcons.strokeRoundedShield01,
                    'The current owner will become a company administrator.',
                  ),
                  _point(
                    HugeIcons.strokeRoundedFolder01,
                    'Saved company records will remain unchanged.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Transfer ownership',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}