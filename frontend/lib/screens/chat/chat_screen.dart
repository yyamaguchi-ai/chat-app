import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/services/pusher_service.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final int roomId;
  final String roomName;
  final bool isGroup;

  const ChatScreen({super.key, required this.roomId, required this.roomName, this.isGroup = false});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageCtrl      = TextEditingController();
  final _scrollCtrl       = ScrollController();
  bool _isSending         = false;
  bool _initialScrollDone = false;
  bool _userScrolledUp    = false;
  late final PusherService _pusherService;

  @override
  void initState() {
    super.initState();

    // ユーザーが上にスクロールしているかを常時追跡
    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;
      _userScrolledUp =
          _scrollCtrl.position.pixels < _scrollCtrl.position.maxScrollExtent - 80;
    });

    _pusherService = PusherService();
    _pusherService.subscribeRoom(widget.roomId, (payload) {
      if (!mounted) return;
      final message = MessageModel.fromJson(payload['message'] as Map<String, dynamic>);
      ref.read(messagesProvider(widget.roomId).notifier).addMessage(message);
      // 最下部にいる場合のみスクロール
      if (!_userScrolledUp) _scrollToBottom();
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _pusherService.unsubscribeRoom(widget.roomId).catchError((_) {});
    _pusherService.dispose().catchError((_) {});
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showAddMember(BuildContext ctx) {
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
              const Text('メンバーを招待', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'ユーザーを検索',
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
                onPressed: selectedUsers.isEmpty ? null : () async {
                  await ref.read(apiServiceProvider).addMembers(
                    widget.roomId,
                    selectedUsers.map((u) => u.id).toList(),
                  );
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('メンバーを招待しました')),
                    );
                  }
                },
                child: const Text('招待する'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    _messageCtrl.clear();
    try {
      _userScrolledUp = false; // 自分の送信後は必ず最下部へ
      await ref.read(messagesProvider(widget.roomId).notifier).sendMessage(widget.roomId, text);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信に失敗しました: $e'), backgroundColor: Colors.red));
        _messageCtrl.text = text;
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me        = ref.watch(authProvider).valueOrNull;
    final msgsAsync = ref.watch(messagesProvider(widget.roomId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomName),
        centerTitle: false,
        actions: [
          if (widget.isGroup)
            IconButton(
              icon: const Icon(Icons.person_add_rounded),
              onPressed: () => _showAddMember(context),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('エラー: $e')),
              data: (messages) {
                // 初回ロード時のみ最下部へ即時ジャンプ
                if (!_initialScrollDone && messages.isNotEmpty) {
                  _initialScrollDone = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _scrollCtrl.hasClients) {
                      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                    }
                  });
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) {
                    final msg  = messages[i];
                    final isMe = msg.userId == me?.id;
                    return _MessageBubble(message: msg, isMe: isMe);
                  },
                );
              },
            ),
          ),
          
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageCtrl,
                      maxLines: 5,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'メッセージを入力...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(color: Color(0xFF6C63FF), shape: BoxShape.circle),
                    child: IconButton(
                      onPressed: _isSending ? null : _sendMessage,
                      icon: _isSending
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    const myColor    = Color(0xFF6C63FF);
    const otherColor = Color(0xFFF0F0F0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: myColor.withOpacity(0.15),
              child: Text((message.user?.name ?? '?')[0].toUpperCase(),
                  style: const TextStyle(color: myColor, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(message.user?.name ?? '',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                  ),
                Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe ? myColor : otherColor,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(18),
                      topRight:    const Radius.circular(18),
                      bottomLeft:  Radius.circular(isMe ? 18 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 18),
                    ),
                  ),
                  child: Text(message.content,
                      style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 15)),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: Text(DateFormat('HH:mm').format(message.createdAt),
                      style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
