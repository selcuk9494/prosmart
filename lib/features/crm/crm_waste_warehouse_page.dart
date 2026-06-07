import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class CrmWasteWarehousePage extends ConsumerStatefulWidget {
  const CrmWasteWarehousePage({super.key});

  @override
  ConsumerState<CrmWasteWarehousePage> createState() => _CrmWasteWarehousePageState();
}

class _CrmWasteWarehousePageState extends ConsumerState<CrmWasteWarehousePage> {
  String? _selectedBranchId;
  final _warehouseNameController = TextEditingController();

  @override
  void dispose() {
    _warehouseNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final branches = ref.watch(branchesProvider).where((e) => e.isActive).toList();
    final warehouses = ref.watch(inventoryWarehousesProvider);
    final selectedWarehouseId = ref.watch(wasteWarehouseSelectionProvider);

    _selectedBranchId ??= session?.branchId ?? (branches.isNotEmpty ? branches.first.id : null);
    ref.read(inventoryWarehousesProvider.notifier).setBranch(_selectedBranchId);
    ref.read(wasteWarehouseSelectionProvider.notifier).setBranch(_selectedBranchId);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Düşüm Deposu', style: Theme.of(context).textTheme.titleLarge),
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
                          ref.read(inventoryWarehousesProvider.notifier).setBranch(v);
                          ref.read(wasteWarehouseSelectionProvider.notifier).setBranch(v);
                        },
                  decoration: const InputDecoration(labelText: 'Şube'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _warehouseNameController,
                        enabled: canEdit && _selectedBranchId != null,
                        decoration: const InputDecoration(labelText: 'Depo Adı'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: FilledButton(
                        onPressed: !canEdit || _selectedBranchId == null
                            ? null
                            : () async {
                          final name = _warehouseNameController.text.trim();
                          if (name.isEmpty) return;
                          await ref.read(inventoryWarehousesProvider.notifier).add(
                                branchId: _selectedBranchId!,
                                name: name,
                              );
                          _warehouseNameController.clear();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Kaydedildi.')),
                            );
                          }
                        },
                        child: const Text('Ekle'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (warehouses.isEmpty)
                  const Text('Bu şube için depo yok.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Depo')),
                        DataColumn(label: Text('Düşüm Deposu')),
                      ],
                      rows: [
                        for (var i = 0; i < warehouses.length; i++)
                          DataRow(
                            color: WidgetStatePropertyAll(
                              i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
                            ),
                            cells: [
                              DataCell(Text(warehouses[i].name)),
                              DataCell(
                                Radio<String>(
                                  value: warehouses[i].id,
                                  groupValue: selectedWarehouseId,
                                  onChanged: !canEdit || _selectedBranchId == null
                                      ? null
                                      : (v) async {
                                          if (v == null) return;
                                          await ref.read(wasteWarehouseSelectionProvider.notifier).setSelected(
                                                branchId: _selectedBranchId!,
                                                warehouseId: v,
                                              );
                                        },
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
