import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/services/api_service.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';
import 'group_edit_screen.dart';

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
  ChatRoomModel? _room;

  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording   = false;
  int  _recordSeconds = 0;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();

    // ユーザーが上にスクロールしているかを常時追跡
    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;
      _userScrolledUp =
          _scrollCtrl.position.pixels < _scrollCtrl.position.maxScrollExtent - 80;
    });

    // メッセージの購読は roomsProvider 側で一括管理しているため、
    // ここでは messagesProvider の変化を監視してスクロールのみ行う。
    ref.listenManual<AsyncValue<List<MessageModel>>>(
      messagesProvider(widget.roomId),
      (previous, next) {
        if (!mounted) return;
        final prevLen = previous?.valueOrNull?.length ?? 0;
        final nextLen = next.valueOrNull?.length ?? 0;
        if (nextLen > prevLen && !_userScrolledUp) _scrollToBottom();
      },
    );

    ref.listenManual<AsyncValue<RoomEvent>>(
      roomEventsProvider,
      (previous, next) {
        if (!mounted) return;
        final event = next.valueOrNull;
        if (event == null || event.roomId != widget.roomId) return;
        if (event.type == 'dissolved') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('このグループは解散されました')));
          context.pop();
        } else if (event.type == 'updated' && _room != null) {
          setState(() => _room = _room!.copyWith(
                name: event.payload['name'] as String?,
                avatar: event.payload['avatar'] as String?,
              ));
        }
      },
    );

    _loadRoom();
  }

  Future<void> _loadRoom() async {
    try {
      final data = await ref.read(apiServiceProvider).getRoom(widget.roomId);
      if (mounted) setState(() => _room = ChatRoomModel.fromJson(data));
    } catch (_) {}
  }

  bool get _isAdmin {
    final me = ref.read(authProvider).valueOrNull;
    if (me == null || _room == null) return false;
    return _room!.roleOf(me.id) == 'admin';
  }

  Future<void> _openGroupEdit() async {
    if (_room == null) return;
    final updated = await Navigator.of(context).push<ChatRoomModel>(
      MaterialPageRoute(builder: (_) => GroupEditScreen(room: _room!)),
    );
    if (updated != null && mounted) setState(() => _room = updated);
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('実行', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _leaveGroup() async {
    if (!await _confirm('グループを退出', 'このグループから退出しますか？')) return;
    try {
      await ref.read(apiServiceProvider).leaveRoom(widget.roomId);
      ref.read(roomsProvider.notifier).refresh();
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.parseError(e)), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _dissolveGroup() async {
    if (!await _confirm('グループを解散', 'このグループを解散すると元に戻せません。よろしいですか？')) return;
    try {
      await ref.read(apiServiceProvider).dissolveRoom(widget.roomId);
      ref.read(roomsProvider.notifier).refresh();
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.parseError(e)), backgroundColor: Colors.red));
      }
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('マイクの使用許可が必要です')));
      }
      return;
    }
    String path;
    AudioEncoder encoder;
    if (kIsWeb) {
      path    = 'voice_${DateTime.now().millisecondsSinceEpoch}.webm';
      encoder = AudioEncoder.opus;
    } else {
      final dir = await getTemporaryDirectory();
      path    = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      encoder = AudioEncoder.aacLc;
    }
    await _audioRecorder.start(RecordConfig(encoder: encoder), path: path);
    setState(() {
      _isRecording   = true;
      _recordSeconds = 0;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    final path = await _audioRecorder.stop();
    setState(() => _isRecording = false);
    if (path == null) return;
    setState(() => _isSending = true);
    try {
      _userScrolledUp = false;
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}${kIsWeb ? '.webm' : '.m4a'}';
      if (kIsWeb) {
        final response = await http.get(Uri.parse(path));
        await ref.read(messagesProvider(widget.roomId).notifier)
            .sendFileBytes(widget.roomId, response.bodyBytes, fileName);
      } else {
        await ref.read(messagesProvider(widget.roomId).notifier)
            .sendFile(widget.roomId, path, fileName);
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatRecordTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
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

  Future<void> _sendFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    setState(() => _isSending = true);
    try {
      _userScrolledUp = false;
      if (kIsWeb) {
        if (file.bytes != null) {
          await ref.read(messagesProvider(widget.roomId).notifier).sendFileBytes(widget.roomId, file.bytes!, file.name);
        }
      } else {
        if (file.path != null) {
          await ref.read(messagesProvider(widget.roomId).notifier).sendFile(widget.roomId, file.path!, file.name);
        }
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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
          SnackBar(content: Text(ApiService.parseError(e)), backgroundColor: Colors.red));
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
        title: GestureDetector(
          onTap: widget.isGroup ? _openGroupEdit : null,
          child: Row(
            children: [
              if (widget.isGroup) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF6C63FF).withOpacity(0.15),
                  backgroundImage: _room?.avatar != null ? NetworkImage(_room!.avatar!) : null,
                  child: _room?.avatar == null
                      ? const Icon(Icons.group, size: 18, color: Color(0xFF6C63FF))
                      : null,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(_room?.name ?? widget.roomName, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        centerTitle: false,
        actions: [
          if (widget.isGroup)
            IconButton(
              icon: const Icon(Icons.person_add_rounded),
              onPressed: () => _showAddMember(context),
            ),
          if (widget.isGroup)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _openGroupEdit();
                    break;
                  case 'leave':
                    _leaveGroup();
                    break;
                  case 'dissolve':
                    _dissolveGroup();
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'edit', child: Text('グループを編集')),
                const PopupMenuItem(value: 'leave', child: Text('グループを退出')),
                if (_isAdmin)
                  const PopupMenuItem(value: 'dissolve', child: Text('グループを解散')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: msgsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(ApiService.parseError(e))),
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
              child: _isRecording
                  ? Row(
                      children: [
                        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                        const SizedBox(width: 8),
                        Text(_formatRecordTime(_recordSeconds),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('録音中...', style: TextStyle(color: Colors.grey)),
                        ),
                        IconButton(
                          onPressed: _stopAndSendRecording,
                          icon: const Icon(Icons.send_rounded, color: Color(0xFF6C63FF)),
                        ),
                        IconButton(
                          onPressed: () async {
                            _recordTimer?.cancel();
                            await _audioRecorder.stop();
                            setState(() => _isRecording = false);
                          },
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Focus(
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey == LogicalKeyboardKey.enter &&
                                  !HardwareKeyboard.instance.isShiftPressed) {
                                _sendMessage();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
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
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: _isSending ? null : _sendFile,
                          icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF6C63FF)),
                        ),
                        IconButton(
                          onPressed: _isSending ? null : _startRecording,
                          icon: const Icon(Icons.mic_rounded, color: Color(0xFF6C63FF)),
                        ),
                        const SizedBox(width: 4),
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

class _AudioMessageWidget extends StatefulWidget {
  final String url;
  final bool isMe;
  const _AudioMessageWidget({required this.url, required this.isMe});

  @override
  State<_AudioMessageWidget> createState() => _AudioMessageWidgetState();
}

class _AudioMessageWidgetState extends State<_AudioMessageWidget> {
  final _player   = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _isPlaying = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() {
        _isPlaying = false;
        _position  = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (_position >= _duration && _duration > Duration.zero) {
        await _player.seek(Duration.zero);
      }
      await _player.play(UrlSource(widget.url));
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final fg = widget.isMe ? Colors.white : const Color(0xFF6C63FF);
    final bg = widget.isMe ? Colors.white.withOpacity(0.3) : Colors.grey[300];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: Icon(
            _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            size: 36,
            color: fg,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: progress,
                backgroundColor: bg,
                valueColor: AlwaysStoppedAnimation(fg),
                minHeight: 3,
              ),
              const SizedBox(height: 4),
              Text(
                _fmt(_position > Duration.zero ? _position : _duration),
                style: TextStyle(fontSize: 11,
                    color: widget.isMe ? Colors.white70 : Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
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
                  child: message.type == 'image' && message.fileUrl != null
                      ? Image.network(
                          message.fileUrl!,
                          width: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image, size: 20),
                              SizedBox(width: 6),
                              Text('画像を読み込めません', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        )
                      : message.type == 'audio' && message.fileUrl != null
                          ? _AudioMessageWidget(url: message.fileUrl!, isMe: isMe)
                          : message.type == 'file' && message.fileUrl != null
                              ? InkWell(
                                  onTap: () => launchUrl(Uri.parse(message.fileUrl!)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.insert_drive_file, size: 20),
                                    const SizedBox(width: 6),
                                    Flexible(child: Text(message.content.isNotEmpty ? message.content : 'ファイル',
                                        style: TextStyle(
                                          color: isMe ? Colors.white : Colors.black87,
                                          fontSize: 15,
                                          decoration: TextDecoration.underline,
                                        ))),
                                  ]),
                                )
                              : Text(message.content,
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
