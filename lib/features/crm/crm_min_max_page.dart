import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class CrmMinMaxPage extends ConsumerStatefulWidget {
  const CrmMinMaxPage({super.key});

  @override
  ConsumerState<CrmMinMaxPage> createState() => _CrmMinMaxPageState();
}

class _CrmMinMaxPageState extends ConsumerState<CrmMinMaxPage> {
  String? _selectedBranchId;
  final _productController = TextEditingController();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();

  @override
  void dispose() {
    _productController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final branches = ref.watch(branchesProvider).where((e) => e.isActive).toList();
    final items = ref.watch(minMaxDefinitionsProvider);

    _selectedBranchId ??= session?.branchId ?? (branches.isNotEmpty ? branches.first.id : null);
    ref.read(minMaxDefinitionsProvider.notifier).setBranch(_selectedBranchId);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Min/Max Tanımı', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                          ref.read(minMaxDefinitionsProvider.notifier).setBranch(v);
                        },
                  decoration: const InputDecoration(labelText: 'Şube'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _productController,
                        enabled: canEdit && _selectedBranchId != null,
                        decoration: const InputDecoration(labelText: 'Ürün'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _minController,
                        enabled: canEdit && _selectedBranchId != null,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Min'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _maxController,
                        enabled: canEdit && _selectedBranchId != null,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Max'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: FilledButton(
                        onPressed: !canEdit || _selectedBranchId == null
                            ? null
                            : () async {
                          final product = _productController.text.trim();
                          final minVal = double.tryParse(_minController.text.replaceAll(',', '.'));
                          final maxVal = double.tryParse(_maxController.text.replaceAll(',', '.'));
                          if (product.isEmpty || minVal == null || maxVal == null) return;
                          await ref.read(minMaxDefinitionsProvider.notifier).add(
                                branchId: _selectedBranchId!,
                                productName: product,
                                minQty: minVal,
                                maxQty: maxVal,
                              );
                          _productController.clear();
                          _minController.clear();
                          _maxController.clear();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Kaydedildi.')),
                            );
                          }
                        },
                        child: const Text('Kaydet'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_selectedBranchId == null)
                  const Text('Şube seçiniz.')
                else if (items.isEmpty)
                  const Text('Kayıt yok.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Ürün')),
                        DataColumn(label: Text('Min')),
                        DataColumn(label: Text('Max')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (var i = 0; i < items.length; i++)
                          DataRow(
                            color: WidgetStatePropertyAll(
                              i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
                            ),
                            cells: [
                              DataCell(Text(items[i].productName)),
                              DataCell(Text(items[i].minQty.toStringAsFixed(2))),
                              DataCell(Text(items[i].maxQty.toStringAsFixed(2))),
                              DataCell(
                                IconButton(
                                  tooltip: 'Sil',
                                  onPressed: canEdit
                                      ? () => ref.read(minMaxDefinitionsProvider.notifier).delete(
                                            items[i].id,
                                          )
                                      : null,
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
