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
  ConsumerState<InventoryInvoicesPage> createState() =>
      _InventoryInvoicesPageState();
}

class _InventoryInvoicesPageState extends ConsumerState<InventoryInvoicesPage> {
  String? _selectedBranchId;
  DateTime? _from;
  DateTime? _to;
  final _invoiceNoFilterController = TextEditingController();
  final _vendorFilterController = TextEditingController();
  String _docKind = 'purchase_invoice';

  @override
  void dispose() {
    _invoiceNoFilterController.dispose();
    _vendorFilterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final branches = ref
        .watch(branchesProvider)
        .where((e) => e.isActive)
        .toList();
    _selectedBranchId ??=
        session?.branchId ?? (branches.isNotEmpty ? branches.first.id : null);

    ref
        .read(inventoryInvoicesProvider.notifier)
        .setFilters(branchId: _selectedBranchId, from: _from, to: _to);
    final allItems = ref.watch(inventoryInvoicesProvider);
    final invoiceNoQuery = _invoiceNoFilterController.text.trim().toLowerCase();
    final vendorQuery = _vendorFilterController.text.trim().toLowerCase();
    final items = [
      for (final item in allItems)
        if ((invoiceNoQuery.isEmpty ||
                item.invoiceNo.toLowerCase().contains(invoiceNoQuery)) &&
            (vendorQuery.isEmpty ||
                (item.vendorName ?? '').toLowerCase().contains(vendorQuery)))
          item,
    ];
    final total = items.fold<double>(0, (sum, item) => sum + (item.total ?? 0));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _NbosInvoiceToolbar(
          title: 'Fatura / İrsaliye',
          subtitle: 'NBOS belge arama, alış faturası ve stok işleme akışı',
          actions: [
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(inventoryInvoicesProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Yenile'),
            ),
            FilledButton.icon(
              onPressed: !canEdit || _selectedBranchId == null
                  ? null
                  : () => context.go('/inv/invoices/new'),
              icon: const Icon(Icons.add),
              label: const Text('Yeni Belge'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionFrame(
          title: 'Fatura Arama',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'purchase_invoice',
                    label: Text('Alış Faturası'),
                    icon: Icon(Icons.receipt_long_outlined),
                  ),
                  ButtonSegment(
                    value: 'purchase_delivery',
                    label: Text('Alış İrsaliyesi'),
                    icon: Icon(Icons.local_shipping_outlined),
                  ),
                  ButtonSegment(
                    value: 'sales_invoice',
                    label: Text('Satış Faturası'),
                    icon: Icon(Icons.point_of_sale_outlined),
                  ),
                  ButtonSegment(
                    value: 'return_invoice',
                    label: Text('İade / Fark'),
                    icon: Icon(Icons.assignment_return_outlined),
                  ),
                ],
                selected: {_docKind},
                onSelectionChanged: (value) =>
                    setState(() => _docKind = value.first),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
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
                            }),
                      decoration: const InputDecoration(labelText: 'Şube'),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: _DateBox(
                      label: 'Başlangıç',
                      value: _from,
                      onTap: () async {
                        final picked = await _pickDate(context, initial: _from);
                        if (picked == null) return;
                        setState(() => _from = picked);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: _DateBox(
                      label: 'Bitiş',
                      value: _to,
                      onTap: () async {
                        final picked = await _pickDate(context, initial: _to);
                        if (picked == null) return;
                        setState(() => _to = picked);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _invoiceNoFilterController,
                      decoration: const InputDecoration(
                        labelText: 'Belge No',
                        prefixIcon: Icon(Icons.tag_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _vendorFilterController,
                      decoration: const InputDecoration(
                        labelText: 'Firma',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear),
                    label: const Text('Temizle'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _InvoiceMetric(
              label: 'Kayıt',
              value: items.length.toString(),
              icon: Icons.list_alt_outlined,
            ),
            _InvoiceMetric(
              label: 'Toplam',
              value: total.toStringAsFixed(2),
              icon: Icons.payments_outlined,
            ),
            _InvoiceMetric(
              label: 'Belge Tipi',
              value: _docKindLabel(_docKind),
              icon: Icons.description_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Arama kriterlerine uygun belge bulunamadı.'),
            ),
          )
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.primaryContainer,
                ),
                columns: const [
                  DataColumn(label: Text('İşlem')),
                  DataColumn(label: Text('Belge Tipi')),
                  DataColumn(label: Text('Belge No')),
                  DataColumn(label: Text('Tarih')),
                  DataColumn(label: Text('Firma')),
                  DataColumn(label: Text('Ödeme Tarihi')),
                  DataColumn(label: Text('Tutar')),
                  DataColumn(label: Text('Açıklama')),
                ],
                rows: [
                  for (var index = 0; index < items.length; index++)
                    DataRow(
                      color: WidgetStatePropertyAll(
                        index.isEven
                            ? const Color(0xFFFFFFFF)
                            : const Color(0xFFF4F4F4),
                      ),
                      cells: [
                        DataCell(
                          IconButton(
                            tooltip: 'Belgeyi aç',
                            onPressed: () =>
                                context.go('/inv/invoices/${items[index].id}'),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        ),
                        DataCell(Text(_docKindLabel(_docKind))),
                        DataCell(
                          Text(items[index].invoiceNo),
                          onTap: () =>
                              context.go('/inv/invoices/${items[index].id}'),
                        ),
                        DataCell(Text(_fmt(items[index].invoiceDate))),
                        DataCell(Text(items[index].vendorName ?? '')),
                        DataCell(
                          Text(
                            items[index].paymentDate == null
                                ? ''
                                : _fmt(items[index].paymentDate!),
                          ),
                        ),
                        DataCell(
                          Text((items[index].total ?? 0).toStringAsFixed(2)),
                        ),
                        DataCell(Text(items[index].notes ?? '')),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _clearFilters() {
    _invoiceNoFilterController.clear();
    _vendorFilterController.clear();
    setState(() {
      _from = null;
      _to = null;
      _docKind = 'purchase_invoice';
    });
  }
}

class InventoryInvoiceDetailPage extends ConsumerStatefulWidget {
  const InventoryInvoiceDetailPage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  ConsumerState<InventoryInvoiceDetailPage> createState() =>
      _InventoryInvoiceDetailPageState();
}

class InventoryInvoiceCreatePage extends ConsumerStatefulWidget {
  const InventoryInvoiceCreatePage({super.key});

  @override
  ConsumerState<InventoryInvoiceCreatePage> createState() =>
      _InventoryInvoiceCreatePageState();
}

class _DraftInvoiceLine {
  const _DraftInvoiceLine({
    required this.description,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    this.productId,
    this.productCode,
    this.productName,
  });

  final String description;
  final String unit;
  final double quantity;
  final double unitPrice;
  final String? productId;
  final String? productCode;
  final String? productName;

  double get lineTotal => quantity * unitPrice;
}

class _InventoryInvoiceCreatePageState
    extends ConsumerState<InventoryInvoiceCreatePage> {
  final _invoiceNoController = TextEditingController();
  final _vendorController = TextEditingController();
  final _notesController = TextEditingController();
  final _discountRateController = TextEditingController();
  final _discountAmountController = TextEditingController();
  final _mealVoucherDiscountController = TextEditingController();
  final _productQueryController = TextEditingController();
  final _lineDescriptionController = TextEditingController();
  final _lineUnitController = TextEditingController();
  final _lineQtyController = TextEditingController(text: '1');
  final _lineUnitPriceController = TextEditingController(text: '0');

  String? _selectedBranchId;
  DateTime _invoiceDate = DateTime.now();
  DateTime? _paymentDate;
  String? _paymentTypeId;
  String? _incomeCenterId;
  String _docKind = 'purchase_invoice';
  InventoryProduct? _selectedProduct;
  final List<_DraftInvoiceLine> _lines = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _productQueryController.addListener(() {
      ref
          .read(inventoryProductsProvider.notifier)
          .setQuery(_productQueryController.text.trim());
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
    _lineDescriptionController.dispose();
    _lineUnitController.dispose();
    _lineQtyController.dispose();
    _lineUnitPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;
    final branches = ref
        .watch(branchesProvider)
        .where((e) => e.isActive)
        .toList();
    final paymentTypes = ref
        .watch(paymentTypesProvider)
        .where((e) => e.isActive)
        .toList();
    final incomeCenters = ref
        .watch(incomeCentersProvider)
        .where((e) => e.isActive)
        .toList();
    final products = ref
        .watch(inventoryProductsProvider)
        .where((e) => e.isActive)
        .take(60)
        .toList();
    final lineTotal = _lines.fold<double>(
      0,
      (sum, line) => sum + line.lineTotal,
    );
    final discountTotal =
        (_parseDouble(_discountAmountController.text) ?? 0) +
        (_parseDouble(_mealVoucherDiscountController.text) ?? 0);
    final netTotal = lineTotal - discountTotal;

    _selectedBranchId ??=
        session?.branchId ?? (branches.isNotEmpty ? branches.first.id : null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _NbosInvoiceToolbar(
          title: 'Fatura Giriş',
          subtitle: 'Başlık, satırlar ve toplamlar tek ekrandan kaydedilir',
          actions: [
            OutlinedButton.icon(
              onPressed: _saving ? null : () => context.go('/inv/invoices'),
              icon: const Icon(Icons.close),
              label: const Text('Kapat'),
            ),
            FilledButton.icon(
              onPressed: !canEdit || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Kaydet'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _InvoiceMetric(
              label: 'Satır',
              value: _lines.length.toString(),
              icon: Icons.format_list_numbered_outlined,
            ),
            _InvoiceMetric(
              label: 'Brüt Toplam',
              value: _money(lineTotal),
              icon: Icons.receipt_long_outlined,
            ),
            _InvoiceMetric(
              label: 'Net Toplam',
              value: _money(netTotal < 0 ? 0 : netTotal),
              icon: Icons.payments_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionFrame(
          title: 'Belge Tipi',
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'purchase_invoice',
                label: Text('Alış Faturası'),
                icon: Icon(Icons.receipt_long_outlined),
              ),
              ButtonSegment(
                value: 'purchase_delivery',
                label: Text('Alış İrsaliyesi'),
                icon: Icon(Icons.local_shipping_outlined),
              ),
              ButtonSegment(
                value: 'sales_invoice',
                label: Text('Satış Faturası'),
                icon: Icon(Icons.point_of_sale_outlined),
              ),
              ButtonSegment(
                value: 'return_invoice',
                label: Text('İade / Fark'),
                icon: Icon(Icons.assignment_return_outlined),
              ),
            ],
            selected: {_docKind},
            onSelectionChanged: _saving
                ? null
                : (value) => setState(() => _docKind = value.first),
          ),
        ),
        const SizedBox(height: 12),
        _SectionFrame(
          title: 'Belge Bilgileri',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedBranchId,
                  decoration: const InputDecoration(labelText: 'Şube'),
                  items: [
                    for (final b in branches)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: role == UserRole.branchUser || _saving
                      ? null
                      : (value) => setState(() => _selectedBranchId = value),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _invoiceNoController,
                  enabled: !_saving,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Fatura No'),
                ),
              ),
              SizedBox(
                width: 220,
                child: _DateBox(
                  label: 'Fatura Tarihi',
                  value: _invoiceDate,
                  onTap: _saving
                      ? () {}
                      : () async {
                          final picked = await _pickDate(
                            context,
                            initial: _invoiceDate,
                          );
                          if (picked != null) {
                            setState(() => _invoiceDate = picked);
                          }
                        },
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _vendorController,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Firma'),
                ),
              ),
              SizedBox(
                width: 280,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Ödeme Türü'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: _paymentTypeId,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Seçiniz'),
                        ),
                        for (final p in paymentTypes)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _paymentTypeId = value),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 280,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Gelir Merkezi'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      isExpanded: true,
                      value: _incomeCenterId,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Seçiniz'),
                        ),
                        for (final g in incomeCenters)
                          DropdownMenuItem(value: g.id, child: Text(g.name)),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _incomeCenterId = value),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: _DateBox(
                  label: 'Ödeme Tarihi',
                  value: _paymentDate,
                  onTap: _saving
                      ? () {}
                      : () async {
                          final picked = await _pickDate(
                            context,
                            initial: _paymentDate,
                          );
                          if (picked != null) {
                            setState(() => _paymentDate = picked);
                          }
                        },
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _discountRateController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'İndirim (%)'),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _discountAmountController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'İndirim Tutar'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _mealVoucherDiscountController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Yemek Çeki İndirim',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 540,
                child: TextField(
                  controller: _notesController,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Açıklama'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionFrame(
          title: 'Satır Girişi',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _productQueryController,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Ürün Ara',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Ürün'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          value:
                              _selectedProduct != null &&
                                  products.any(
                                    (p) => p.id == _selectedProduct!.id,
                                  )
                              ? _selectedProduct!.id
                              : null,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Serbest satır'),
                            ),
                            for (final p in products)
                              DropdownMenuItem<String?>(
                                value: p.id,
                                child: Text('${p.code ?? ''} ${p.name}'.trim()),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (id) {
                                  setState(() {
                                    _selectedProduct = id == null
                                        ? null
                                        : products.firstWhere(
                                            (p) => p.id == id,
                                          );
                                    if (_selectedProduct != null) {
                                      _lineDescriptionController.text =
                                          _selectedProduct!.name;
                                      _lineUnitController.text =
                                          _selectedProduct!.unit;
                                    }
                                  });
                                },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    child: TextField(
                      controller: _lineDescriptionController,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Açıklama'),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _lineUnitController,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Birim'),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _lineQtyController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Miktar'),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _lineUnitPriceController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Birim Fiyat',
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _addDraftLine,
                    icon: const Icon(Icons.add),
                    label: const Text('Satır Ekle'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Henüz satır eklenmedi.'),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.primaryContainer,
                    ),
                    columns: const [
                      DataColumn(label: Text('Kod')),
                      DataColumn(label: Text('Ürün / Açıklama')),
                      DataColumn(label: Text('Birim')),
                      DataColumn(label: Text('Miktar')),
                      DataColumn(label: Text('Birim Fiyat')),
                      DataColumn(label: Text('Tutar')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (var i = 0; i < _lines.length; i++)
                        DataRow(
                          color: WidgetStatePropertyAll(
                            i.isEven
                                ? const Color(0xFFFFFFFF)
                                : const Color(0xFFF4F4F4),
                          ),
                          cells: [
                            DataCell(Text(_lines[i].productCode ?? '')),
                            DataCell(
                              Text(
                                _lines[i].productName ?? _lines[i].description,
                              ),
                            ),
                            DataCell(Text(_lines[i].unit)),
                            DataCell(
                              Text(_lines[i].quantity.toStringAsFixed(2)),
                            ),
                            DataCell(Text(_money(_lines[i].unitPrice))),
                            DataCell(Text(_money(_lines[i].lineTotal))),
                            DataCell(
                              IconButton(
                                tooltip: 'Satırı sil',
                                onPressed: _saving
                                    ? null
                                    : () => setState(() => _lines.removeAt(i)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Toplam: ${_money(lineTotal)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _addDraftLine() {
    final description = _lineDescriptionController.text.trim();
    final unit = _lineUnitController.text.trim().isEmpty
        ? (_selectedProduct?.unit ?? 'adet')
        : _lineUnitController.text.trim();
    final quantity = _parseDouble(_lineQtyController.text);
    final unitPrice = _parseDouble(_lineUnitPriceController.text);

    if (description.isEmpty) {
      _showMessage('Satır açıklaması gerekli.');
      return;
    }
    if (quantity == null || quantity == 0) {
      _showMessage('Miktar gerekli.');
      return;
    }
    if (unitPrice == null) {
      _showMessage('Birim fiyat gerekli.');
      return;
    }

    setState(() {
      _lines.add(
        _DraftInvoiceLine(
          productId: _selectedProduct?.id,
          productCode: _selectedProduct?.code,
          productName: _selectedProduct?.name,
          description: description,
          unit: unit,
          quantity: quantity,
          unitPrice: unitPrice,
        ),
      );
      _selectedProduct = null;
      _lineDescriptionController.clear();
      _lineUnitController.clear();
      _lineQtyController.text = '1';
      _lineUnitPriceController.text = '0';
    });
  }

  Future<void> _save() async {
    final branchId = _selectedBranchId;
    final invoiceNo = _invoiceNoController.text.trim();
    if (branchId == null || branchId.isEmpty) {
      _showMessage('Şube seçimi gerekli.');
      return;
    }
    if (invoiceNo.isEmpty) {
      _showMessage('Fatura No gerekli.');
      return;
    }
    if (_lines.isEmpty) {
      _showMessage('En az bir fatura satırı ekleyin.');
      return;
    }

    setState(() => _saving = true);
    try {
      final notesText = _notesController.text.trim();
      final createdId = await ref
          .read(inventoryInvoicesProvider.notifier)
          .create(
            branchId: branchId,
            invoiceNo: invoiceNo,
            invoiceDate: _invoiceDate,
            vendorName: _vendorController.text.trim().isEmpty
                ? null
                : _vendorController.text.trim(),
            notes: notesText.isEmpty
                ? _docKindLabel(_docKind)
                : '${_docKindLabel(_docKind)} • $notesText',
            paymentTypeId: _paymentTypeId,
            incomeCenterId: _incomeCenterId,
            discountRate: _parseDouble(_discountRateController.text),
            discountAmount: _parseDouble(_discountAmountController.text),
            mealVoucherDiscount: _parseDouble(
              _mealVoucherDiscountController.text,
            ),
            paymentDate: _paymentDate,
            lines: [
              for (final line in _lines)
                (
                  description: line.description,
                  quantity: line.quantity,
                  unitPrice: line.unitPrice,
                  productId: line.productId,
                  unit: line.unit,
                ),
            ],
          );
      if (createdId == null) {
        _showMessage('Fatura oluşturulamadı.');
        return;
      }

      if (!mounted) return;
      context.go('/inv/invoices/$createdId');
    } catch (e) {
      if (mounted) _showMessage(_errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  double? _parseDouble(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _NbosInvoiceToolbar extends StatelessWidget {
  const _NbosInvoiceToolbar({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: scheme.primary, width: 4)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.receipt_long_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(subtitle),
                ],
              ),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value == null ? '' : _fmt(value!)),
      ),
    );
  }
}

class _InvoiceMetric extends StatelessWidget {
  const _InvoiceMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(value, style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionFrame extends StatelessWidget {
  const _SectionFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

class _InventoryInvoiceDetailPageState
    extends ConsumerState<InventoryInvoiceDetailPage> {
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

    final paymentTypes = ref
        .watch(paymentTypesProvider)
        .where((e) => e.isActive)
        .toList();
    final incomeCenters = ref
        .watch(incomeCentersProvider)
        .where((e) => e.isActive)
        .toList();
    final products = ref
        .watch(inventoryProductsProvider)
        .where((e) => e.isActive)
        .take(50)
        .toList();

    final detail = ref.watch(inventoryInvoiceDetailProvider(widget.invoiceId));
    return detail.when(
      data: (data) {
        final header = data.header;
        final lines = data.lines;
        final stockPost = data.stockPost;
        final total = lines.fold(0.0, (p, e) => p + e.lineTotal);
        final hasStockLines = lines.any(
          (e) => e.productId != null && e.productId!.isNotEmpty,
        );

        if (!_initialized) {
          _invoiceNoController.text = header.invoiceNo;
          _vendorController.text = header.vendorName ?? '';
          _notesController.text = header.notes ?? '';
          _discountRateController.text = header.discountRate?.toString() ?? '';
          _discountAmountController.text =
              header.discountAmount?.toString() ?? '';
          _mealVoucherDiscountController.text =
              header.mealVoucherDiscount?.toString() ?? '';
          _invoiceDate = header.invoiceDate;
          _paymentDate = header.paymentDate;
          _paymentTypeId = header.paymentTypeId;
          _incomeCenterId = header.incomeCenterId;
          _initialized = true;
        }

        final paymentTypeIds = paymentTypes.map((e) => e.id).toSet();
        final paymentTypeValue =
            (_paymentTypeId != null && paymentTypeIds.contains(_paymentTypeId))
            ? _paymentTypeId
            : null;
        final incomeCenterIds = incomeCenters.map((e) => e.id).toSet();
        final incomeCenterValue =
            (_incomeCenterId != null &&
                incomeCenterIds.contains(_incomeCenterId))
            ? _incomeCenterId
            : null;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _NbosInvoiceToolbar(
              title: 'Alış Faturası Kartı',
              subtitle:
                  '${header.invoiceNo} • ${header.vendorName?.isNotEmpty == true ? header.vendorName! : 'Firma seçilmedi'}',
              actions: [
                OutlinedButton.icon(
                  onPressed: () => context.go('/inv/invoices'),
                  icon: const Icon(Icons.close),
                  label: const Text('Kapat'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InvoiceMetric(
                  label: 'Belge No',
                  value: header.invoiceNo,
                  icon: Icons.tag_outlined,
                ),
                _InvoiceMetric(
                  label: 'Tarih',
                  value: _fmt(header.invoiceDate),
                  icon: Icons.event_outlined,
                ),
                _InvoiceMetric(
                  label: 'Toplam',
                  value: total.toStringAsFixed(2),
                  icon: Icons.payments_outlined,
                ),
                _InvoiceMetric(
                  label: 'Stok',
                  value: stockPost == null ? 'İşlenmedi' : 'İşlendi',
                  icon: stockPost == null
                      ? Icons.inventory_2_outlined
                      : Icons.check_circle_outline,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionFrame(
              title: 'Belge Bilgileri',
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
                          decoration: const InputDecoration(
                            labelText: 'Fatura No',
                          ),
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
                          decoration: const InputDecoration(
                            labelText: 'Ödeme Türü',
                          ),
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
                          decoration: const InputDecoration(
                            labelText: 'Gelir Merkezi',
                          ),
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
                                  final picked = await _pickDate(
                                    context,
                                    initial: _invoiceDate,
                                  );
                                  if (picked != null) {
                                    setState(() => _invoiceDate = picked);
                                  }
                                },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Fatura Tarihi',
                            ),
                            child: Text(
                              _invoiceDate == null ? '' : _fmt(_invoiceDate!),
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
                                  final picked = await _pickDate(
                                    context,
                                    initial: _paymentDate,
                                  );
                                  if (picked != null) {
                                    setState(() => _paymentDate = picked);
                                  }
                                },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Ödeme Tarihi',
                            ),
                            child: Text(
                              _paymentDate == null ? '' : _fmt(_paymentDate!),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: _discountRateController,
                          enabled: canEdit,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Genel İndirim (%)',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _discountAmountController,
                          enabled: canEdit,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'İndirim Tutar',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: _mealVoucherDiscountController,
                          enabled: canEdit,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Yemek Çeki İndirim',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 520,
                        child: TextField(
                          controller: _notesController,
                          enabled: canEdit,
                          decoration: const InputDecoration(
                            labelText: 'Açıklama',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Toplam: ${total.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Chip(
                              avatar: Icon(
                                stockPost == null
                                    ? Icons.inventory_2_outlined
                                    : Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: Text(
                                stockPost == null
                                    ? 'Stoka işlenmedi'
                                    : '${stockPost.warehouseName ?? 'Depo'}: ${stockPost.linesCount} satır işlendi',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: !canEdit || !hasStockLines
                            ? null
                            : () async {
                                try {
                                  await ref
                                      .read(inventoryInvoiceActionsProvider)
                                      .postToStock(widget.invoiceId);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Fatura stoğa işlendi.'),
                                      ),
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
                        icon: const Icon(Icons.move_down_outlined),
                        label: const Text('Stoka İşle'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: !canEdit
                            ? null
                            : () async {
                                final rate = double.tryParse(
                                  _discountRateController.text.replaceAll(
                                    ',',
                                    '.',
                                  ),
                                );
                                final amount = double.tryParse(
                                  _discountAmountController.text.replaceAll(
                                    ',',
                                    '.',
                                  ),
                                );
                                final meal = double.tryParse(
                                  _mealVoucherDiscountController.text
                                      .replaceAll(',', '.'),
                                );
                                try {
                                  await ref
                                      .read(inventoryInvoiceActionsProvider)
                                      .updateHeader(
                                        widget.invoiceId,
                                        invoiceNo: _invoiceNoController.text
                                            .trim(),
                                        invoiceDate: _invoiceDate,
                                        vendorName: _vendorController.text
                                            .trim(),
                                        notes: _notesController.text.trim(),
                                        paymentTypeId: _paymentTypeId ?? '',
                                        incomeCenterId: _incomeCenterId ?? '',
                                        discountRate:
                                            _discountRateController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : rate,
                                        discountAmount:
                                            _discountAmountController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : amount,
                                        mealVoucherDiscount:
                                            _mealVoucherDiscountController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : meal,
                                        paymentDate: _paymentDate,
                                      );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Kaydedildi.'),
                                      ),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _OpenDocsCard(
                    title: 'Açık İrsaliyeler',
                    provider: ref.watch(
                      inventoryOpenDeliveryNotesProvider(header.branchId),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OpenDocsCard(
                    title: 'Açık Siparişler',
                    provider: ref.watch(
                      inventoryOpenPurchaseOrdersProvider(header.branchId),
                    ),
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
                    Text(
                      'Stok Kalemleri Ekleme',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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
                            decoration: const InputDecoration(
                              labelText: 'Ürün Ara',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 420,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Stok Kalemi',
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true,
                                value:
                                    _selectedProduct?.id != null &&
                                        products.any(
                                          (p) => p.id == _selectedProduct!.id,
                                        )
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
                                      child: Text(
                                        '${p.code ?? ''} ${p.name}'.trim(),
                                      ),
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
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Miktar',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: _unitPriceController,
                            enabled: canEdit,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Birim Fiyat',
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: !canEdit
                              ? null
                              : () async {
                                  final qty = double.tryParse(
                                    _qtyController.text.replaceAll(',', '.'),
                                  );
                                  final price = double.tryParse(
                                    _unitPriceController.text.replaceAll(
                                      ',',
                                      '.',
                                    ),
                                  );
                                  if (_selectedProduct == null ||
                                      qty == null ||
                                      price == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Ürün, miktar ve birim fiyat gerekli.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  try {
                                    await ref
                                        .read(inventoryInvoiceActionsProvider)
                                        .addLine(
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
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
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
                            i.isEven
                                ? const Color(0xFFFFFFFF)
                                : const Color(0xFFF4F4F4),
                          ),
                          cells: [
                            DataCell(Text(lines[i].productCode ?? '')),
                            DataCell(
                              Text(
                                lines[i].productName ?? lines[i].description,
                              ),
                            ),
                            DataCell(Text(lines[i].unit ?? '')),
                            DataCell(
                              Text(lines[i].quantity.toStringAsFixed(2)),
                            ),
                            DataCell(
                              Text(lines[i].unitPrice.toStringAsFixed(2)),
                            ),
                            DataCell(
                              Text(lines[i].lineTotal.toStringAsFixed(2)),
                            ),
                            DataCell(
                              IconButton(
                                tooltip: 'Sil',
                                onPressed: !canEdit
                                    ? null
                                    : () => ref
                                          .read(inventoryInvoiceActionsProvider)
                                          .deleteLine(
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
  const _OpenDocsCard({required this.title, required this.provider});

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

String _money(double value) => value.toStringAsFixed(2);

String _docKindLabel(String value) {
  return switch (value) {
    'purchase_delivery' => 'Alış İrsaliyesi',
    'sales_invoice' => 'Satış Faturası',
    'return_invoice' => 'İade / Fark',
    _ => 'Alış Faturası',
  };
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
