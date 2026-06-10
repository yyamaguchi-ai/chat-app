import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/api_service.dart';
import '../../providers/providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _isSaving   = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).valueOrNull;
    if (user != null) {
      _nameCtrl.text  = user.name;
      _phoneCtrl.text = user.phone ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ニックネームを入力してください'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ref.read(authProvider.notifier).updateProfile(
        name:  _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('プロフィールを更新しました')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.parseError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: const Color(0xFF6C63FF),
                  child: Text(
                    user != null && user.name.isNotEmpty
                        ? user.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 36,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  user?.email ?? '',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'ニックネーム',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '電話番号（非公開）',
                  prefixIcon: Icon(Icons.phone_outlined),
                  helperText: '他のユーザーには表示されません',
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('保存する'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
