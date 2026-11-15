import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/network/api_client.dart';
import '../providers/auth_provider.dart';
import '../../workspaces/workspace_page_style.dart';

class DeviceSessionService {
  Future<Map<String, dynamic>> list(String token, int page) async {
    final response = await ApiClient.getJson(
      '/auth/devices',
      bearerToken: token,
      queryParameters: {'page': page},
    );
    if (response.statusCode != 200) {
      throw Exception('Unable to load device sessions.');
    }
    final body = jsonDecode(response.body);
    if (body is! Map ||
        body['data'] is! Map ||
        body['data']['sessions'] is! List) {
      throw Exception('Unexpected device session response.');
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<void> revoke(String token, int id) async {
    final response = await ApiClient.deleteJson(
      '/auth/devices/$id',
      bearerToken: token,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body);
      throw Exception(
        body is Map
            ? body['message'] ?? 'Unable to sign out this device.'
            : 'Unable to sign out this device.',
      );
    }
  }
}

final deviceSessionServiceProvider = Provider<DeviceSessionService>(
  (ref) => DeviceSessionService(),
);
final deviceSessionsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, int>((ref, page) async {
      final session = ref.watch(authSessionProvider);
      if (!session.isLoggedIn) {
        throw Exception('Sign in to manage device sessions.');
      }
      return ref.read(deviceSessionServiceProvider).list(session.token, page);
    });

class DeviceSessionsPage extends ConsumerStatefulWidget {
  const DeviceSessionsPage({super.key});
  @override
  ConsumerState<DeviceSessionsPage> createState() => _DeviceSessionsPageState();
}

class _DeviceSessionsPageState extends ConsumerState<DeviceSessionsPage> {
  static const Color _pageBackground = Color(0xFFF7F7F8);
  static const Color _cardBorder = Color(0xFFE8ECF0);

  int page = 1;
  int? busy;
  bool confirming = false;
  String? error;
  late final token = ref.read(authSessionProvider).token;

