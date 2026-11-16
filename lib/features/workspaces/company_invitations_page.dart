import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import '../widget/app_backarrow.dart'; // adjust to your file name/path
import 'workspace_page_style.dart';
import 'workspace_provider.dart';

const Color _personalAccent = Color(0xFF001F3F);
const Color _companyAccent = Color(0xFF245B83);
const Color _pageBackground = Color(0xFFF7F7F8);
const Color _cardBorder = Color(0xFFE8ECF0);
const Color _amber = Color(0xFFB26A00);

class CompanyInvitationService {
  Future<List<Map<String, dynamic>>> pending(String token) async {
    final response = await ApiClient.getJson(
      '/company-invitations',
      bearerToken: token,
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load invitations.');
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['data'] is! List) {
      throw Exception('Unexpected invitation response.');
    }
    return (body['data'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> respond(String token, int id, bool accept) async {
    final response = await ApiClient.postJson(
      '/company-invitations/$id/respond',
      bearerToken: token,
      body: {'response': accept ? 'accepted' : 'declined'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body);
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to respond to invitation.'
            : 'Unable to respond to invitation.',
      );
    }
  }
}

final companyInvitationServiceProvider = Provider<CompanyInvitationService>(
  (ref) => CompanyInvitationService(),
);
final companyInvitationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final session = ref.watch(authSessionProvider);
      if (!session.isLoggedIn || !session.isVerified) {
        throw Exception('Sign in and verify your email to view invitations.');
      }
      return ref.read(companyInvitationServiceProvider).pending(session.token);
    });

class CompanyInvitationsPage extends ConsumerStatefulWidget {
  const CompanyInvitationsPage({super.key});
  @override
  ConsumerState<CompanyInvitationsPage> createState() =>
      _CompanyInvitationsPageState();
}

