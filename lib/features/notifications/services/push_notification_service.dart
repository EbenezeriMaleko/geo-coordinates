import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../auth/models/auth_models.dart';

final GlobalKey<NavigatorState> notificationsNavigatorKey =
    GlobalKey<NavigatorState>();

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const _channelId = 'taref_announcements';
  static const _channelName = 'TaREF announcements';
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  AuthSession? _activeSession;
  bool _initialized = false;

  bool get isAvailable => _initialized;

  Future<void> initialize() async {
    if (_initialized || Firebase.apps.isEmpty) return;

    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (_) => _openInbox(),
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Important TaREF account and workspace announcements.',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (_) => _openInbox(),
    );
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) async {
      final session = _activeSession;
      if (session == null || !session.isLoggedIn || !_enabledFor(session)) {
        return;
      }
      try {
        await _registerToken(session, token);
      } catch (_) {
        // Inbox notifications remain available if device registration fails.
      }
    });
    _initialized = true;
  }

  Future<void> handleInitialMessage() async {
    if (!_initialized) return;
    final message = await FirebaseMessaging.instance.getInitialMessage();
    if (message == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInbox());
  }

  Future<bool> isEnabled(AuthSession session) async {
    if (session.user == null) return false;
    final preferences = await _preferences();
    return preferences.get(_preferenceKey(session), defaultValue: false)
        as bool;
  }

  Future<bool> enable(AuthSession session) async {
    if (!_initialized || !session.isLoggedIn || session.user == null) {
      throw const PushNotificationException(
        'Push notifications are not configured for this app yet.',
      );
    }

    final permission = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      return false;
    }

    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    String? token;
    if (Platform.isIOS) {
      for (var attempt = 0; attempt < 6 && token == null; attempt++) {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken != null) {
          token = await FirebaseMessaging.instance.getToken();
        } else {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    } else {
      token = await FirebaseMessaging.instance.getToken();
    }
    if (token == null || token.isEmpty) {
      throw const PushNotificationException(
        'This device has not finished registering for push. Please try again shortly.',
      );
    }

    await _registerToken(session, token);
    final preferences = await _preferences();
    await preferences.put(_preferenceKey(session), true);
    await preferences.put(_tokenKey(session), token);
    _activeSession = session;
    return true;
  }

  Future<void> disable(AuthSession session) async {
    final preferences = await _preferences();
    final token = preferences.get(_tokenKey(session)) as String?;
    if (token != null && token.isNotEmpty) {
      await _unregisterToken(session, token);
    }
    await preferences.put(_preferenceKey(session), false);
    await preferences.delete(_tokenKey(session));
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
  }

  Future<void> syncSession(AuthSession next) async {
    final previous = _activeSession;
    final changedUser = previous?.user?.id != next.user?.id;
    if (changedUser && previous != null && previous.isLoggedIn) {
      final preferences = await _preferences();
      final previousToken = preferences.get(_tokenKey(previous)) as String?;
      if (previousToken != null && previousToken.isNotEmpty) {
        try {
          await _unregisterToken(previous, previousToken);
        } catch (_) {
          // The previous account's token will be replaced on its next login.
        }
      }
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    }

    _activeSession = next.isLoggedIn ? next : null;
    if (!_initialized || !next.isLoggedIn || next.user == null) return;

    final enabled = await isEnabled(next);
    if (!enabled) return;
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) {
      try {
        await _registerToken(next, token);
        final preferences = await _preferences();
        await preferences.put(_tokenKey(next), token);
      } catch (_) {
        // Keep the inbox usable while push delivery is unavailable.
      }
    }
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _localNotifications.show(
      id: message.messageId.hashCode,
      title: notification.title,
      body: notification.body,
      payload: message.data['notification_id']?.toString(),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription:
              'Important TaREF account and workspace announcements.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  Future<void> _registerToken(AuthSession session, String token) async {
    final platform = Platform.isIOS ? 'ios' : 'android';
    final response = await http
        .post(
          ApiClient.uri('/notifications/device-token'),
          headers: ApiClient.jsonHeaders(bearerToken: session.token),
          body: jsonEncode({'token': token, 'platform': platform}),
        )
        .timeout(ApiClient.timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const PushNotificationException(
        'This device could not be registered for notifications.',
      );
    }
  }

  Future<void> _unregisterToken(AuthSession session, String token) async {
    final response = await http
        .delete(
          ApiClient.uri('/notifications/device-token'),
          headers: ApiClient.jsonHeaders(bearerToken: session.token),
          body: jsonEncode({'token': token}),
        )
        .timeout(ApiClient.timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const PushNotificationException(
        'This device could not be removed from push notifications.',
      );
    }
  }

  Future<Box> _preferences() async {
    if (Hive.isBoxOpen('notification_preferences')) {
      return Hive.box('notification_preferences');
    }
    return Hive.openBox('notification_preferences');
  }

  String _preferenceKey(AuthSession session) =>
      'push_enabled_${session.user!.id}';
  String _tokenKey(AuthSession session) => 'push_token_${session.user!.id}';

  bool _enabledFor(AuthSession session) =>
      Hive.isBoxOpen('notification_preferences') &&
      (Hive.box('notification_preferences').get(_preferenceKey(session))
              as bool? ??
          false);

  void _openInbox() {
    notificationsNavigatorKey.currentState?.pushNamed('/notifications');
  }
}

class PushNotificationException implements Exception {
  final String message;
  const PushNotificationException(this.message);

  @override
  String toString() => message;
}
