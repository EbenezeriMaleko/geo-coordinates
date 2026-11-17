import '../../widget/plan_access_lock.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../widget/library_record_style.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/providers/auth_provider.dart';
import '../../workspaces/workspace_provider.dart';
import '../services/record_share_service.dart';
import '../services/record_recovery_service.dart';

class RecordSharingPage extends ConsumerStatefulWidget {
  const RecordSharingPage({
    super.key,
    required this.record,
    required this.company,
  });
  final String record;
  final int? company;

  @override
  ConsumerState<RecordSharingPage> createState() => _RecordSharingPageState();
}

class _RecordSharingPageState extends ConsumerState<RecordSharingPage> {
  final service = RecordShareService();
  final password = TextEditingController();
  late final String token;
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  bool includeClaimant = false;
  int days = 30;
  int page = 1;

  bool get current =>
      mounted &&
      ref.read(authSessionProvider).isVerified &&
      ref.read(authSessionProvider).token == token &&
      ref.read(workspaceProvider).activeCompanyId == widget.company &&
      !ref.read(workspaceProvider).isLoading;

  @override
  void initState() {
    super.initState();
    token = ref.read(authSessionProvider).token;
    Future.microtask(refresh);
  }

  @override
  void dispose() {
    password.dispose();
    service.dispose();
    super.dispose();
  }

