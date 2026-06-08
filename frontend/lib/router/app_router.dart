import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/chat/chat_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.uri.path == '/login' || state.uri.path == '/register';
      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(
        path: '/chat/:roomId',
        builder: (context, state) {
          final roomId = int.parse(state.pathParameters['roomId']!);
          final roomName = state.uri.queryParameters['name'] ?? 'チャット';
          return ChatScreen(roomId: roomId, roomName: roomName);
        },
      ),
    ],
  );
});
