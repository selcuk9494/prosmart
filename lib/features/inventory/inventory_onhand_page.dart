import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class InventoryOnHandPage extends ConsumerStatefulWidget {
  const InventoryOnHandPage({super.key});

  @override
  ConsumerState<InventoryOnHandPage> createState() => _InventoryOnHandPageState();
}

class _InventoryOnHandPageState extends ConsumerState<InventoryOnHandPage> {
  String? _selectedBranchId;
  String? _selectedWarehouseId;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final branches = ref.watch(branchesProvider).where((e) => e.isActive).toList();
    _selectedBranchId ??= session?.branchId ?? (branches.isNotEmpty ? branches.first.id : null);

    ref.read(inventoryWarehousesProvider.notifier).setBranch(_selectedBranchId);
    final warehouses = ref.watch(inventoryWarehousesProvider).where((e) => e.isActive).toList();
    if (_selectedWarehouseId != null &&
        warehouses.every((w) => w.id != _selectedWarehouseId)) {
      _selectedWarehouseId = null;
    }

    final branchId = _selectedBranchId;
    final onhand = branchId == null
        ? const AsyncValue.data([])
        : ref.watch(inventoryOnHandProvider((branchId: branchId, warehouseId: _selectedWarehouseId)));

    final qtyFmt = NumberFormat('#,##0.###', 'tr_TR');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Eldeki Stok', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedBranchId,
                items: [
                  for (final b in branches)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: role == UserRole.branchUser
                    ? null
                    : (v) => setState(() => _selectedBranchId = v),
                decoration: const InputDecoration(labelText: 'Şube'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _selectedWarehouseId,
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Tümü')),
                  for (final w in warehouses)
                    DropdownMenuItem<String?>(value: w.id, child: Text(w.name)),
                ],
                onChanged: (v) => setState(() => _selectedWarehouseId = v),
                decoration: const InputDecoration(labelText: 'Depo'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        onhand.when(
          data: (items) {
            if (items.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Kayıt yok.'),
                ),
              );
            }
            return Card(
              child: Column(
                children: [
                  for (final r in items)
                    ListTile(
                      title: Text(r.productName),
                      subtitle: Text(r.unit),
                      trailing: Text(qtyFmt.format(r.quantity)),
                    ),
                ],
              ),
            );
          },
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Yükleniyor…'),
                ],
              ),
            ),
          ),
          error: (e, st) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Hata: $e'),
            ),
          ),
        ),
      ],
    );
  }
}
