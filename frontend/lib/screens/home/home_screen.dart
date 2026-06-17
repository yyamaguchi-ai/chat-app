import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/api_service.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import '../profile/profile_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(roomsProvider);
    final me         = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('チャット'),
        leading: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: CircleAvatar(
              backgroundColor: const Color(0xFF6C63FF),
              child: Text(
                me != null && me.name.isNotEmpty ? me.name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(context: context, delegate: _UserSearchDelegate(ref)),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: roomsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(ApiService.parseError(e))),
        data: (rooms) => rooms.isEmpty
            ? const Center(child: Text('チャットルームがありません\n右上の検索からユーザーを探しましょう',
                textAlign: TextAlign.center))
            : RefreshIndicator(
                onRefresh: () => ref.read(roomsProvider.notifier).refresh(),
                child: ListView.separated(
                  itemCount: rooms.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (ctx, i) => _RoomTile(room: rooms[i]),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateGroup(context, ref),
        child: const Icon(Icons.group_add_rounded),
      ),
    );
  }

  void _showCreateGroup(BuildContext ctx, WidgetRef ref) {
    final nameCtrl      = TextEditingController();
    final searchCtrl    = TextEditingController();
    final selectedUsers = <UserModel>[];
    List<UserModel> searchResults = [];

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('グループを作成', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'グループ名', prefixIcon: Icon(Icons.group)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'メンバーを検索',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (q) async {
                  if (q.length < 2) {
                    setModalState(() => searchResults = []);
                    return;
                  }
                  final results = await ref.read(apiServiceProvider).searchUsers(q);
                  setModalState(() {
                    searchResults = results.map((u) => UserModel.fromJson(u)).toList();
                  });
                },
              ),
              if (searchResults.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...searchResults.map((u) => ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 16, child: Text(u.name[0].toUpperCase())),
                  title: Text(u.name),
                  subtitle: Text(u.email),
                  trailing: selectedUsers.any((s) => s.id == u.id)
                      ? const Icon(Icons.check_circle, color: Color(0xFF6C63FF))
                      : const Icon(Icons.add_circle_outline),
                  onTap: () {
                    setModalState(() {
                      if (selectedUsers.any((s) => s.id == u.id)) {
                        selectedUsers.removeWhere((s) => s.id == u.id);
                      } else {
                        selectedUsers.add(u);
                      }
                    });
                  },
                )),
              ],
              if (selectedUsers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: selectedUsers.map((u) => Chip(
                    label: Text(u.name),
                    onDeleted: () => setModalState(() => selectedUsers.removeWhere((s) => s.id == u.id)),
                  )).toList(),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final api  = ref.read(apiServiceProvider);
                  final room = await api.createGroupRoom(
                    name: nameCtrl.text.trim(),
                    memberIds: selectedUsers.map((u) => u.id).toList(),
                  );
                  await ref.read(roomsProvider.notifier).refresh();
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    ctx.push('/chat/${room['id']}?name=${Uri.encodeComponent(nameCtrl.text.trim())}&type=group');
                  }
                },
                child: const Text('作成する'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  final ChatRoomModel room;
  const _RoomTile({required this.room});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: const Color(0xFF6C63FF).withOpacity(0.15),
        backgroundImage: room.avatar != null ? NetworkImage(room.avatar!) : null,
        child: room.avatar != null
            ? null
            : room.type == 'group'
                ? const Icon(Icons.group, color: Color(0xFF6C63FF))
                : Text(room.name.isNotEmpty ? room.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(room.latestMessage?.content ?? '（メッセージなし）',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      trailing: room.unreadCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFF6C63FF), borderRadius: BorderRadius.circular(12)),
              child: Text('${room.unreadCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))
          : null,
      onTap: () => context.push('/chat/${room.id}?name=${Uri.encodeComponent(room.name)}&type=${room.type}'),
    );
  }
}

class _UserSearchDelegate extends SearchDelegate<void> {
  final WidgetRef ref;
  _UserSearchDelegate(this.ref);

  @override
  String get searchFieldLabel => 'ユーザーを検索...';

  @override
  List<Widget> buildActions(BuildContext ctx) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext ctx) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(ctx, null));

  @override
  Widget buildResults(BuildContext ctx) => _buildSearchResults(ctx);

  @override
  Widget buildSuggestions(BuildContext ctx) =>
      query.length >= 2 ? _buildSearchResults(ctx) : const SizedBox();

  Widget _buildSearchResults(BuildContext ctx) {
    return FutureBuilder<List<dynamic>>(
      future: ref.read(apiServiceProvider).searchUsers(query),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = snap.data ?? [];
        if (users.isEmpty) return const Center(child: Text('ユーザーが見つかりません'));
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (_, i) {
            final u = UserModel.fromJson(users[i]);
            return ListTile(
              leading: CircleAvatar(child: Text(u.name[0].toUpperCase())),
              title: Text(u.name),
              subtitle: Text(u.email),
              onTap: () async {
                final room = await ref.read(apiServiceProvider).createDirectRoom(u.id);
                await ref.read(roomsProvider.notifier).refresh();
                if (ctx.mounted) {
                  close(ctx, null);
                  ctx.push('/chat/${room['id']}?name=${Uri.encodeComponent(u.name)}&type=direct');
                }
              },
            );
          },
        );
      },
    );
  }
}
