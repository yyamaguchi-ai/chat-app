import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/services/api_service.dart';
import '../../data/models/models.dart';
import '../../providers/providers.dart';

class GroupEditScreen extends ConsumerStatefulWidget {
  final ChatRoomModel room;

  const GroupEditScreen({super.key, required this.room});

  @override
  ConsumerState<GroupEditScreen> createState() => _GroupEditScreenState();
}

class _GroupEditScreenState extends ConsumerState<GroupEditScreen> {
  late final TextEditingController _nameCtrl;
  late List<UserModel> _members;
  Uint8List? _pickedBytes;
  String? _pickedPath;
  String? _pickedFileName;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.room.name);
    _members  = List.of(widget.room.members);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (kIsWeb) {
      if (file.bytes == null) return;
      setState(() {
        _pickedBytes    = file.bytes;
        _pickedFileName = file.name;
      });
    } else {
      if (file.path == null) return;
      setState(() {
        _pickedPath     = file.path;
        _pickedFileName = file.name;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('グループ名を入力してください'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSaving = true);
    final api = ref.read(apiServiceProvider);
    try {
      var updated = widget.room.copyWith(name: name);

      if (name != widget.room.name) {
        final data = await api.updateRoomName(widget.room.id, name);
        updated = ChatRoomModel.fromJson(data);
      }

      if (_pickedFileName != null) {
        final data = kIsWeb
            ? await api.updateRoomAvatarBytes(widget.room.id, _pickedBytes!, _pickedFileName!)
            : await api.updateRoomAvatar(widget.room.id, _pickedPath!, _pickedFileName!);
        updated = updated.copyWith(avatar: data['avatar'] as String?);
      }

      ref.read(roomsProvider.notifier).refresh();
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.parseError(e)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showAddMember() {
    final searchCtrl    = TextEditingController();
    final selectedUsers = <UserModel>[];
    List<UserModel> searchResults = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx2, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
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
                    searchResults = results
                        .map((u) => UserModel.fromJson(u))
                        .where((u) => !_members.any((m) => m.id == u.id))
                        .toList();
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
                  final data = await ref.read(apiServiceProvider).addMembers(
                    widget.room.id,
                    selectedUsers.map((u) => u.id).toList(),
                  );
                  final updatedRoom = ChatRoomModel.fromJson(data);
                  if (mounted) setState(() => _members = updatedRoom.members);
                  if (sheetCtx.mounted) {
                    Navigator.of(sheetCtx).pop();
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
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

  ImageProvider? get _previewImage {
    if (_pickedBytes != null) return MemoryImage(_pickedBytes!);
    if (widget.room.avatar != null) return NetworkImage(widget.room.avatar!);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('グループを編集'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C63FF)))
                : const Text('保存', style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: const Color(0xFF6C63FF).withOpacity(0.15),
                      backgroundImage: _previewImage,
                      child: _previewImage == null
                          ? const Icon(Icons.group, size: 40, color: Color(0xFF6C63FF))
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Color(0xFF6C63FF), shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_pickedFileName != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Text('新しい画像: $_pickedFileName',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            ],
            const SizedBox(height: 32),
            TextField(
              controller: _nameCtrl,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'グループ名', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Text('メンバー（${_members.length}）',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showAddMember,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('追加'),
                ),
              ],
            ),
            ..._members.map((u) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 18, child: Text(u.name[0].toUpperCase())),
              title: Text(u.name),
              subtitle: u.role == 'admin' ? const Text('管理者') : null,
            )),
          ],
        ),
      ),
    );
  }
}