  Future<void> refresh({
    String method = 'GET',
    int? link,
    int? targetPage,
    Map<String, dynamic>? body,
  }) async {
    if (!current || busy) return;
    final record = int.tryParse(widget.record);
    if (record == null || record < 1) {
      setState(() => error = 'A saved cloud record is required.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await service.request(
        token: token,
        record: record,
        company: widget.company,
        isCurrent: () => current,
        method: method,
        linkId: link,
        page: targetPage ?? page,
        body: body,
      );
      if (!current) return;
      setState(() {
        data = result;
        page = (result['page'] as num?)?.toInt() ?? 1;
        if (method == 'POST') {
          final links = result['links'];
          if (includeClaimant &&
              (links is! List ||
                  links.isEmpty ||
                  links.first is! Map ||
                  (links.first as Map)['include_claimant_details'] != true)) {
            error =
                'The link was created, but the server did not confirm its privacy settings. Do not share it.';
          }
          password.clear();
          includeClaimant = false;
        }
      });
    } catch (failure) {
      if (current) {
        setState(
          () => error = failure.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke link?'),
        content: const Text('Anyone with this link will lose access.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep link'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed == true && current) await refresh(method: 'DELETE', link: id);
  }

  Future<void> createLink() async {
    if (!current || busy || RecordRecoveryService().pending(widget.record)) {
      return;
    }
    if (password.text.isNotEmpty && password.text.length < 8) {
      setState(() => error = 'Password must contain at least 8 characters.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create public record link?'),
        content: Text(
          'Anyone with this link${password.text.isNotEmpty ? ' and its password' : ''} can view the saved record and its geometry until it expires or is revoked. '
          '${includeClaimant ? 'Customer name, phone, plot number and land use will also be included. ' : 'Customer details will not be included. '}'
          'The link expires in $days day${days == 1 ? '' : 's'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create link'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !current ||
        RecordRecoveryService().pending(widget.record)) {
      return;
    }
    await refresh(
      method: 'POST',
      targetPage: 1,
      body: {
        'expires_days': days,
        if (password.text.isNotEmpty) 'password': password.text,
        'include_claimant_details': includeClaimant,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionProvider);
    ref.watch(workspaceProvider);
    final policy = data?['policy'] is Map ? data!['policy'] as Map : const {};
    final links = data?['links'] is List
        ? (data!['links'] as List).whereType<Map>().toList()
        : <Map>[];
    final pending = RecordRecoveryService().pending(widget.record);
    final lastPage = (data?['last_page'] as num?)?.toInt() ?? 1;
    return LibraryRecordScaffold(
      company: widget.company != null,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedArrowLeft01,
            size: 22,
          ),
        ),
        centerTitle: true,
        title: const Text('Share record'),
        actions: [
          IconButton(
            onPressed: busy ? null : () => refresh(),
            icon: const HugeIcon(
              size: 20,
              icon: HugeIcons.strokeRoundedRefresh,
            ),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: !current
          ? const Center(
              child: Text('Workspace or account changed. Reopen sharing.'),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LibraryRecordHeader(
                    icon: HugeIcons.strokeRoundedLink01,
                    title: 'Share this record',
                    subtitle: 'Manage link expiry, passwords, and access.',
                  ),
                  if (busy && data == null)
                    const Center(child: CircularProgressIndicator()),
                  if (error != null)
                    _SharingNotice(text: error!, isError: true),
                  if (pending)
                    const _SharingNotice(
                      text:
                          'Sync or resolve pending local edits before creating or sharing a link.',
                    ),
                  if (data != null && data!['can_manage'] != true)
                    PlanAccessLock(
                      locked: true,
                      child: _SharingNotice(
                        text:
                            'Only the record owner or a company owner or administrator can manage links.',
                      ),
                    ),
                  if (data != null && data!['can_manage'] == true) ...[
                    if (policy['available'] != true)
                      PlanAccessLock(
                        locked: true,
                        child: _SharingNotice(
                          text: 'Shared links are unavailable.',
                        ),
                      ),
                    if (policy['available'] == true) ...[
                      if (policy['workspace_enabled'] == false)
                        const _SharingNotice(
                          text:
                              'Public sharing is disabled for this workspace. Contact a company administrator.',
                        ),
                      if (policy['workspace_enabled'] != false &&
                          policy['allowed'] != true)
                        const _SharingNotice(
                          text:
                              'The shared-link allowance has been reached. Revoke an existing link or request a different plan.',
                        ),
                      _SharingCard(
                        title: 'Create a sharing link',
                        icon: HugeIcons.strokeRoundedLink01,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<int>(
                              initialValue: days,
                              decoration: const InputDecoration(
                                labelText: 'Expires in',
                                prefixIcon: SizedBox(
                                  width: 48,
                                  child: Center(
                                    widthFactor: 1,
                                    heightFactor: 1,
                                    child: HugeIcon(
                                      icon: HugeIcons.strokeRoundedClock01,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 1,
                                  child: Text('1 day'),
                                ),
                                DropdownMenuItem(
                                  value: 7,
                                  child: Text('7 days'),
                                ),
                                DropdownMenuItem(
                                  value: 30,
                                  child: Text('30 days'),
                                ),
                                DropdownMenuItem(
                                  value: 90,
                                  child: Text('90 days'),
                                ),
                                DropdownMenuItem(
                                  value: 365,
                                  child: Text('1 year'),
                                ),
                              ],
                              onChanged: busy
                                  ? null
                                  : (value) =>
                                        setState(() => days = value ?? 30),
                            ),
                            const SizedBox(height: 16),
                            PlanAccessLock(
                              locked:
                                  !busy && policy['password_allowed'] != true,
                              child: TextField(
                                controller: password,
                                enabled:
                                    !busy && policy['password_allowed'] == true,
                                obscureText: true,
                                maxLength: 128,
                                decoration: InputDecoration(
                                  labelText: 'Password (optional)',
                                  helperMaxLines: 3,
                                  prefixIcon: const SizedBox(
                                    width: 48,
                                    child: Center(
                                      widthFactor: 1,
                                      heightFactor: 1,
                                      child: HugeIcon(
                                        icon: HugeIcons.strokeRoundedLockKey,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  helperText: policy['password_allowed'] == true
                                      ? 'At least 8 characters'
                                      : 'Not included in this plan',
                                ),
                              ),
                            ),
                            if (widget.company != null)
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                shape: const RoundedRectangleBorder(),
                                tileColor: Colors.transparent,
                                value: includeClaimant,
                                onChanged: busy
                                    ? null
                                    : (value) => setState(
                                        () => includeClaimant = value,
                                      ),
                                title: const Text('Include claimant details'),
                                subtitle: const Text(
                                  'Name, phone, plot number and land use may be visible. ID is never shared.',
                                ),
                              ),
                            const SizedBox(height: 16),
                            PlanAccessLock(
                              locked:
                                  !busy &&
                                  (policy['allowed'] != true ||
                                      policy['workspace_enabled'] == false),
                              child: FilledButton.icon(
                                onPressed:
                                    busy || pending || policy['allowed'] != true
                                    ? null
                                    : createLink,
                                icon: const HugeIcon(
                                  size: 20,
                                  icon: HugeIcons.strokeRoundedLink01,
                                ),
                                label: const Text('Create link'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'ACTIVE LINKS',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (links.isEmpty)
                      const _SharingNotice(text: 'No unexpired links.'),
                    for (final link in links)
                      Builder(
                        builder: (context) {
                          final id = int.tryParse(link['id']?.toString() ?? '');
                          final url = link['url']?.toString() ?? '';
                          final safe =
                              !pending &&
                              link['active'] == true &&
                              link['include_claimant_details'] is bool &&
                              RecordShareService.safeUrl(url);
                          return _SharingCard(
                            title: 'Link #${id ?? '?'}',
                            icon: HugeIcons.strokeRoundedLink01,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _LinkBadge(
                                      text: link['active'] == true
                                          ? 'Active'
                                          : 'Unavailable',
                                    ),
                                    if (link['password_protected'] == true)
                                      const _LinkBadge(
                                        text: 'Password protected',
                                      ),
                                    if (link['include_claimant_details'] ==
                                        true)
                                      const _LinkBadge(
                                        text: 'Claimant details included',
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Expires ${link['expires_at'] ?? 'unknown'}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.black54,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    TextButton.icon(
                                      label: const Text('Copy'),
                                      onPressed: !safe || busy
                                          ? null
                                          : () async {
                                              if (!current ||
                                                  RecordRecoveryService()
                                                      .pending(widget.record)) {
                                                return;
                                              }
                                              await Clipboard.setData(
                                                ClipboardData(text: url),
                                              );
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Link copied.',
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                      icon: const HugeIcon(
                                        size: 20,
                                        icon: HugeIcons.strokeRoundedCopy01,
                                      ),
                                    ),
                                    TextButton.icon(
                                      label: const Text('Share'),
                                      onPressed: !safe || busy
                                          ? null
                                          : () {
                                              if (!current ||
                                                  RecordRecoveryService()
                                                      .pending(widget.record)) {
                                                return;
                                              }
                                              final box = context
                                                  .findRenderObject();
                                              final origin =
                                                  box is RenderBox &&
                                                      box.hasSize
                                                  ? box.localToGlobal(
                                                          Offset.zero,
                                                        ) &
                                                        box.size
                                                  : const Rect.fromLTWH(
                                                      0,
                                                      0,
                                                      1,
                                                      1,
                                                    );
                                              SharePlus.instance.share(
                                                ShareParams(
                                                  text: url,
                                                  sharePositionOrigin: origin,
                                                ),
                                              );
                                            },
                                      icon: const HugeIcon(
                                        size: 20,
                                        icon: HugeIcons.strokeRoundedShare01,
                                      ),
                                    ),
                                    TextButton.icon(
                                      label: const Text('Revoke'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFFB42318,
                                        ),
                                      ),
                                      onPressed: id == null || busy
                                          ? null
                                          : () => revoke(id),
                                      icon: const HugeIcon(
                                        size: 20,
                                        icon: HugeIcons.strokeRoundedUnlink01,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    if (lastPage > 1)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Previous page',
                            onPressed: busy || page <= 1
                                ? null
                                : () => refresh(targetPage: page - 1),
                            icon: const HugeIcon(
                              size: 20,
                              icon: HugeIcons.strokeRoundedArrowLeft01,
                            ),
                          ),
                          Text('Page $page of $lastPage'),
                          IconButton(
                            tooltip: 'Next page',
                            onPressed: busy || page >= lastPage
                                ? null
                                : () => refresh(targetPage: page + 1),
                            icon: const HugeIcon(
                              size: 20,
                              icon: HugeIcons.strokeRoundedArrowRight01,
                            ),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _SharingCard extends StatelessWidget {
  const _SharingCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final dynamic icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: HugeIcon(icon: icon, size: 20, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _SharingNotice extends StatelessWidget {
  const _SharingNotice({required this.text, this.isError = false});
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? const Color(0xFFB42318)
        : Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(
            icon: isError
                ? HugeIcons.strokeRoundedAlertCircle
                : HugeIcons.strokeRoundedInformationCircle,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkBadge extends StatelessWidget {
  const _LinkBadge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4F7),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        color: Color(0xFF526579),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
