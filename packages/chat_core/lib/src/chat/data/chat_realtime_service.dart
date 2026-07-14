import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import '../../core/network/api_client.dart';

class ChatRealtimeEvent {
  const ChatRealtimeEvent({required this.event, required this.payload});

  final String event;
  final Map<String, dynamic> payload;

  factory ChatRealtimeEvent.fromJson(Map<String, dynamic> json) {
    return ChatRealtimeEvent(
      event: json['event'] as String? ?? '',
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

class ChatRealtimeService {
  ChatRealtimeService({required this.apiClient});

  final ApiClient apiClient;
  final StreamController<ChatRealtimeEvent> _events =
      StreamController.broadcast();
  IOWebSocketChannel? _channel;
  Timer? _reconnectTimer;
  String _token = '';
  String _workspaceId = '';
  String _deviceId = '';
  bool _manualDisconnect = false;
  int _reconnectAttempt = 0;
  final Set<String> _seenEventKeys = <String>{};

  Stream<ChatRealtimeEvent> get events => _events.stream;
  bool get isConnected => _channel != null;

  Future<void> connect({
    required String token,
    required String workspaceId,
    required String deviceId,
  }) async {
    _token = token;
    _workspaceId = workspaceId;
    _deviceId = deviceId;
    _manualDisconnect = false;
    await disconnect(manual: false);
    final url = apiClient.websocketUrl('/ws/chat');
    final channel = IOWebSocketChannel.connect(
      Uri.parse(url),
      headers: {
        HttpHeaders.authorizationHeader: 'Token $token',
        'X-Workspace-Id': workspaceId,
        'X-Device-Id': deviceId,
      },
    );
    _channel = channel;
    channel.stream.listen(
      (event) {
        final decoded = jsonDecode(event as String) as Map<String, dynamic>;
        final eventKey = _eventKey(decoded);
        if (eventKey != null && !_seenEventKeys.add(eventKey)) {
          return;
        }
        if (_seenEventKeys.length > 2048) {
          _seenEventKeys.remove(_seenEventKeys.first);
        }
        _events.add(ChatRealtimeEvent.fromJson(decoded));
      },
      onDone: _scheduleReconnect,
      onError: (_) => _scheduleReconnect(),
    );
  }

  Future<void> disconnect({bool manual = true}) async {
    if (manual) {
      _manualDisconnect = true;
    }
    _reconnectTimer?.cancel();
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }

  Future<void> dispose() async {
    _manualDisconnect = true;
    await disconnect();
    await _events.close();
  }

  void sendEvent(String event, Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    channel.sink.add(jsonEncode({'event': event, 'payload': payload}));
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _token.isEmpty || _workspaceId.isEmpty) {
      return;
    }
    _channel = null;
    _reconnectTimer?.cancel();
    final seconds = _reconnectAttempt < 1
        ? 1
        : (_reconnectAttempt * 2).clamp(2, 30);
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      connect(token: _token, workspaceId: _workspaceId, deviceId: _deviceId);
    });
  }

  String? _eventKey(Map<String, dynamic> decoded) {
    final event = decoded['event'] as String?;
    final payload = decoded['payload'];
    if (event == null || payload is! Map) return null;
    final id =
        payload['event_id'] ??
        payload['message_id'] ??
        payload['client_message_id'] ??
        payload['receipt_id'];
    return id == null ? null : '$event:$id';
  }
}
