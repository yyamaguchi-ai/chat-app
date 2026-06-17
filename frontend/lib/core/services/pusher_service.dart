import 'dart:convert';

import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

class PusherService {
  static const _appKey    = '12ebcea7a3b9ebfc009f';
  static const _cluster   = 'ap3';

  final _pusher = PusherChannelsFlutter.getInstance();

  Future<void> subscribeRoom(
    int roomId,
    void Function(Map<String, dynamic>) onMessageCreated, {
    void Function(Map<String, dynamic>)? onRoomDissolved,
    void Function(Map<String, dynamic>)? onRoomUpdated,
  }) async {
    await _pusher.init(
      apiKey:  _appKey,
      cluster: _cluster,
    );
    await _pusher.subscribe(
      channelName: 'chat-room.$roomId',
      onEvent: (event) {
        final data = event.data;
        if (data == null) return;
        final payload = jsonDecode(data is String ? data : jsonEncode(data));
        if (payload is! Map<String, dynamic>) return;
        switch (event.eventName) {
          case 'message.created':
            onMessageCreated(payload);
            break;
          case 'room.dissolved':
            onRoomDissolved?.call(payload);
            break;
          case 'room.updated':
            onRoomUpdated?.call(payload);
            break;
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
