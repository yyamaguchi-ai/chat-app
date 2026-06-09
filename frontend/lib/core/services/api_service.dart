import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const _baseUrl = 'http://172.16.10.74:8000/api';
  static const _tokenKey = 'auth_token';

  late final Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString(_tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    final res = await _dio.post('/register', data: {
      'name': name, 'email': email,
      'password': password, 'password_confirmation': passwordConfirmation,
    });
    await _saveToken(res.data['token']);
    return res.data;
  }

  Future<Map<String, dynamic>> login({
    required String email, required String password,
  }) async {
    final res = await _dio.post('/login', data: {'email': email, 'password': password});
    await _saveToken(res.data['token']);
    return res.data;
  }

  Future<void> logout() async {
    await _dio.post('/logout');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/me');
    return res.data;
  }

  Future<List<dynamic>> getRooms() async {
    final res = await _dio.get('/rooms');
    return res.data;
  }

  Future<Map<String, dynamic>> createDirectRoom(int userId) async {
    final res = await _dio.post('/rooms/direct', data: {'user_id': userId});
    return res.data;
  }

  Future<Map<String, dynamic>> createGroupRoom({
    required String name, List<int> memberIds = const [],
  }) async {
    final res = await _dio.post('/rooms/group', data: {'name': name, 'member_ids': memberIds});
    return res.data;
  }

  Future<Map<String, dynamic>> getMessages(int roomId, {int page = 1}) async {
    final res = await _dio.get('/rooms/$roomId/messages', queryParameters: {'page': page});
    return res.data;
  }

  Future<Map<String, dynamic>> sendMessage({
    required int roomId, required String content,
  }) async {
    final res = await _dio.post('/rooms/$roomId/messages', data: {'content': content, 'type': 'text'});
    return res.data;
  }

  Future<Map<String, dynamic>> addMembers(int roomId, List<int> userIds) async {
    final res = await _dio.post('/rooms/$roomId/members', data: {'user_ids': userIds});
    return res.data;
  }

  Future<List<dynamic>> searchUsers(String query) async {
    final res = await _dio.get('/users/search', queryParameters: {'q': query});
    return res.data;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }
}
