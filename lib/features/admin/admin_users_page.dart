import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';

class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  @override
  Widget build(BuildContext context) {
    final items = ref.watch(usersProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Kullanıcı Tanımlama', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton(
              onPressed: () => _openCreateDialog(context),
              child: const Text('Yeni'),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () => context.go('/'),
              child: const Text('Kapat'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: items.isEmpty
                ? const Text('Kayıt yok.')
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Kullanıcı')),
                        DataColumn(label: Text('Ad Soyad')),
                        DataColumn(label: Text('Rol')),
                        DataColumn(label: Text('Aktif')),
                        DataColumn(label: Text('İşlem')),
                      ],
                      rows: [
                        for (var i = 0; i < items.length; i++)
                          DataRow(
                            color: WidgetStatePropertyAll(
                              i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
                            ),
                            cells: [
                              DataCell(Text(items[i].username)),
                              DataCell(Text(items[i].displayName)),
                              DataCell(Text(_roleLabel(items[i].role))),
                              DataCell(
                                Switch(
                                  value: items[i].isActive,
                                  onChanged: (_) => ref.read(usersProvider.notifier).toggleActive(
                                        items[i].id,
                                      ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  children: [
                                    OutlinedButton(
                                      onPressed: () => _openEditDialog(context, items[i]),
                                      child: const Text('Düzenle'),
                                    ),
                                  ],
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

  Future<void> _openCreateDialog(BuildContext context) async {
    final usernameController = TextEditingController();
    final displayNameController = TextEditingController();
    final passwordController = TextEditingController();
    var role = 'branchUser';

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Yeni Kullanıcı'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Kullanıcı Adı'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: displayNameController,
                    decoration: const InputDecoration(labelText: 'Ad Soyad'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    items: const [
                      DropdownMenuItem(value: 'manager', child: Text('Yönetici')),
                      DropdownMenuItem(value: 'accounting', child: Text('Muhasebe')),
                      DropdownMenuItem(value: 'branchUser', child: Text('Şube')),
                    ],
                    onChanged: (v) => role = v ?? role,
                    decoration: const InputDecoration(labelText: 'Rol'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Şifre (boş olabilir)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      );

      if (ok != true) return;

      final username = usernameController.text.trim();
      final displayName = displayNameController.text.trim();
      final password = passwordController.text;
      if (username.isEmpty || displayName.isEmpty) return;

      await ref.read(usersProvider.notifier).addUser(
            username: username,
            displayName: displayName,
            role: role,
            password: password,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaydedildi.')),
        );
      }
    } finally {
      usernameController.dispose();
      displayNameController.dispose();
      passwordController.dispose();
    }
  }

  Future<void> _openEditDialog(BuildContext context, AppUser user) async {
    final displayNameController = TextEditingController(text: user.displayName);
    final passwordController = TextEditingController();
    var role = user.role;
    var removePassword = false;

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setLocalState) {
              return AlertDialog(
                title: Text(user.username),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: displayNameController,
                        decoration: const InputDecoration(labelText: 'Ad Soyad'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        items: const [
                          DropdownMenuItem(value: 'manager', child: Text('Yönetici')),
                          DropdownMenuItem(value: 'accounting', child: Text('Muhasebe')),
                          DropdownMenuItem(value: 'branchUser', child: Text('Şube')),
                        ],
                        onChanged: (v) => role = v ?? role,
                        decoration: const InputDecoration(labelText: 'Rol'),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: removePassword,
                        onChanged: (v) {
                          setLocalState(() {
                            removePassword = v ?? false;
                            if (removePassword) passwordController.clear();
                          });
                        },
                        title: const Text('Şifreyi kaldır (boş şifre)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: passwordController,
                        enabled: !removePassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Yeni şifre (boş bırak = değişme)',
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('İptal'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Kaydet'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (ok != true) return;

      final displayName = displayNameController.text.trim();
      final password = passwordController.text;

      await ref.read(usersProvider.notifier).updateUser(
            user.id,
            displayName: displayName.isEmpty ? null : displayName,
            role: role,
            password: removePassword ? '' : (password.isEmpty ? null : password),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Güncellendi.')),
        );
      }
    } finally {
      displayNameController.dispose();
      passwordController.dispose();
    }
  }

  String _roleLabel(String role) {
    return switch (role) {
      'manager' => 'Yönetici',
      'accounting' => 'Muhasebe',
      _ => 'Şube',
    };
  }
}
