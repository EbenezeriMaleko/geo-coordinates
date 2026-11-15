import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../../widget/app_backarrow.dart'; // adjust to your file name/path
import '../services/push_notification_service.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  static const Color _pageBackground = Color(0xFFF7F7F8);
  static const Color _cardBorder = Color(0xFFE8ECF0);

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

  // ── Logic (unchanged) ─────────────────────────────────────────

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

  // ── UI helpers ────────────────────────────────────────────────

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  Widget _pushCard() {
    final accent = Theme.of(context).colorScheme.primary;
    final available = PushNotificationService.instance.isAvailable;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedNotification01,
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mobile push notifications',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  available
                      ? 'Optional alerts on this device'
                      : 'Push delivery is not configured for this app build',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _pushEnabled,
            onChanged: available ? _setPushEnabled : null,
            activeColor: accent,
          ),
        ],
      ),
    );
  }

  Widget _notificationCard(_InboxItem item) {
    final accent = Theme.of(context).colorScheme.primary;
    final unread = item.readAt == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unread ? accent.withValues(alpha: 0.35) : _cardBorder,
          width: unread ? 1.3 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _markRead(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: unread
                        ? accent.withValues(alpha: 0.10)
                        : const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedMegaphone01,
                    color: unread ? accent : Colors.black45,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight:
                                    unread ? FontWeight.w700 : FontWeight.w500,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.body,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const HugeIcon(
                            icon: HugeIcons.strokeRoundedClock01,
                            color: Colors.black38,
                            size: 13,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _timeAgo(item.createdAt),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return _StatusView(
        icon: HugeIcons.strokeRoundedWifiOff01,
        message: _error!,
        action: FilledButton.tonal(
          onPressed: () => _load(),
          child: const Text('Retry'),
        ),
      );
    }

    if (_items.isEmpty) {
      return const _StatusView(
        icon: HugeIcons.strokeRoundedNotification01,
        message: 'You are all caught up.',
      );
    }

    return NotificationListener<ScrollNotification>(
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
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: _items.length + (_loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return _notificationCard(_items[index]);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = _unreadCount;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: const AppBackButton(),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (unread > 0)
            IconButton(
              tooltip: 'Mark all as read',
              onPressed: _markAllRead,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                color: Colors.black87,
                size: 22,
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedRefresh,
              color: Colors.black87,
              size: 22,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _pushCard(),
          Expanded(child: _content()),
        ],
      ),
    );
  }
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
  final dynamic icon;
  final String message;
  final Widget? action;
  const _StatusView({required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: icon, color: Colors.black26, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}