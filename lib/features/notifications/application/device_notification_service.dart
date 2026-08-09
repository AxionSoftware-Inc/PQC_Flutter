import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../chat/data/chat_realtime_service.dart';

/// Bridges authenticated realtime/task events to native device notifications.
///
/// The notification text deliberately contains no message plaintext: encrypted
/// chat content must never be copied into the OS notification tray.
class DeviceNotificationService {
  DeviceNotificationService({required this.apiClient});

  static const _channelId = 'antiq_messages';
  static const _channelName = 'AntiQ xabarlar';
  static const _taskSeenPrefix = 'antiq.task_notifications.seen.';

  final ApiClient apiClient;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<ChatRealtimeEvent>? _realtimeSubscription;
  Timer? _taskTimer;
  Timer? _conversationTimer;
  SharedPreferences? _preferences;
  int? _currentUserId;
  String? _scopeKey;
  bool _initialized = false;
  final Set<String> _shownKeys = <String>{};
  final Set<String> _seenTaskKeys = <String>{};
  final Map<int, String> _seenConversationStates = <int, String>{};
  Future<void>? _conversationPollInFlight;

  Future<void> initialize() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Chat va topshiriq bildirishnomalari',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);
    _preferences = await SharedPreferences.getInstance();
    _initialized = true;
  }

  Future<void> start({
    required int currentUserId,
    required int accountId,
    required int workspaceId,
    required Stream<ChatRealtimeEvent> realtimeEvents,
  }) async {
    await initialize();
    await stop();
    if (workspaceId <= 0) return;
    _currentUserId = currentUserId;
    _scopeKey = '$_taskSeenPrefix$accountId.$workspaceId';
    _loadSeenTaskKeys();
    _seenConversationStates.clear();
    _realtimeSubscription = realtimeEvents.listen(_handleRealtimeEvent);
    // This catches task notifications created while the app was suspended or
    // the websocket was reconnecting. The realtime path remains immediate.
    await _pollTaskNotifications(seedExisting: true);
    await _pollConversations(seedExisting: true);
    _taskTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_pollTaskNotifications());
    });
    _conversationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_pollConversations());
    });
  }

  Future<void> stop() async {
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _taskTimer?.cancel();
    _taskTimer = null;
    _conversationTimer?.cancel();
    _conversationTimer = null;
    _conversationPollInFlight = null;
    _currentUserId = null;
    _scopeKey = null;
    _shownKeys.clear();
    _seenTaskKeys.clear();
    _seenConversationStates.clear();
  }

  Future<void> dispose() async {
    await stop();
  }

  void _loadSeenTaskKeys() {
    final key = _scopeKey;
    if (key == null) return;
    _seenTaskKeys
      ..clear()
      ..addAll(_preferences?.getStringList(key) ?? const []);
  }

  Future<void> _persistSeenTaskKeys() async {
    final key = _scopeKey;
    if (key == null || _preferences == null) return;
    final values = _seenTaskKeys.toList();
    if (values.length > 500) {
      values.removeRange(0, values.length - 500);
      _seenTaskKeys
        ..clear()
        ..addAll(values);
    }
    await _preferences!.setStringList(key, values);
  }

  void _handleRealtimeEvent(ChatRealtimeEvent event) {
    final payload = event.payload;
    if (event.event == 'message.created') {
      final senderId = _asInt(payload['sender_id']);
      if (senderId == null || senderId == _currentUserId) return;
      final messageId = _asInt(payload['id']);
      final key = 'message:${messageId ?? payload['client_message_id']}';
      unawaited(
        _showOnce(
          key: key,
          title: '${payload['sender_name'] ?? 'Foydalanuvchi'}dan xabar keldi',
          body: 'Yangi shifrlangan xabar',
        ),
      );
      return;
    }
    if (event.event != 'task.notification.created') return;
    final recipientId = _asInt(payload['recipient_user_id']);
    if (recipientId != null && recipientId != _currentUserId) return;
    final notificationId = _asInt(payload['notification_id']);
    final key = 'task:${notificationId ?? payload['activity_id']}';
    if (_seenTaskKeys.contains(key)) return;
    unawaited(
      _showOnce(
        key: key,
        title: '${payload['sender_name'] ?? 'Rahbar'}dan vazifa keldi',
        body: payload['task_title']?.toString() ?? 'Yangi topshiriq',
      ),
    );
  }

  Future<void> _pollTaskNotifications({bool seedExisting = false}) async {
    try {
      final response = await apiClient.get('/task-kpi/notifications');
      if (response is! Map || response['items'] is! List) return;
      final items = (response['items'] as List).whereType<Map>();
      for (final raw in items) {
        final notification = Map<String, dynamic>.from(raw);
        final id = _asInt(notification['id']);
        if (id == null) continue;
        final key = 'task:$id';
        if (_seenTaskKeys.contains(key)) continue;
        _seenTaskKeys.add(key);
        _shownKeys.add(key);
        if (seedExisting) continue;
        final activity = notification['activity'] is Map
            ? Map<String, dynamic>.from(notification['activity'] as Map)
            : const <String, dynamic>{};
        await _show(
          key: key,
          title: '${activity['author_name'] ?? 'Rahbar'}dan vazifa keldi',
          body: notification['task_title']?.toString() ?? 'Yangi topshiriq',
        );
      }
      await _persistSeenTaskKeys();
    } catch (_) {
      // Notifications are auxiliary; a missing optional task plugin or a
      // temporary network failure must never affect the chat session.
    }
  }

  Future<void> _pollConversations({bool seedExisting = false}) {
    final inFlight = _conversationPollInFlight;
    if (inFlight != null) return inFlight;
    late final Future<void> operation;
    operation = _pollConversationsOnce(seedExisting: seedExisting);
    _conversationPollInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_conversationPollInFlight, operation)) {
        _conversationPollInFlight = null;
      }
    });
  }

  Future<void> _pollConversationsOnce({required bool seedExisting}) async {
    try {
      final response = await apiClient.get(
        '/conversations',
        queryParameters: const {'offset': '0', 'limit': '50'},
      );
      if (response is! List) return;
      for (final item in response.whereType<Map>()) {
        final conversation = Map<String, dynamic>.from(item);
        final conversationId = _asInt(conversation['id']);
        final latestMessageId = _asInt(conversation['latest_message_id']);
        if (conversationId == null || latestMessageId == null) continue;
        final senderId = _asInt(conversation['latest_sender_id']);
        final unreadCount = _asInt(conversation['unread_count']) ?? 0;
        final state = '$latestMessageId:$unreadCount';
        final previous = _seenConversationStates[conversationId];
        _seenConversationStates[conversationId] = state;
        if (seedExisting || previous == null || previous == state) continue;
        if (senderId == null || senderId == _currentUserId) continue;
        final senderName =
            conversation['latest_sender_name']?.toString() ?? 'Foydalanuvchi';
        await _showOnce(
          key: 'message:$latestMessageId',
          title: '$senderName dan xabar keldi',
          body: 'Yangi shifrlangan xabar',
        );
      }
    } catch (_) {
      // Realtime remains the fast path; polling is only a best-effort recovery
      // path and must never block the authenticated app.
    }
  }

  Future<void> _showOnce({
    required String key,
    required String title,
    required String body,
  }) async {
    if (_shownKeys.contains(key)) return;
    _shownKeys.add(key);
    await _show(key: key, title: title, body: body);
    if (key.startsWith('task:')) {
      _seenTaskKeys.add(key);
      await _persistSeenTaskKeys();
    }
  }

  Future<void> _show({
    required String key,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id: _notificationId(key),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Chat va topshiriq bildirishnomalari',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  int _notificationId(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  int? _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }
}