class _CompanyInvitationsPageState
    extends ConsumerState<CompanyInvitationsPage> {
  int? busy;
  bool confirming = false;
  String? error;

  Future<void> respond(Map<String, dynamic> invitation, bool accept) async {
    if (busy != null || confirming) return;
    final id = int.tryParse(invitation['id'].toString());
    if (id == null) return;
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn || !session.isVerified) return;
    final company = invitation['company'] is Map
        ? invitation['company']['name']?.toString() ?? 'this company'
        : 'this company';
    final isCompany = ref.read(workspaceProvider).activeCompanyId != null;
    bool? confirmed;
    confirming = true;
    try {
      confirmed = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _RespondSheet(
          accept: accept,
          accent: isCompany ? _companyAccent : _personalAccent,
          company: company,
          roleLabel: companyRoleLabel(invitation['role']?.toString()),
        ),
      );
    } finally {
      confirming = false;
    }
    if (!mounted ||
        confirmed != true ||
        session.token != ref.read(authSessionProvider).token ||
        !ref.read(authSessionProvider).isVerified) {
      return;
    }
    setState(() {
      busy = id;
      error = null;
    });
    try {
      await ref
          .read(companyInvitationServiceProvider)
          .respond(session.token, id, accept);
      if (!mounted || session.token != ref.read(authSessionProvider).token) {
        return;
      }
      ref.invalidate(companyInvitationsProvider);
      if (accept) await ref.read(workspaceProvider.notifier).refresh();
      if (!mounted || session.token != ref.read(authSessionProvider).token) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Invitation accepted. Use the workspace selector to view your available companies.'
                : 'Invitation declined.',
          ),
        ),
      );
    } catch (failure) {
      if (mounted && session.token == ref.read(authSessionProvider).token) {
        setState(
          () => error = failure.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  // ── UI helpers ────────────────────────────────────────────────

  Widget _notice({
    required dynamic icon,
    required String text,
    bool isError = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.primary;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(icon: icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: isError ? scheme.error : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts[0][0].toUpperCase();
  }

  Widget _infoRow(dynamic icon, String text, {Color? color}) {
    final c = color ?? Colors.black54;
    return Row(
      children: [
        HugeIcon(icon: icon, color: c, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: c),
          ),
        ),
      ],
    );
  }

  Widget _invitationCard(Map<String, dynamic> item) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final isBusy = busy?.toString() == item['id'].toString();
    final anyBusy = busy != null;

    final company = item['company'] is Map
        ? item['company']['name']?.toString() ?? 'Company'
        : 'Company';
    final role = companyRoleLabel(item['role']?.toString());
    final inviter = item['inviter'] is Map
        ? item['inviter']['name']?.toString() ?? 'a company manager'
        : null;
    final expires = DateTime.tryParse(
      item['expires_at']?.toString() ?? '',
    )?.toLocal();

    String? expiryText;
    Color? expiryColor;
    if (expires != null) {
      final days = expires.difference(DateTime.now()).inDays;
      final date = MaterialLocalizations.of(context).formatMediumDate(expires);
      if (expires.isBefore(DateTime.now())) {
        expiryText = 'Expired on $date';
        expiryColor = scheme.error;
      } else if (days <= 3) {
        expiryText = 'Expires soon · $date';
        expiryColor = _amber;
      } else {
        expiryText = 'Expires $date';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(company),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        role,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (inviter != null || expiryText != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFEEF1F4)),
            const SizedBox(height: 12),
          ],
          if (inviter != null)
            _infoRow(HugeIcons.strokeRoundedUser, 'Invited by $inviter'),
          if (inviter != null && expiryText != null) const SizedBox(height: 8),
          if (expiryText != null)
            _infoRow(
              HugeIcons.strokeRoundedCalendar03,
              expiryText,
              color: expiryColor,
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: anyBusy ? null : () => respond(item, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(
                      color: scheme.error.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Decline',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: anyBusy ? null : () => respond(item, true),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : HugeIcon(
                          icon: HugeIcons.strokeRoundedTick02,
                          color: anyBusy ? Colors.black38 : Colors.white,
                          size: 18,
                        ),
                  label: Text(
                    isBusy ? 'Saving...' : 'Accept invitation',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invitations = ref.watch(companyInvitationsProvider);
    final isCompany = ref.watch(workspaceProvider).activeCompanyId != null;
    final accent = isCompany ? _companyAccent : _personalAccent;
    final baseTheme = Theme.of(context);

    Future<void> refresh() async {
      ref.invalidate(companyInvitationsProvider);
      try {
        await ref.read(companyInvitationsProvider.future);
      } catch (_) {}
    }

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(primary: accent),
      ),
      child: PopScope(
        canPop: busy == null,
        child: WorkspaceScaffold(
          company: isCompany,
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            leading: const AppBackButton(),
            title: const Text(
              'Company invitations',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'Refresh invitations',
                onPressed: busy == null ? refresh : null,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedRefresh,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ColoredBox(
            color: _pageBackground,
            child: invitations.when(
              loading: () => const Center(child: CircularProgressIndicator()),
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
                        'Unable to load invitations',
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
              data: (items) => RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    if (error != null)
                      _notice(
                        icon: HugeIcons.strokeRoundedAlert02,
                        text: error!,
                        isError: true,
                      ),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 64),
                        child: Column(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: HugeIcon(
                                icon: HugeIcons.strokeRoundedMail01,
                                color: accent,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No pending invitations',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'When a company invites you, it will appear here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      _notice(
                        icon: HugeIcons.strokeRoundedInformationCircle,
                        text:
                            'Accepting an invitation will not change your active workspace.',
                      ),
                      for (final item in items) _invitationCard(item),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Confirmation sheet ─────────────────────────────────────────────

class _RespondSheet extends StatelessWidget {
  const _RespondSheet({
    required this.accept,
    required this.accent,
    required this.company,
    required this.roleLabel,
  });

  final bool accept;
  final Color accent;
  final String company;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final color = accept ? accent : error;

    return SafeArea(
      top: false,
      child: Padding(
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
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: HugeIcon(
                icon: accept
                    ? HugeIcons.strokeRoundedTick02
                    : HugeIcons.strokeRoundedCancel01,
                color: color,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              accept ? 'Join $company?' : 'Decline invitation?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              accept
                  ? 'You will join as $roleLabel. Your active workspace will stay unchanged.'
                  : 'You will not join $company. A manager can invite you again later.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  accept ? 'Accept invitation' : 'Decline invitation',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
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