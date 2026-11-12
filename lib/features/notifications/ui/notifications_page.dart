import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/push_notification_service.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final List<_InboxItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _pushEnabled = false;
  int _unreadCount = 0;
  int _page = 1;
  int _lastPage = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final session = ref.read(authSessionProvider);
    if (!session.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = 'Sign in to view notifications.';
      });
      return;
    }
    if (more) {
      if (_loadingMore || _page >= _lastPage) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    }
    try {
      final response = await ApiClient.getJson(
        '/notifications',
        bearerToken: session.token,
        queryParameters: {'page': more ? _page + 1 : 1},
        tag: 'notifications.inbox',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Notifications could not be loaded.');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = (json['data'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => _InboxItem.fromJson(row.cast<String, dynamic>()))
          .toList();
      final meta = (json['meta'] as Map?)?.cast<String, dynamic>() ?? {};
      if (!mounted) return;
      setState(() {
        if (more) {
          _items.addAll(rows);
          _page++;
        } else {
          _items
            ..clear()
            ..addAll(rows);
          _page = 1;
        }
        _lastPage = (meta['last_page'] as num?)?.toInt() ?? 1;
        _unreadCount = (meta['unread_count'] as num?)?.toInt() ?? _unreadCount;
        _error = null;
      });
      _pushEnabled = await PushNotificationService.instance.isEnabled(session);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted && more) {
        _showMessage(
          'More notifications could not be loaded. Scroll to retry.',
        );
      } else if (mounted) {
        setState(
          () => _error =
              'Could not load notifications. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _markRead(_InboxItem item) async {
    if (item.readAt != null) return;
    final session = ref.read(authSessionProvider);
    setState(() {
      item.readAt = DateTime.now().toIso8601String();
      _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30).toInt();
    });
    try {
      final response = await ApiClient.patchJson(
        '/notifications/${item.id}/read',
        body: const {},
        bearerToken: session.token,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Request failed');
      }
    } catch (_) {
      await _load();
    }
  }

  Future<void> _markAllRead() async {
    final session = ref.read(authSessionProvider);
    try {
      final response = await ApiClient.postJsonNoBody(
        '/notifications/read-all',
        bearerToken: session.token,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Request failed');
      }
      if (mounted) {
        setState(() {
          for (final item in _items) {
            item.readAt ??= DateTime.now().toIso8601String();
          }
          _unreadCount = 0;
        });
      }
    } catch (_) {
      if (mounted) _showMessage('Notifications could not be marked as read.');
    }
  }

  Future<void> _setPushEnabled(bool value) async {
    final session = ref.read(authSessionProvider);
    try {
      if (value) {
        final enabled = await PushNotificationService.instance.enable(session);
        if (!enabled && mounted) {
          _showMessage(
            'Push permission was declined. Your inbox will still work.',
          );
        }
        if (mounted) setState(() => _pushEnabled = enabled);
      } else {
        await PushNotificationService.instance.disable(session);
        if (mounted) setState(() => _pushEnabled = false);
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error.toString().replaceFirst('PushNotificationException: ', ''),
        );
      }
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final unread = _unreadCount;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
          if (unread > 0)
            TextButton.icon(
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Read all'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile.adaptive(
            value: _pushEnabled,
            onChanged: PushNotificationService.instance.isAvailable
                ? _setPushEnabled
                : null,
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Mobile push notifications'),
            subtitle: Text(
              PushNotificationService.instance.isAvailable
                  ? 'Optional alerts on this device'
                  : 'Push delivery is not configured for this app build',
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _StatusView(
                    message: _error!,
                    action: TextButton(
                      onPressed: () => _load(),
                      child: const Text('Retry'),
                    ),
                  )
                : _items.isEmpty
                ? const _StatusView(message: 'You are all caught up.')
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.extentAfter < 240 &&
                          !_loadingMore &&
                          _page < _lastPage) {
                        _load(more: true);
                      }
                      return false;
                    },
                    child: RefreshIndicator(
                      onRefresh: () => _load(),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _items.length + (_loadingMore ? 1 : 0),
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          if (index == _items.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          final item = _items[index];
                          return ListTile(
                            onTap: () => _markRead(item),
                            leading: CircleAvatar(
                              backgroundColor: item.readAt == null
                                  ? colors.primaryContainer
                                  : colors.surfaceContainerHighest,
                              child: Icon(
                                Icons.campaign_outlined,
                                color: item.readAt == null
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: TextStyle(
                                      fontWeight: item.readAt == null
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (item.readAt == null)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: colors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.body),
                                  const SizedBox(height: 5),
                                  Text(
                                    _formatDate(item.createdAt),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) =>
      MaterialLocalizations.of(context).formatMediumDate(date);
}

class _InboxItem {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  String? readAt;

  _InboxItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readAt,
  });

  factory _InboxItem.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    return _InboxItem(
      id: json['id']?.toString() ?? '',
      title: data['title']?.toString() ?? 'TaREF GPS update',
      body: data['body']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      readAt: json['read_at']?.toString(),
    );
  }
}

class _StatusView extends StatelessWidget {
  final String message;
  final Widget? action;
  const _StatusView({required this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.notifications_none, size: 34),
        const SizedBox(height: 12),
        Text(message),
        ?action,
      ],
    ),
  );
}
