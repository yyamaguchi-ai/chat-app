import 'dart:convert';

import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

class PusherService {
  static const _appKey    = 'YOUR_PUSHER_APP_KEY';
  static const _cluster   = 'YOUR_PUSHER_APP_CLUSTER';

  final _pusher = PusherChannelsFlutter.getInstance();

  Future<void> subscribeRoom(int roomId, void Function(Map<String, dynamic>) onMessageCreated) async {
    await _pusher.init(
      apiKey:  _appKey,
      cluster: _cluster,
    );
    await _pusher.subscribe(
      channelName: 'chat-room.$roomId',
      onEvent: (event) {
        if (event.eventName != 'message.created') return;
        final data = event.data;
        if (data == null) return;
        final payload = jsonDecode(data is String ? data : jsonEncode(data));
        if (payload is Map<String, dynamic>) {
          onMessageCreated(payload);
        }
      },
    );
    await _pusher.connect();
  }

  Future<void> unsubscribeRoom(int roomId) async {
    try {
      await _pusher.unsubscribe(channelName: 'chat-room.$roomId');
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _pusher.disconnect();
    } catch (_) {}
  }
}
