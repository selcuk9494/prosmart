import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class InventoryWarehousesPage extends ConsumerStatefulWidget {
  const InventoryWarehousesPage({super.key});

  @override
  ConsumerState<InventoryWarehousesPage> createState() =>
      _InventoryWarehousesPageState();
}

class _InventoryWarehousesPageState
    extends ConsumerState<InventoryWarehousesPage> {
  String? _selectedBranchId;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final branches = ref.watch(branchesProvider).where((e) => e.isActive).toList();
    final items = ref.watch(inventoryWarehousesProvider);

    _selectedBranchId ??= session?.branchId ?? (branches.isNotEmpty ? branches.first.id : null);
    ref.read(inventoryWarehousesProvider.notifier).setBranch(_selectedBranchId);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Depolar', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: _selectedBranchId == null
                  ? null
                  : () async {
                      final name = await _textDialog(context, title: 'Depo Ekle');
                      if (name == null || name.trim().isEmpty) return;
                      await ref.read(inventoryWarehousesProvider.notifier).add(
                            branchId: _selectedBranchId!,
                            name: name.trim(),
                          );
                    },
              icon: const Icon(Icons.add),
              label: const Text('Yeni'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedBranchId,
          items: [
            for (final b in branches)
              DropdownMenuItem(value: b.id, child: Text(b.name)),
          ],
          onChanged: role == UserRole.branchUser
              ? null
              : (v) {
                  setState(() => _selectedBranchId = v);
                  ref.read(inventoryWarehousesProvider.notifier).setBranch(v);
                },
          decoration: const InputDecoration(labelText: 'Şube'),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Kayıt yok.'),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final w in items)
                  SwitchListTile(
                    value: w.isActive,
                    onChanged: (_) => ref
                        .read(inventoryWarehousesProvider.notifier)
                        .toggleActive(w.id),
                    title: Text(w.name),
                    subtitle: Text(w.code),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<String?> _textDialog(
    BuildContext context, {
    required String title,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Ad'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }
}
