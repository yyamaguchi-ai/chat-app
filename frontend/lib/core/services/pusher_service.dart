import 'dart:convert';

import 'package:pusher_client/pusher_client.dart';

class PusherService {
  static const _appKey = 'YOUR_PUSHER_APP_KEY';
  static const _cluster = 'YOUR_PUSHER_APP_CLUSTER';

  late final PusherClient _pusher;
  Channel? _channel;

  PusherService() {
    final options = PusherOptions(cluster: _cluster, encrypted: true);
    _pusher = PusherClient(_appKey, options, autoConnect: true, enableLogging: false);
  }

  void subscribeRoom(int roomId, void Function(Map<String, dynamic> payload) onMessageCreated) {
    _channel = _pusher.subscribe('chat-room.$roomId');
    _channel?.bind('message.created', (event) {
      if (event?.data == null) return;
      final payload = jsonDecode(event!.data!);
      if (payload is Map<String, dynamic>) {
        onMessageCreated(payload);
      }
    });
  }

  void unsubscribeRoom(int roomId) {
    if (_channel != null) {
      _channel?.unbind('message.created');
      _pusher.unsubscribe('chat-room.$roomId');
      _channel = null;
    }
  }

  void dispose() {
    _channel?.unbind('message.created');
    _pusher.unsubscribeAll();
    _pusher.disconnect();
  }
}
