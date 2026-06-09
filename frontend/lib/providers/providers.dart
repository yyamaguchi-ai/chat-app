import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/api_service.dart';
import '../data/models/models.dart';

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
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiServiceProvider);
      final data = await api.login(email: email, password: password);
      return UserModel.fromJson(data['user']);
    });
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiServiceProvider);
      final data = await api.register(
        name: name,
        email: email,
        password: password,
        passwordConfirmation: passwordConfirmation,
      );
      return UserModel.fromJson(data['user']);
    });
  }

  Future<void> logout() async {
    final api = ref.read(apiServiceProvider);
    await api.logout();
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);

class RoomsNotifier extends AsyncNotifier<List<ChatRoomModel>> {
  @override
  Future<List<ChatRoomModel>> build() async {
    final auth = ref.watch(authProvider);
    if (auth.valueOrNull == null) return [];
    final api = ref.read(apiServiceProvider);
    final rooms = await api.getRooms();
    return rooms.map((r) => ChatRoomModel.fromJson(r)).toList();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(apiServiceProvider);
      final rooms = await api.getRooms();
      return rooms.map((r) => ChatRoomModel.fromJson(r)).toList();
    });
  }
}

final roomsProvider = AsyncNotifierProvider<RoomsNotifier, List<ChatRoomModel>>(RoomsNotifier.new);

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
  }

  Future<void> sendMessage(int roomId, String content) async {
    final api = ref.read(apiServiceProvider);
    final data = await api.sendMessage(roomId: roomId, content: content);
    addMessage(MessageModel.fromJson(data));
  }
}

final messagesProvider = AsyncNotifierProviderFamily<MessagesNotifier, List<MessageModel>, int>(MessagesNotifier.new);
