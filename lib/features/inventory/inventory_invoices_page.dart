import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class InventoryInvoicesPage extends ConsumerStatefulWidget {
  const InventoryInvoicesPage({super.key});

  @override
  ConsumerState<InventoryInvoicesPage> createState() => _InventoryInvoicesPageState();
}

class _InventoryInvoicesPageState extends ConsumerState<InventoryInvoicesPage> {
  String? _selectedBranchId;
  DateTime? _from;
  DateTime? _to;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final branches = ref.watch(branchesProvider).where((e) => e.isActive).toList();
    _selectedBranchId ??= session?.branchId ?? (branches.isNotEmpty ? branches.first.id : null);

    ref.read(inventoryInvoicesProvider.notifier).setFilters(
          branchId: _selectedBranchId,
          from: _from,
          to: _to,
        );
    final items = ref.watch(inventoryInvoicesProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Fatura', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: !canEdit || _selectedBranchId == null
                  ? null
                  : () async {
                      final createdId = await _createInvoiceDialog(context, branchId: _selectedBranchId!);
                      if (createdId != null && context.mounted) {
                        context.go('/inv/invoices/$createdId');
                      }
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
            for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.name)),
          ],
          onChanged: role == UserRole.branchUser
              ? null
              : (v) => setState(() {
                    _selectedBranchId = v;
                  }),
          decoration: const InputDecoration(labelText: 'Şube'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Başlangıç'),
                child: InkWell(
                  onTap: () async {
                    final picked = await _pickDate(context, initial: _from);
                    if (picked == null) return;
                    setState(() => _from = picked);
                  },
                  child: Text(_from == null ? '' : _fmt(_from!)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Bitiş'),
                child: InkWell(
                  onTap: () async {
                    final picked = await _pickDate(context, initial: _to);
                    if (picked == null) return;
                    setState(() => _to = picked);
                  },
                  child: Text(_to == null ? '' : _fmt(_to!)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _from = null;
                  _to = null;
                }),
                child: const Text('Temizle'),
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
                for (final i in items)
                  ListTile(
                    title: Text(i.invoiceNo),
                    subtitle: Text('${_fmt(i.invoiceDate)}${i.vendorName == null ? '' : ' • ${i.vendorName}'}'),
                    trailing: Text((i.total ?? 0).toStringAsFixed(2)),
                    onTap: () => context.go('/inv/invoices/${i.id}'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<String?> _createInvoiceDialog(BuildContext context, {required String branchId}) async {
    final invoiceNoController = TextEditingController();
    final vendorController = TextEditingController();
    final notesController = TextEditingController();
    DateTime invoiceDate = DateTime.now();

    final createdId = await showDialog<String?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Fatura Ekle'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: invoiceNoController,
                      decoration: const InputDecoration(labelText: 'Fatura No'),
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Tarih'),
                      child: InkWell(
                        onTap: () async {
                          final picked = await _pickDate(context, initial: invoiceDate);
                          if (picked == null) return;
                          setState(() => invoiceDate = picked);
                        },
                        child: Text(_fmt(invoiceDate)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: vendorController,
                      decoration: const InputDecoration(labelText: 'Tedarikçi (opsiyonel)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(labelText: 'Not (opsiyonel)'),
                      maxLines: 2,
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
                  onPressed: () async {
                    final no = invoiceNoController.text.trim();
                    if (no.isEmpty) return;
                    try {
                      final id = await ref.read(inventoryInvoicesProvider.notifier).create(
                            branchId: branchId,
                            invoiceNo: no,
                            invoiceDate: invoiceDate,
                            vendorName: vendorController.text.trim().isEmpty ? null : vendorController.text.trim(),
                            notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                          );
                      if (id == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kaydedilemedi.')),
                          );
                        }
                        return;
                      }
                      if (context.mounted) Navigator.of(context).pop(id);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_errText(e))),
                        );
                      }
                    }
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    invoiceNoController.dispose();
    vendorController.dispose();
    notesController.dispose();
    return createdId;
  }
}

class InventoryInvoiceDetailPage extends ConsumerStatefulWidget {
  const InventoryInvoiceDetailPage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  ConsumerState<InventoryInvoiceDetailPage> createState() => _InventoryInvoiceDetailPageState();
}

class _InventoryInvoiceDetailPageState extends ConsumerState<InventoryInvoiceDetailPage> {
  final _invoiceNoController = TextEditingController();
  final _vendorController = TextEditingController();
  final _notesController = TextEditingController();
  final _discountRateController = TextEditingController();
  final _discountAmountController = TextEditingController();
  final _mealVoucherDiscountController = TextEditingController();

  final _productQueryController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _unitPriceController = TextEditingController(text: '0');

  DateTime? _invoiceDate;
  DateTime? _paymentDate;
  String? _paymentTypeId;
  String? _incomeCenterId;
  InventoryProduct? _selectedProduct;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _productQueryController.addListener(() {
      final q = _productQueryController.text.trim();
      ref.read(inventoryProductsProvider.notifier).setQuery(q);
    });
  }

  @override
  void dispose() {
    _invoiceNoController.dispose();
    _vendorController.dispose();
    _notesController.dispose();
    _discountRateController.dispose();
    _discountAmountController.dispose();
    _mealVoucherDiscountController.dispose();
    _productQueryController.dispose();
    _qtyController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final paymentTypes = ref.watch(paymentTypesProvider).where((e) => e.isActive).toList();
    final incomeCenters = ref.watch(incomeCentersProvider).where((e) => e.isActive).toList();
    final products = ref.watch(inventoryProductsProvider).where((e) => e.isActive).take(50).toList();

    final detail = ref.watch(inventoryInvoiceDetailProvider(widget.invoiceId));
    return detail.when(
      data: (data) {
        final header = data.header;
        final lines = data.lines;
        final total = lines.fold(0.0, (p, e) => p + e.lineTotal);

        if (!_initialized) {
          _invoiceNoController.text = header.invoiceNo;
          _vendorController.text = header.vendorName ?? '';
          _notesController.text = header.notes ?? '';
          _discountRateController.text = header.discountRate?.toString() ?? '';
          _discountAmountController.text = header.discountAmount?.toString() ?? '';
          _mealVoucherDiscountController.text = header.mealVoucherDiscount?.toString() ?? '';
          _invoiceDate = header.invoiceDate;
          _paymentDate = header.paymentDate;
          _paymentTypeId = header.paymentTypeId;
          _incomeCenterId = header.incomeCenterId;
          _initialized = true;
        }

        final paymentTypeIds = paymentTypes.map((e) => e.id).toSet();
        final paymentTypeValue =
            (_paymentTypeId != null && paymentTypeIds.contains(_paymentTypeId)) ? _paymentTypeId : null;
        final incomeCenterIds = incomeCenters.map((e) => e.id).toSet();
        final incomeCenterValue =
            (_incomeCenterId != null && incomeCenterIds.contains(_incomeCenterId)) ? _incomeCenterId : null;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text('Alış Faturası - Ekleme', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                OutlinedButton(
                  onPressed: () => context.go('/inv/invoices'),
                  child: const Text('Kapat'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _invoiceNoController,
                            enabled: canEdit,
                            decoration: const InputDecoration(labelText: 'Fatura No'),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _vendorController,
                            enabled: canEdit,
                            decoration: const InputDecoration(labelText: 'Firma'),
                          ),
                        ),
                        SizedBox(
                          width: 260,
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Ödeme Türü'),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true,
                                value: paymentTypeValue,
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Seçiniz'),
                                  ),
                                  for (final p in paymentTypes)
                                    DropdownMenuItem<String?>(
                                      value: p.id,
                                      child: Text(p.name),
                                    ),
                                ],
                                onChanged: !canEdit
                                    ? null
                                    : (v) {
                                        setState(() => _paymentTypeId = v);
                                      },
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 260,
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Gelir Merkezi'),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true,
                                value: incomeCenterValue,
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Seçiniz'),
                                  ),
                                  for (final g in incomeCenters)
                                    DropdownMenuItem<String?>(
                                      value: g.id,
                                      child: Text(g.name),
                                    ),
                                ],
                                onChanged: !canEdit
                                    ? null
                                    : (v) {
                                        setState(() => _incomeCenterId = v);
                                      },
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: InkWell(
                            onTap: !canEdit
                                ? null
                                : () async {
                                    final picked = await _pickDate(context, initial: _invoiceDate);
                                    if (picked != null) setState(() => _invoiceDate = picked);
                                  },
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'Fatura Tarihi'),
                              child: Text(_invoiceDate == null ? '' : _fmt(_invoiceDate!)),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: InkWell(
                            onTap: !canEdit
                                ? null
                                : () async {
                                    final picked = await _pickDate(context, initial: _paymentDate);
                                    if (picked != null) setState(() => _paymentDate = picked);
                                  },
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'Ödeme Tarihi'),
                              child: Text(_paymentDate == null ? '' : _fmt(_paymentDate!)),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: _discountRateController,
                            enabled: canEdit,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Genel İndirim (%)'),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: _discountAmountController,
                            enabled: canEdit,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'İndirim Tutar'),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: _mealVoucherDiscountController,
                            enabled: canEdit,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Yemek Çeki İndirim'),
                          ),
                        ),
                        SizedBox(
                          width: 520,
                          child: TextField(
                            controller: _notesController,
                            enabled: canEdit,
                            decoration: const InputDecoration(labelText: 'Açıklama'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Toplam: ${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        FilledButton(
                          onPressed: !canEdit
                              ? null
                              : () async {
                                  final rate = double.tryParse(_discountRateController.text.replaceAll(',', '.'));
                                  final amount = double.tryParse(_discountAmountController.text.replaceAll(',', '.'));
                                  final meal = double.tryParse(_mealVoucherDiscountController.text.replaceAll(',', '.'));
                                  try {
                                    await ref.read(inventoryInvoiceActionsProvider).updateHeader(
                                          widget.invoiceId,
                                          invoiceNo: _invoiceNoController.text.trim(),
                                          invoiceDate: _invoiceDate,
                                          vendorName: _vendorController.text.trim(),
                                          notes: _notesController.text.trim(),
                                          paymentTypeId: _paymentTypeId ?? '',
                                          incomeCenterId: _incomeCenterId ?? '',
                                          discountRate: _discountRateController.text.trim().isEmpty ? null : rate,
                                          discountAmount: _discountAmountController.text.trim().isEmpty ? null : amount,
                                          mealVoucherDiscount:
                                              _mealVoucherDiscountController.text.trim().isEmpty ? null : meal,
                                          paymentDate: _paymentDate,
                                        );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Kaydedildi.')),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(_errText(e))),
                                      );
                                    }
                                  }
                                },
                          child: const Text('Kaydet'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _OpenDocsCard(
                    title: 'Açık İrsaliyeler',
                    provider: ref.watch(inventoryOpenDeliveryNotesProvider(header.branchId)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OpenDocsCard(
                    title: 'Açık Siparişler',
                    provider: ref.watch(inventoryOpenPurchaseOrdersProvider(header.branchId)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Stok Kalemleri Ekleme', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 260,
                          child: TextField(
                            controller: _productQueryController,
                            enabled: canEdit,
                            decoration: const InputDecoration(labelText: 'Ürün Ara'),
                          ),
                        ),
                        SizedBox(
                          width: 420,
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Stok Kalemi'),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true,
                                value: _selectedProduct?.id != null && products.any((p) => p.id == _selectedProduct!.id)
                                    ? _selectedProduct!.id
                                    : null,
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Seçiniz'),
                                  ),
                                  for (final p in products)
                                    DropdownMenuItem<String?>(
                                      value: p.id,
                                      child: Text('${p.code ?? ''} ${p.name}'.trim()),
                                    ),
                                ],
                                onChanged: !canEdit
                                    ? null
                                    : (id) {
                                        setState(() {
                                          if (id == null) {
                                            _selectedProduct = null;
                                            return;
                                          }
                                          InventoryProduct? found;
                                          for (final p in products) {
                                            if (p.id == id) {
                                              found = p;
                                              break;
                                            }
                                          }
                                          _selectedProduct = found;
                                        });
                                      },
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _qtyController,
                            enabled: canEdit,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Miktar'),
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: _unitPriceController,
                            enabled: canEdit,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Birim Fiyat'),
                          ),
                        ),
                        FilledButton(
                          onPressed: !canEdit
                              ? null
                              : () async {
                                  final qty = double.tryParse(_qtyController.text.replaceAll(',', '.'));
                                  final price = double.tryParse(_unitPriceController.text.replaceAll(',', '.'));
                                  if (_selectedProduct == null || qty == null || price == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Ürün, miktar ve birim fiyat gerekli.')),
                                    );
                                    return;
                                  }
                                  try {
                                    await ref.read(inventoryInvoiceActionsProvider).addLine(
                                          invoiceId: widget.invoiceId,
                                          productId: _selectedProduct!.id,
                                          description: _selectedProduct!.name,
                                          unit: _selectedProduct!.unit,
                                          quantity: qty,
                                          unitPrice: price,
                                        );
                                    if (!mounted) return;
                                    setState(() {
                                      _selectedProduct = null;
                                      _qtyController.text = '1';
                                      _unitPriceController.text = '0';
                                    });
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(_errText(e))),
                                      );
                                    }
                                  }
                                },
                          child: const Text('Ekle'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (lines.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Satır yok.'),
                ),
              )
            else
              Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Kod')),
                      DataColumn(label: Text('Ürün')),
                      DataColumn(label: Text('Birim')),
                      DataColumn(label: Text('Miktar')),
                      DataColumn(label: Text('Birim Fiyat')),
                      DataColumn(label: Text('Tutar')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (var i = 0; i < lines.length; i++)
                        DataRow(
                          color: WidgetStatePropertyAll(
                            i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
                          ),
                          cells: [
                            DataCell(Text(lines[i].productCode ?? '')),
                            DataCell(Text(lines[i].productName ?? lines[i].description)),
                            DataCell(Text(lines[i].unit ?? '')),
                            DataCell(Text(lines[i].quantity.toStringAsFixed(2))),
                            DataCell(Text(lines[i].unitPrice.toStringAsFixed(2))),
                            DataCell(Text(lines[i].lineTotal.toStringAsFixed(2))),
                            DataCell(
                              IconButton(
                                tooltip: 'Sil',
                                onPressed: !canEdit
                                    ? null
                                    : () => ref.read(inventoryInvoiceActionsProvider).deleteLine(
                                          invoiceId: widget.invoiceId,
                                          lineId: lines[i].id,
                                        ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text(e.toString())),
    );
  }
}

class _OpenDocsCard extends ConsumerWidget {
  const _OpenDocsCard({
    required this.title,
    required this.provider,
  });

  final String title;
  final AsyncValue<List<InventoryOpenDocument>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: provider.when(
          data: (items) {
            if (items.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Kayıt yok.'),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('No')),
                      DataColumn(label: Text('Tarih')),
                      DataColumn(label: Text('Firma')),
                      DataColumn(label: Text('Kalem')),
                      DataColumn(label: Text('Tutar')),
                    ],
                    rows: [
                      for (final d in items)
                        DataRow(
                          cells: [
                            DataCell(Text(d.docNo)),
                            DataCell(Text(_fmt(d.docDate))),
                            DataCell(Text(d.vendorName ?? '')),
                            DataCell(Text((d.linesCount ?? 0).toString())),
                            DataCell(Text((d.total ?? 0).toStringAsFixed(2))),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (e, st) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_errText(e)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<DateTime?> _pickDate(BuildContext context, {DateTime? initial}) {
  final now = DateTime.now();
  final init = initial ?? now;
  return showDatePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    initialDate: DateTime(init.year, init.month, init.day),
  );
}

String _fmt(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final mon = d.month.toString().padLeft(2, '0');
  final y = d.year.toString().padLeft(4, '0');
  return '$day.$mon.$y';
}

String _errText(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (data is Map) {
      final error = data['error'];
      final requestId = data['requestId'];
      final parts = <String>[
        if (status != null) 'HTTP $status',
        if (error != null) error.toString(),
        if (requestId != null) 'rid:${requestId.toString()}',
      ];
      if (parts.isNotEmpty) return parts.join(' ');
    }
    final msg = e.message;
    if (msg != null && msg.trim().isNotEmpty) return msg;
  }
  return e.toString();
}
