import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/api_service.dart';
import '../core/services/pusher_service.dart';
import '../data/models/models.dart';

class RoomEvent {
  final int roomId;
  final String type;
  final Map<String, dynamic> payload;
  const RoomEvent(this.roomId, this.type, this.payload);
}

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    final api = ref.read(apiServiceProvider);
    final token = await api.getToken();
    if (token == null) return null;
    try {
      final data = await api.getMe();
      return UserModel.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    try {
      final api  = ref.read(apiServiceProvider);
      final data = await api.login(email: email, password: password);
      state = AsyncData(UserModel.fromJson(data['user']));
    } catch (e) {
      state = AsyncError(ApiService.parseError(e), StackTrace.current);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    state = const AsyncLoading();
    try {
      final api  = ref.read(apiServiceProvider);
      final data = await api.register(
        name: name,
        email: email,
        password: password,
        passwordConfirmation: passwordConfirmation,
      );
      state = AsyncData(UserModel.fromJson(data['user']));
    } catch (e) {
      state = AsyncError(ApiService.parseError(e), StackTrace.current);
    }
  }

  Future<void> logout() async {
    final api = ref.read(apiServiceProvider);
    await api.logout();
    state = const AsyncData(null);
  }

  Future<void> updateProfile({String? name, String? phone}) async {
    final api = ref.read(apiServiceProvider);
    final data = await api.updateProfile(name: name, phone: phone);
    state = AsyncData(UserModel.fromJson(data));
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);

class RoomsNotifier extends AsyncNotifier<List<ChatRoomModel>> {
  final PusherService _pusher = PusherService();
  final Set<int> _subscribedRoomIds = {};
  final _eventsController = StreamController<RoomEvent>.broadcast();

  Stream<RoomEvent> get events => _eventsController.stream;

  @override
  Future<List<ChatRoomModel>> build() async {
    final auth = ref.watch(authProvider);
    if (auth.valueOrNull == null) return [];
    final api = ref.read(apiServiceProvider);
    final rooms = await api.getRooms();
    final list = rooms.map((r) => ChatRoomModel.fromJson(r)).toList();
    _subscribeAll(list);
    return list;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiServiceProvider);
      final rooms = await api.getRooms();
      final list = rooms.map((r) => ChatRoomModel.fromJson(r)).toList();
      _subscribeAll(list);
      return list;
    });
  }

  // chat-room.{id} チャンネルはプラグイン側がチャンネル名で1つしか持てないため、
  // 部屋一覧が読み込まれたタイミングで一括して購読を行う（チャット画面側では購読しない）。
  void _subscribeAll(List<ChatRoomModel> rooms) {
    for (final room in rooms) {
      if (!_subscribedRoomIds.add(room.id)) continue;
      _pusher.subscribeRoom(
        room.id,
        (payload) {
          final message = MessageModel.fromJson(payload['message'] as Map<String, dynamic>);
          ref.read(messagesProvider(room.id).notifier).addMessage(message);
        },
        onRoomDissolved: (payload) {
          _eventsController.add(RoomEvent(room.id, 'dissolved', payload));
          state.whenData((rooms) {
            state = AsyncData(rooms.where((r) => r.id != room.id).toList());
          });
        },
        onRoomUpdated: (payload) {
          _eventsController.add(RoomEvent(room.id, 'updated', payload));
          state.whenData((rooms) {
            final index = rooms.indexWhere((r) => r.id == room.id);
            if (index == -1) return;
            final updated = rooms[index].copyWith(
              name: payload['name'] as String?,
              avatar: payload['avatar'] as String?,
            );
            final newList = [...rooms];
            newList[index] = updated;
            state = AsyncData(newList);
          });
        },
      ).catchError((_) {});
    }
  }

  void updateLatestMessage(int roomId, MessageModel message) {
    state.whenData((rooms) {
      final index = rooms.indexWhere((r) => r.id == roomId);
      if (index == -1) return;
      final updated = rooms[index].copyWith(latestMessage: message);
      final reordered = [...rooms]..removeAt(index);
      reordered.insert(0, updated);
      state = AsyncData(reordered);
    });
  }
}

final roomsProvider = AsyncNotifierProvider<RoomsNotifier, List<ChatRoomModel>>(RoomsNotifier.new);

final roomEventsProvider = StreamProvider<RoomEvent>((ref) {
  return ref.watch(roomsProvider.notifier).events;
});

class MessagesNotifier extends FamilyAsyncNotifier<List<MessageModel>, int> {
  @override
  Future<List<MessageModel>> build(int roomId) async {
    final api = ref.read(apiServiceProvider);
    final data = await api.getMessages(roomId);
    final items = (data['data'] as List).map((m) => MessageModel.fromJson(m)).toList();
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  void addMessage(MessageModel message) {
    state.whenData((messages) {
      if (messages.any((existing) => existing.id == message.id)) return;
      state = AsyncData([...messages, message]);
    });
    ref.read(roomsProvider.notifier).updateLatestMessage(arg, message);
  }

  Future<void> sendMessage(int roomId, String content) async {
    final api = ref.read(apiServiceProvider);
    final data = await api.sendMessage(roomId: roomId, content: content);
    addMessage(MessageModel.fromJson(data));
  }

  Future<void> sendFile(int roomId, String filePath, String fileName) async {
    final api = ref.read(apiServiceProvider);
    final data = await api.sendFile(roomId, filePath, fileName);
    addMessage(MessageModel.fromJson(data));
  }

  Future<void> sendFileBytes(int roomId, Uint8List bytes, String fileName) async {
    final api = ref.read(apiServiceProvider);
    final data = await api.sendFileBytes(roomId, bytes, fileName);
    addMessage(MessageModel.fromJson(data));
  }
}

final messagesProvider = AsyncNotifierProviderFamily<MessagesNotifier, List<MessageModel>, int>(MessagesNotifier.new);
