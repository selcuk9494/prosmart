import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/stores.dart';

class InventoryProductsPage extends ConsumerStatefulWidget {
  const InventoryProductsPage({super.key});

  @override
  ConsumerState<InventoryProductsPage> createState() =>
      _InventoryProductsPageState();
}

class _InventoryProductsPageState extends ConsumerState<InventoryProductsPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inventoryProductsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Ürünler', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: () async {
                final created = await _createDialog(context);
                if (created == null) return;
                await ref.read(inventoryProductsProvider.notifier).add(
                      name: created.name,
                      unit: created.unit,
                      code: created.code.trim().isEmpty ? null : created.code,
                    );
              },
              icon: const Icon(Icons.add),
              label: const Text('Yeni'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'Ara (ad / kod)',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => ref.read(inventoryProductsProvider.notifier).setQuery(v),
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
                for (final p in items)
                  SwitchListTile(
                    value: p.isActive,
                    onChanged: (_) => ref
                        .read(inventoryProductsProvider.notifier)
                        .toggleActive(p.id),
                    title: Text(p.name),
                    subtitle: Text('${p.unit}${p.code == null ? '' : ' • ${p.code}'}'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<_ProductForm?> _createDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final unitController = TextEditingController(text: 'adet');
    final codeController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<_ProductForm>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Yeni Ürün'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Ad'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Ad gerekli' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: unitController,
                  decoration: const InputDecoration(labelText: 'Birim (adet/kg/lt)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: codeController,
                  decoration: const InputDecoration(labelText: 'Kod (opsiyonel)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.of(context).pop(
                  _ProductForm(
                    name: nameController.text.trim(),
                    unit: unitController.text.trim().isEmpty
                        ? 'adet'
                        : unitController.text.trim(),
                    code: codeController.text.trim(),
                  ),
                );
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    unitController.dispose();
    codeController.dispose();

    return result;
  }
}

class _ProductForm {
  const _ProductForm({
    required this.name,
    required this.unit,
    required this.code,
  });

  final String name;
  final String unit;
  final String code;
}
