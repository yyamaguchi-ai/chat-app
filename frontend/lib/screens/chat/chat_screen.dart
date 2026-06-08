import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/services/pusher_service.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final int roomId;
  final String roomName;

  const ChatScreen({super.key, required this.roomId, required this.roomName});

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
    });
  }

  @override
  void dispose() {
    _pusherService.unsubscribeRoom(widget.roomId);
    _pusherService.dispose();
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
      appBar: AppBar(title: Text(widget.roomName), centerTitle: false),
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
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 8),
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
