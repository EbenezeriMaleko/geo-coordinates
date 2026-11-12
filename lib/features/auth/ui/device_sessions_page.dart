import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          title: const Text('Signed-in devices'),
          actions: [
            IconButton(
              tooltip: 'Refresh devices',
              onPressed: available && busy == null ? refresh : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !available
            ? const Center(
                child: Text('Account changed. Reopen signed-in devices.'),
              )
            : devices!.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: TextButton.icon(
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Unable to load devices. Retry'),
                  ),
                ),
                data: (data) {
                  final items = (data['sessions'] as List? ?? [])
                      .whereType<Map>();
                  final last = (data['last_page'] as num?)?.toInt() ?? 1;
                  final limit = data['login_limit'];
                  return SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              data['enforced'] != true
                                  ? 'Device limits are not enforced on this server.'
                                  : limit == -1
                                  ? 'Device allowance: unlimited'
                                  : limit == null
                                  ? 'No device allowance configured.'
                                  : 'Device allowance: $limit',
                            ),
                          ),
                        ),
                        if (data['available'] != true)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              'Some device details are unavailable on this server.',
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
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: refresh,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              children: [
                                if (items.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text('No active sessions found.'),
                                  ),
                                for (final item in items) ...[
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.devices_outlined),
                                    title: Text(
                                      item['name']?.toString() ??
                                          'Existing session',
                                    ),
                                    subtitle: Text(
                                      item['current'] == true
                                          ? 'Current device'
                                          : 'Other session',
                                    ),
                                  ),
                                  Text(
                                    'Signed in: ${date(context, item['created_at'])}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  Text(
                                    'Last used: ${date(context, item['last_used_at'])}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  if (item['current'] == false)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: busy == null
                                            ? () => revoke(item)
                                            : null,
                                        icon: const Icon(
                                          Icons.logout,
                                          size: 18,
                                        ),
                                        label: Text(
                                          busy == item['id']
                                              ? 'Signing out...'
                                              : 'Sign out device',
                                        ),
                                      ),
                                    ),
                                  const Divider(height: 24),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Previous devices page',
                              onPressed: busy == null && page > 1
                                  ? () => setState(() => page--)
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Flexible(child: Text('Page $page of $last')),
                            IconButton(
                              tooltip: 'Next devices page',
                              onPressed: busy == null && page < last
                                  ? () => setState(() => page++)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
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
