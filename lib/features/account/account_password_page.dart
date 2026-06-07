import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api_client.dart';
import '../../app/config.dart';

class AccountPasswordPage extends ConsumerStatefulWidget {
  const AccountPasswordPage({super.key});

  @override
  ConsumerState<AccountPasswordPage> createState() => _AccountPasswordPageState();
}

class _AccountPasswordPageState extends ConsumerState<AccountPasswordPage> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  var _removePassword = false;
  var _busy = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Şifre Değiştirme', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            OutlinedButton(
              onPressed: _busy ? null : () => context.go('/'),
              child: const Text('Kapat'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _currentController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Mevcut Şifre'),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _removePassword,
                    onChanged: _busy
                        ? null
                        : (v) {
                            setState(() => _removePassword = v ?? false);
                          },
                    title: const Text('Şifreyi kaldır (boş şifre)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newController,
                    enabled: !_removePassword,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Yeni Şifre'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _confirmController,
                    enabled: !_removePassword,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Yeni Şifre (Tekrar)'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Spacer(),
                      SizedBox(
                        width: 140,
                        child: FilledButton(
                          onPressed: _busy ? null : _save,
                          child: const Text('Kaydet'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 140,
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _currentController.clear();
                                  _newController.clear();
                                  _confirmController.clear();
                                  setState(() => _removePassword = false);
                                },
                          child: const Text('İptal'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final current = _currentController.text;
    final newPass = _removePassword ? '' : _newController.text;
    final confirm = _confirmController.text;

    if (!_removePassword && newPass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yeni şifreler eşleşmiyor.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      if (AppConfig.hasApi) {
        final dio = ref.read(dioProvider);
        await dio.post<Map<String, dynamic>>(
          '/auth/change-password',
          data: {
            'currentPassword': current,
            'newPassword': newPass,
          },
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_removePassword ? 'Şifre kaldırıldı.' : 'Şifre güncellendi.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşlem başarısız.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