  Future<void> revoke(Map session) async {
    if (busy != null || confirming || session['current'] != false) return;
    final id = int.tryParse(session['id'].toString());
    if (id == null || token != ref.read(authSessionProvider).token) return;
    bool? confirmed;
    confirming = true;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign out this device?'),
          content: Text(
            '${session['name'] ?? 'This device'} will lose cloud access until it signs in again. Local records will not be deleted.',
          ),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Sign out device'),
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
    if (!mounted ||
        confirmed != true ||
        token != ref.read(authSessionProvider).token) {
      return;
    }
    setState(() {
      busy = id;
      error = null;
    });
    try {
      await ref.read(deviceSessionServiceProvider).revoke(token, id);
      if (!mounted || token != ref.read(authSessionProvider).token) return;
      ref.invalidate(deviceSessionsProvider);
      setState(() => page = 1);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Device signed out.')));
    } catch (failure) {
      if (mounted && token == ref.read(authSessionProvider).token) {
        setState(
          () => error = failure.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  String date(BuildContext context, dynamic raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    return value == null
        ? 'Unavailable'
        : MaterialLocalizations.of(context).formatMediumDate(value);
  }

  // ── UI helpers ────────────────────────────────────────────────

  /// Small banner for allowance / server notices / errors.
  Widget _notice({
    required dynamic icon,
    required String text,
    bool isError = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.primary;
    return Container(
      width: double.infinity,
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

  Widget _infoRow(dynamic icon, String label, String value) {
    return Row(
      children: [
        HugeIcon(icon: icon, color: Colors.black38, size: 16),
        const SizedBox(width: 8),
        Text(
          '$label  ',
          style: const TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _deviceCard(Map item) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final isCurrent = item['current'] == true;
    final isBusy = busy?.toString() == item['id'].toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? accent.withValues(alpha: 0.35) : _cardBorder,
          width: isCurrent ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? accent.withValues(alpha: 0.10)
                      : const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedSmartPhone01,
                  color: isCurrent ? accent : Colors.black54,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item['name']?.toString() ?? 'Existing session',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? accent.withValues(alpha: 0.10)
                      : const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isCurrent ? 'Current device' : 'Other session',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isCurrent ? accent : Colors.black54,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _infoRow(
            HugeIcons.strokeRoundedCalendar03,
            'Signed in',
            date(context, item['created_at']),
          ),
          const SizedBox(height: 8),
          _infoRow(
            HugeIcons.strokeRoundedClock01,
            'Last used',
            date(context, item['last_used_at']),
          ),
          if (item['current'] == false) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy == null ? () => revoke(item) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: isBusy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.error,
                        ),
                      )
                    : HugeIcon(
                        icon: HugeIcons.strokeRoundedLogout01,
                        color: scheme.error,
                        size: 18,
                      ),
                label: Text(
                  isBusy ? 'Signing out...' : 'Sign out device',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pagination(int last) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous devices page',
            onPressed: busy == null && page > 1
                ? () => setState(() => page--)
                : null,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              color: Colors.black87,
              size: 22,
            ),
          ),
          Flexible(
            child: Text(
              'Page $page of $last',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next devices page',
            onPressed: busy == null && page < last
                ? () => setState(() => page++)
                : null,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              color: Colors.black87,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final available = session.isLoggedIn && session.token == token;
    final devices = available ? ref.watch(deviceSessionsProvider(page)) : null;
    Future<void> refresh() async {
      ref.invalidate(deviceSessionsProvider(page));
      try {
        await ref.read(deviceSessionsProvider(page).future);
      } catch (_) {}
    }

    return PopScope(
      canPop: busy == null,
      child: WorkspaceScaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: busy == null ? () => Navigator.of(context).maybePop() : null,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              color: Colors.black87,
              size: 29,
            ),
          ),
          title: const Text(
            'Signed-in devices',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Refresh devices',
              onPressed: available && busy == null ? refresh : null,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedRefresh,
                color: Colors.black87,
                size: 22,
              ),
            ),
          ],
        ),
        body: ColoredBox(
          color: _pageBackground,
          child: !available
              ? const Center(
                  child: Text('Account changed. Reopen signed-in devices.'),
                )
              : devices!.when(
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
                            color: Colors.black38,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Unable to load devices',
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
                  data: (data) {
                    final items = (data['sessions'] as List? ?? [])
                        .whereType<Map>()
                        .toList();
                    final last = (data['last_page'] as num?)?.toInt() ?? 1;
                    final limit = data['login_limit'];
                    final allowanceText = data['enforced'] != true
                        ? 'Device limits are not enforced on this server.'
                        : limit == -1
                        ? 'Device allowance: unlimited'
                        : limit == null
                        ? 'No device allowance configured.'
                        : 'Device allowance: $limit';

                    return SafeArea(
                      child: Column(
                        children: [
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: refresh,
                              child: ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  8,
                                ),
                                children: [
                                  _notice(
                                    icon: HugeIcons.strokeRoundedShield01,
                                    text: allowanceText,
                                  ),
                                  if (data['available'] != true) ...[
                                    const SizedBox(height: 10),
                                    _notice(
                                      icon: HugeIcons
                                          .strokeRoundedInformationCircle,
                                      text:
                                          'Some device details are unavailable on this server.',
                                    ),
                                  ],
                                  if (error != null) ...[
                                    const SizedBox(height: 10),
                                    _notice(
                                      icon: HugeIcons.strokeRoundedAlert02,
                                      text: error!,
                                      isError: true,
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  if (items.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 40,
                                      ),
                                      child: Column(
                                        children: [
                                          HugeIcon(
                                            icon: HugeIcons
                                                .strokeRoundedSmartPhone01,
                                            color: Colors.black26,
                                            size: 40,
                                          ),
                                          SizedBox(height: 10),
                                          Text(
                                            'No active sessions found.',
                                            style: TextStyle(
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  for (final item in items) _deviceCard(item),
                                ],
                              ),
                            ),
                          ),
                          if (last > 1) _pagination(last),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}