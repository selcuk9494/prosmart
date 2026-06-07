import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class InventoryTransactionsPage extends ConsumerStatefulWidget {
  const InventoryTransactionsPage({super.key});

  @override
  ConsumerState<InventoryTransactionsPage> createState() =>
      _InventoryTransactionsPageState();
}

class _InventoryTransactionsPageState
    extends ConsumerState<InventoryTransactionsPage> {
  String? _selectedBranchId;
  String? _selectedWarehouseId;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final branches = ref.watch(branchesProvider).where((e) => e.isActive).toList();

    _selectedBranchId ??= session?.branchId ?? (branches.isNotEmpty ? branches.first.id : null);
    ref.read(inventoryTransactionsProvider.notifier).setBranch(_selectedBranchId);
    ref.read(inventoryWarehousesProvider.notifier).setBranch(_selectedBranchId);

    final warehouses = ref.watch(inventoryWarehousesProvider).where((e) => e.isActive).toList();
    if (_selectedWarehouseId != null &&
        warehouses.every((w) => w.id != _selectedWarehouseId)) {
      _selectedWarehouseId = null;
    }
    ref.read(inventoryTransactionsProvider.notifier).setWarehouse(_selectedWarehouseId);

    final items = ref.watch(inventoryTransactionsProvider);
    final dateFmt = DateFormat('yyyy-MM-dd', 'tr_TR');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Stok Hareketleri', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: (_selectedBranchId == null || warehouses.isEmpty)
                  ? null
                  : () async {
                      final form = await _createDialog(
                        context,
                        branchId: _selectedBranchId!,
                        warehouses: warehouses,
                        products: ref.read(inventoryProductsProvider),
                      );
                      if (form == null) return;
                      await ref.read(inventoryTransactionsProvider.notifier).create(
                            branchId: form.branchId,
                            warehouseId: form.warehouseId,
                            businessDate: form.businessDate,
                            kind: form.kind,
                            referenceNo: form.referenceNo,
                            notes: form.notes,
                            lines: form.lines,
                          );
                    },
              icon: const Icon(Icons.add),
              label: const Text('Fiş'),
            ),
          ],
        ),
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
                for (final t in items)
                  ListTile(
                    title: Text('${_kindLabel(t.kind)} • ${dateFmt.format(t.businessDate)}'),
                    subtitle: Text(
                      [
                        if (t.referenceNo != null && t.referenceNo!.isNotEmpty) t.referenceNo!,
                        if (t.notes != null && t.notes!.isNotEmpty) t.notes!,
                      ].join(' • '),
                    ),
                    trailing: Text(
                      warehouses
                          .firstWhere(
                            (w) => w.id == t.warehouseId,
                            orElse: () => const InventoryWarehouse(
                              id: 'x',
                              branchId: 'x',
                              code: '',
                              name: '?',
                            ),
                          )
                          .name,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _kindLabel(String kind) {
    final v = kind.toLowerCase();
    if (v == 'in') return 'Giriş';
    if (v == 'out') return 'Çıkış';
    if (v == 'transfer') return 'Transfer';
    return kind;
  }

  Future<_TxForm?> _createDialog(
    BuildContext context, {
    required String branchId,
    required List<InventoryWarehouse> warehouses,
    required List<InventoryProduct> products,
  }) async {
    final refNoController = TextEditingController();
    final notesController = TextEditingController();
    var selectedWarehouseId = warehouses.first.id;
    var selectedDate = DateTime.now();
    var kind = 'in';
    final lines = <_LineForm>[];

    void addLine() {
      lines.add(
        _LineForm(
          productId: products.isNotEmpty ? products.first.id : '',
          qtyController: TextEditingController(text: '1'),
          costController: TextEditingController(text: '0'),
        ),
      );
    }

    addLine();
    final result = await showDialog<_TxForm>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Stok Fişi'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: kind,
                              items: const [
                                DropdownMenuItem(value: 'in', child: Text('Giriş')),
                                DropdownMenuItem(value: 'out', child: Text('Çıkış')),
                              ],
                              onChanged: (v) => setState(() => kind = v ?? 'in'),
                              decoration: const InputDecoration(labelText: 'Tür'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedWarehouseId,
                              items: [
                                for (final w in warehouses)
                                  DropdownMenuItem(value: w.id, child: Text(w.name)),
                              ],
                              onChanged: (v) =>
                                  setState(() => selectedWarehouseId = v ?? selectedWarehouseId),
                              decoration: const InputDecoration(labelText: 'Depo'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(DateFormat('yyyy-MM-dd', 'tr_TR').format(selectedDate)),
                          ),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) setState(() => selectedDate = picked);
                            },
                            child: const Text('Tarih Seç'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: refNoController,
                        decoration: const InputDecoration(labelText: 'Belge No (opsiyonel)'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(labelText: 'Açıklama (opsiyonel)'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Kalemler',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < lines.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String?>(
                                  initialValue: lines[i].productId.isEmpty ? null : lines[i].productId,
                                  items: [
                                    for (final p in products.where((e) => e.isActive))
                                      DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => lines[i] = lines[i].copyWith(productId: v ?? '')),
                                  decoration: const InputDecoration(labelText: 'Ürün'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: lines[i].qtyController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Miktar'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: lines[i].costController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Birim Maliyet'),
                                ),
                              ),
                              IconButton(
                                onPressed: lines.length <= 1
                                    ? null
                                    : () => setState(() {
                                          lines[i].dispose();
                                          lines.removeAt(i);
                                        }),
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Sil',
                              ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: products.isEmpty ? null : () => setState(addLine),
                          icon: const Icon(Icons.add),
                          label: const Text('Kalem Ekle'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: products.isEmpty
                      ? null
                      : () {
                          final mapped = <InventoryStockLine>[];
                          for (final l in lines) {
                            final productId = l.productId.trim();
                            if (productId.isEmpty) continue;
                            final qty = _parseNum(l.qtyController.text);
                            if (qty == 0) continue;
                            final cost = _parseNum(l.costController.text);
                            mapped.add(
                              InventoryStockLine(
                                productId: productId,
                                quantity: kind == 'out' ? -qty.abs() : qty.abs(),
                                unitCost: cost,
                              ),
                            );
                          }
                          if (mapped.isEmpty) {
                            Navigator.of(context).pop();
                            return;
                          }
                          Navigator.of(context).pop(
                            _TxForm(
                              branchId: branchId,
                              warehouseId: selectedWarehouseId,
                              businessDate: selectedDate,
                              kind: kind,
                              referenceNo: refNoController.text.trim(),
                              notes: notesController.text.trim(),
                              lines: mapped,
                            ),
                          );
                        },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    for (final l in lines) {
      l.dispose();
    }
    refNoController.dispose();
    notesController.dispose();

    return result;
  }

  double _parseNum(String raw) {
    final normalized = raw.replaceAll(' ', '').replaceAll(',', '.').trim();
    return double.tryParse(normalized) ?? 0;
  }
}

class _TxForm {
  const _TxForm({
    required this.branchId,
    required this.warehouseId,
    required this.businessDate,
    required this.kind,
    required this.referenceNo,
    required this.notes,
    required this.lines,
  });

  final String branchId;
  final String warehouseId;
  final DateTime businessDate;
  final String kind;
  final String referenceNo;
  final String notes;
  final List<InventoryStockLine> lines;
}

class _LineForm {
  const _LineForm({
    required this.productId,
    required this.qtyController,
    required this.costController,
  });

  final String productId;
  final TextEditingController qtyController;
  final TextEditingController costController;

  _LineForm copyWith({String? productId}) {
    return _LineForm(
      productId: productId ?? this.productId,
      qtyController: qtyController,
      costController: costController,
    );
  }

  void dispose() {
    qtyController.dispose();
    costController.dispose();
  }
}
