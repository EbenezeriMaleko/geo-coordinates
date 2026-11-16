import 'package:flutter/material.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share record'),
        actions: [
          IconButton(
            onPressed: busy ? null : () => refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: !current
          ? const Center(
              child: Text('Workspace or account changed. Reopen sharing.'),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (busy && data == null)
                  const Center(child: CircularProgressIndicator()),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (pending)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Sync or resolve pending local edits before creating or sharing a link.',
                    ),
                  ),
                if (data != null && data!['can_manage'] != true)
                  const Text(
                    'Only the record owner or a company owner or administrator can manage links.',
                  ),
                if (data != null && data!['can_manage'] == true) ...[
                  if (policy['available'] != true)
                    const Text('Shared links are unavailable.'),
                  if (policy['available'] == true) ...[
                    if (policy['workspace_enabled'] == false)
                      const Text(
                        'Public sharing is disabled for this workspace. Contact a company administrator.',
                      ),
                    if (policy['workspace_enabled'] != false &&
                        policy['allowed'] != true)
                      const Text(
                        'The shared-link allowance has been reached. Revoke an existing link or request a different plan.',
                      ),
                    DropdownButtonFormField<int>(
                      initialValue: days,
                      decoration: const InputDecoration(
                        labelText: 'Expires in',
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1 day')),
                        DropdownMenuItem(value: 7, child: Text('7 days')),
                        DropdownMenuItem(value: 30, child: Text('30 days')),
                        DropdownMenuItem(value: 90, child: Text('90 days')),
                        DropdownMenuItem(value: 365, child: Text('1 year')),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() => days = value ?? 30),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      enabled: !busy && policy['password_allowed'] == true,
                      obscureText: true,
                      maxLength: 128,
                      decoration: InputDecoration(
                        labelText: 'Password (optional)',
                        helperText: policy['password_allowed'] == true
                            ? 'At least 8 characters'
                            : 'Not included in this plan',
                      ),
                    ),
                    if (widget.company != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: includeClaimant,
                        onChanged: busy
                            ? null
                            : (value) =>
                                  setState(() => includeClaimant = value),
                        title: const Text('Include claimant details'),
                        subtitle: const Text(
                          'Name, phone, plot number and land use may be visible. ID is never shared.',
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: busy || pending || policy['allowed'] != true
                          ? null
                          : createLink,
                      icon: const Icon(Icons.add_link),
                      label: const Text('Create link'),
                    ),
                  ],
                  const Divider(height: 32),
                  Text(
                    'Active links',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (links.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No unexpired links.'),
                    ),
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
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Link #${id ?? '?'}'),
                          subtitle: Text(
                            '${link['active'] == true ? 'Active' : 'Unavailable'} · ${link['password_protected'] == true ? 'Password protected · ' : ''}${link['include_claimant_details'] == true ? 'Claimant details included · ' : ''}Expires ${link['expires_at'] ?? 'unknown'}',
                          ),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Copy link',
                                onPressed: !safe || busy
                                    ? null
                                    : () async {
                                        if (!current ||
                                            RecordRecoveryService().pending(
                                              widget.record,
                                            )) {
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
                                              content: Text('Link copied.'),
                                            ),
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.copy),
                              ),
                              IconButton(
                                tooltip: 'Share link',
                                onPressed: !safe || busy
                                    ? null
                                    : () {
                                        if (!current ||
                                            RecordRecoveryService().pending(
                                              widget.record,
                                            )) {
                                          return;
                                        }
                                        final box = context.findRenderObject();
                                        final origin =
                                            box is RenderBox && box.hasSize
                                            ? box.localToGlobal(Offset.zero) &
                                                  box.size
                                            : const Rect.fromLTWH(0, 0, 1, 1);
                                        SharePlus.instance.share(
                                          ShareParams(
                                            text: url,
                                            sharePositionOrigin: origin,
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.share_outlined),
                              ),
                              IconButton(
                                tooltip: 'Revoke link',
                                onPressed: id == null || busy
                                    ? null
                                    : () => revoke(id),
                                icon: const Icon(Icons.link_off),
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
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('Page $page of $lastPage'),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: busy || page >= lastPage
                              ? null
                              : () => refresh(targetPage: page + 1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                ],
              ],
            ),
    );
  }
}
