import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class InventoryCountsPage extends ConsumerStatefulWidget {
  const InventoryCountsPage({super.key});

  @override
  ConsumerState<InventoryCountsPage> createState() => _InventoryCountsPageState();
}

class _InventoryCountsPageState extends ConsumerState<InventoryCountsPage> {
  String? _selectedBranchId;
  String? _selectedWarehouseId;
  String? _selectedStatus;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final branches = ref.watch(branchesProvider).where((e) => e.isActive).toList();

    _selectedBranchId ??=
        session?.branchId ?? (branches.isNotEmpty ? branches.first.id : null);

    ref.read(inventoryCountsProvider.notifier).setBranch(_selectedBranchId);
    ref.read(inventoryCountsProvider.notifier).setWarehouse(_selectedWarehouseId);
    ref.read(inventoryCountsProvider.notifier).setStatus(_selectedStatus);
    ref.read(inventoryWarehousesProvider.notifier).setBranch(_selectedBranchId);

    final warehouses =
        ref.watch(inventoryWarehousesProvider).where((e) => e.isActive).toList();
    if (_selectedWarehouseId != null &&
        warehouses.every((w) => w.id != _selectedWarehouseId)) {
      _selectedWarehouseId = null;
    }

    final items = ref.watch(inventoryCountsProvider);
    final fmt = DateFormat('yyyy-MM-dd', 'tr_TR');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Depo Sayım', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: (_selectedBranchId == null || warehouses.isEmpty)
                  ? null
                  : () async {
                      final form = await _createDialog(
                        context,
                        warehouses: warehouses,
                      );
                      if (form == null) return;

                      final id = await ref
                          .read(inventoryCountsProvider.notifier)
                          .createDraft(
                            branchId: _selectedBranchId!,
                            warehouseId: form.warehouseId,
                            businessDate: form.businessDate,
                          );
                      if (!context.mounted) return;
                      if (id != null && id.isNotEmpty) {
                        context.go('/inv/counts/$id');
                      }
                    },
              icon: const Icon(Icons.add),
              label: const Text('Yeni Sayım'),
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
                    : (v) => setState(() {
                          _selectedBranchId = v;
                          _selectedWarehouseId = null;
                        }),
                decoration: const InputDecoration(labelText: 'Şube'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _selectedWarehouseId,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tümü'),
                  ),
                  for (final w in warehouses)
                    DropdownMenuItem<String?>(
                      value: w.id,
                      child: Text(w.name),
                    ),
                ],
                onChanged: (v) => setState(() => _selectedWarehouseId = v),
                decoration: const InputDecoration(labelText: 'Depo'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _selectedStatus,
          items: const [
            DropdownMenuItem<String?>(value: null, child: Text('Tümü')),
            DropdownMenuItem<String?>(value: 'draft', child: Text('Taslak')),
            DropdownMenuItem<String?>(value: 'submitted', child: Text('Gönderildi')),
            DropdownMenuItem<String?>(value: 'approved', child: Text('Onaylandı')),
            DropdownMenuItem<String?>(value: 'rejected', child: Text('Reddedildi')),
          ],
          onChanged: (v) => setState(() => _selectedStatus = v),
          decoration: const InputDecoration(labelText: 'Durum'),
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
                for (final c in items)
                  ListTile(
                    onTap: () => context.go('/inv/counts/${c.id}'),
                    title: Text(
                      '${fmt.format(c.businessDate)} • ${_statusLabel(c.status)}',
                    ),
                    subtitle: Text(
                      [
                        c.warehouseName ?? '',
                        if (c.linesCount > 0) '${c.linesCount} kalem',
                      ].where((e) => e.trim().isNotEmpty).join(' • '),
                    ),
                    trailing: Text(
                      c.diffAbsTotal.toStringAsFixed(3),
                      style: TextStyle(
                        color: c.diffAbsTotal.abs() > 0.0005
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return 'Taslak';
      case 'submitted':
        return 'Gönderildi';
      case 'approved':
        return 'Onaylandı';
      case 'rejected':
        return 'Reddedildi';
      default:
        return status;
    }
  }

  Future<_CreateCountForm?> _createDialog(
    BuildContext context, {
    required List<InventoryWarehouse> warehouses,
  }) async {
    var selectedWarehouseId = warehouses.first.id;
    var selectedDate = DateTime.now();

    String dateText() =>
        DateFormat('yyyy-MM-dd', 'tr_TR').format(selectedDate);

    return showDialog<_CreateCountForm>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Sayım Fişi'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedWarehouseId,
                      items: [
                        for (final w in warehouses)
                          DropdownMenuItem(value: w.id, child: Text(w.name)),
                      ],
                      onChanged: (v) => setState(
                        () => selectedWarehouseId = v ?? selectedWarehouseId,
                      ),
                      decoration: const InputDecoration(labelText: 'Depo'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Tarih'),
                            child: Text(dateText()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => selectedDate = picked);
                            }
                          },
                          child: const Text('Seç'),
                        ),
                      ],
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
                  onPressed: () => Navigator.of(context).pop(
                    _CreateCountForm(
                      warehouseId: selectedWarehouseId,
                      businessDate: selectedDate,
                    ),
                  ),
                  child: const Text('Oluştur'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class InventoryCountDetailPage extends ConsumerStatefulWidget {
  const InventoryCountDetailPage({super.key, required this.countId});

  final String countId;

  @override
  ConsumerState<InventoryCountDetailPage> createState() =>
      _InventoryCountDetailPageState();
}

class _InventoryCountDetailPageState
    extends ConsumerState<InventoryCountDetailPage> {
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _extraProductIds = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;

    final detail = ref.watch(inventoryStockCountDetailProvider(widget.countId));
    final products = ref.watch(inventoryProductsProvider).where((p) => p.isActive).toList();

    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Hata: $e'),
            ),
          ),
        ],
      ),
      data: (data) {
        final h = data.header;
        final canManage = role == UserRole.manager;
        final isOwner = session?.userId == h.createdByUserId;
        final canEdit = (role == UserRole.manager || role == UserRole.accounting) ||
            (isOwner && (h.status == 'draft' || h.status == 'rejected'));
        final canSubmit = isOwner && (h.status == 'draft' || h.status == 'rejected');

        final lines = <InventoryStockCountLine>[
          ...data.lines,
          for (final pId in _extraProductIds)
            if (data.lines.every((l) => l.productId != pId))
              InventoryStockCountLine(
                productId: pId,
                productName: products.firstWhere(
                  (p) => p.id == pId,
                  orElse: () => InventoryProduct(id: pId, name: '?', unit: 'adet'),
                ).name,
                unit: products.firstWhere(
                  (p) => p.id == pId,
                  orElse: () => InventoryProduct(id: pId, name: '?', unit: 'adet'),
                ).unit,
                countedQty: 0,
                onhandQty: 0,
                diffQty: 0,
              ),
        ];

        for (final l in lines) {
          _controllers.putIfAbsent(
            l.productId,
            () => TextEditingController(text: l.countedQty.toString()),
          );
          _controllers[l.productId]!.text = _controllers[l.productId]!.text.isEmpty
              ? l.countedQty.toString()
              : _controllers[l.productId]!.text;
        }

        final fmt = DateFormat('yyyy-MM-dd', 'tr_TR');

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text('Sayım Detay', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                if (canEdit)
                  FilledButton(
                    onPressed: () async {
                      await _save(context, lines);
                    },
                    child: const Text('Kaydet'),
                  ),
                if (canEdit) const SizedBox(width: 8),
                if (canSubmit)
                  FilledButton(
                    onPressed: () async {
                      await _save(context, lines);
                      await ref
                          .read(inventoryCountsProvider.notifier)
                          .submit(widget.countId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Onaya gönderildi.')),
                        );
                      }
                    },
                    child: const Text('Onaya Gönder'),
                  ),
                if (canManage && h.status == 'submitted') const SizedBox(width: 8),
                if (canManage && h.status == 'submitted')
                  FilledButton(
                    onPressed: () async {
                      await ref
                          .read(inventoryCountsProvider.notifier)
                          .approve(widget.countId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Onaylandı.')),
                        );
                      }
                    },
                    child: const Text('Onayla'),
                  ),
                if (canManage && h.status == 'submitted') const SizedBox(width: 8),
                if (canManage && h.status == 'submitted')
                  OutlinedButton(
                    onPressed: () async {
                      final reason = await _textDialog(
                        context,
                        title: 'Reddetme Sebebi',
                        label: 'Sebep',
                      );
                      if (reason == null || reason.trim().isEmpty) return;
                      await ref.read(inventoryCountsProvider.notifier).reject(
                            countId: widget.countId,
                            reason: reason.trim(),
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reddedildi.')),
                        );
                      }
                    },
                    child: const Text('Reddet'),
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
                    Text(
                      '${fmt.format(h.businessDate)} • ${_statusLabel(h.status)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        Text('Şube: ${h.branchName ?? h.branchId}'),
                        Text('Depo: ${h.warehouseName ?? h.warehouseId}'),
                        Text('Kalem: ${lines.length}'),
                        Text(
                          'Fark(∑|Δ|): ${data.totals.diffAbsTotal.toStringAsFixed(3)}',
                          style: TextStyle(
                            color: data.totals.diffAbsTotal.abs() > 0.0005
                                ? Colors.red
                                : Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (h.rejectionReason != null &&
                        h.rejectionReason!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('Red Sebebi: ${h.rejectionReason}'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Kalemler', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (canEdit)
                  OutlinedButton.icon(
                    onPressed: products.isEmpty
                        ? null
                        : () async {
                            final pid = await _pickProduct(
                              context,
                              products: products,
                              existing: lines.map((e) => e.productId).toSet(),
                            );
                            if (pid == null) return;
                            setState(() {
                              _extraProductIds.add(pid);
                              _controllers.putIfAbsent(
                                pid,
                                () => TextEditingController(text: '0'),
                              );
                            });
                          },
                    icon: const Icon(Icons.add),
                    label: const Text('Kalem'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Ürün')),
                      DataColumn(label: Text('Birim')),
                      DataColumn(label: Text('Eldeki')),
                      DataColumn(label: Text('Sayılan')),
                      DataColumn(label: Text('Fark')),
                    ],
                    rows: [
                      for (var i = 0; i < lines.length; i++)
                        _row(lines[i], i, canEdit),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  DataRow _row(InventoryStockCountLine line, int index, bool canEdit) {
    final predicted = _predictedDiff(line);
    return DataRow(
      color: WidgetStatePropertyAll(
        index.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
      ),
      cells: [
        DataCell(Text(line.productName)),
        DataCell(Text(line.unit)),
        DataCell(Text(line.onhandQty.toStringAsFixed(3))),
        DataCell(
          SizedBox(
            width: 120,
            child: TextFormField(
              controller: _controllers[line.productId],
              enabled: canEdit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
            ),
          ),
        ),
        DataCell(
          Text(
            predicted.toStringAsFixed(3),
            style: TextStyle(
              color: predicted.abs() > 0.0005 ? Colors.red : null,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  double _parseQty(String? raw) {
    final v = (raw ?? '').trim().replaceAll(',', '.');
    return double.tryParse(v) ?? 0;
  }

  double _predictedDiff(InventoryStockCountLine line) {
    final controller = _controllers[line.productId];
    final counted = _parseQty(controller?.text);
    return counted - line.onhandQty;
  }

  Future<void> _save(BuildContext context, List<InventoryStockCountLine> lines) async {
    final payload = <({String productId, double countedQty})>[];
    for (final l in lines) {
      final counted = _parseQty(_controllers[l.productId]?.text);
      payload.add((productId: l.productId, countedQty: counted));
    }
    await ref.read(inventoryCountsProvider.notifier).saveLines(
          countId: widget.countId,
          lines: payload,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedildi.')),
      );
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return 'Taslak';
      case 'submitted':
        return 'Gönderildi';
      case 'approved':
        return 'Onaylandı';
      case 'rejected':
        return 'Reddedildi';
      default:
        return status;
    }
  }

  Future<String?> _pickProduct(
    BuildContext context, {
    required List<InventoryProduct> products,
    required Set<String> existing,
  }) async {
    String q = '';
    InventoryProduct? selected;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final filtered = products
                .where(
                  (p) =>
                      p.name.toLowerCase().contains(q.toLowerCase()) ||
                      (p.code ?? '').toLowerCase().contains(q.toLowerCase()),
                )
                .where((p) => !existing.contains(p.id))
                .take(100)
                .toList();
            selected ??= filtered.isNotEmpty ? filtered.first : null;

            return AlertDialog(
              title: const Text('Ürün Seç'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(labelText: 'Ara'),
                      onChanged: (v) => setState(() => q = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selected?.id,
                      items: [
                        for (final p in filtered)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              [p.code, p.name].whereType<String>().where((e) => e.isNotEmpty).join(' • '),
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        selected = filtered.where((p) => p.id == v).firstOrNull;
                      }),
                      decoration: const InputDecoration(labelText: 'Ürün'),
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
                  onPressed: selected == null ? null : () => Navigator.of(context).pop(selected!.id),
                  child: const Text('Ekle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _textDialog(
    BuildContext context, {
    required String title,
    required String label,
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
            decoration: InputDecoration(labelText: label),
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

class _CreateCountForm {
  const _CreateCountForm({
    required this.warehouseId,
    required this.businessDate,
  });

  final String warehouseId;
  final DateTime businessDate;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
