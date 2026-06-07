import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class InventoryRecipesPage extends ConsumerStatefulWidget {
  const InventoryRecipesPage({super.key});

  @override
  ConsumerState<InventoryRecipesPage> createState() => _InventoryRecipesPageState();
}

class _InventoryRecipesPageState extends ConsumerState<InventoryRecipesPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    ref.read(inventoryRecipesProvider.notifier).setQuery(_searchController.text);
    final items = ref.watch(inventoryRecipesProvider);

    final products = ref.watch(inventoryProductsProvider).where((p) => p.isActive).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Reçete', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: canEdit && products.isNotEmpty
                  ? () async {
                      final form = await _createDialog(context, products: products);
                      if (form == null) return;
                      final id = await ref.read(inventoryRecipesProvider.notifier).upsert(
                            productId: form.productId,
                            code: form.code,
                            name: form.name,
                            description: form.description,
                            yieldQty: form.yieldQty,
                            yieldUnit: form.yieldUnit,
                            gimOran: form.gimOran,
                            lines: const [],
                          );
                      if (!context.mounted) return;
                      if (id != null && id.isNotEmpty) context.go('/inv/recipes/$id');
                    }
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('Yeni Reçete'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'Ara (ad/kod)',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
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
                for (final r in items)
                  ListTile(
                    onTap: () => context.go('/inv/recipes/${r.id}'),
                    title: Text(
                      [
                        if ((r.code ?? '').trim().isNotEmpty) r.code!,
                        r.name,
                      ].join(' • '),
                    ),
                    subtitle: Text(
                      [
                        r.productName,
                        '${r.linesCount} kalem',
                        '${r.yieldQty.toStringAsFixed(3)} ${r.yieldUnit}',
                      ].join(' • '),
                    ),
                    trailing: canEdit
                        ? Switch(
                            value: r.isActive,
                            onChanged: (_) => ref
                                .read(inventoryRecipesProvider.notifier)
                                .toggleActive(r.id),
                          )
                        : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<_RecipeCreateForm?> _createDialog(
    BuildContext context, {
    required List<InventoryProduct> products,
  }) async {
    InventoryProduct selectedProduct = products.first;
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final yieldQtyController = TextEditingController(text: '1');
    final yieldUnitController = TextEditingController(text: 'adet');
    final gimOranController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<_RecipeCreateForm>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Yeni Reçete'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedProduct.id,
                        items: [
                          for (final p in products)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text([p.code, p.name].whereType<String>().where((e) => e.isNotEmpty).join(' • ')),
                            ),
                        ],
                        onChanged: (v) {
                          final found =
                              products.where((p) => p.id == v).firstOrNull ?? products.first;
                          setState(() => selectedProduct = found);
                        },
                        decoration: const InputDecoration(labelText: 'Ürün Adı'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: codeController,
                              decoration: const InputDecoration(labelText: 'Ürün Kodu (opsiyonel)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: yieldUnitController,
                              decoration: const InputDecoration(labelText: 'Reçete Birimi'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: yieldQtyController,
                              decoration: const InputDecoration(labelText: 'Porsiyon Miktarı'),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) {
                                final raw = (v ?? '').trim().replaceAll(',', '.');
                                final n = double.tryParse(raw);
                                if (n == null || n <= 0) return 'Geçersiz miktar';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: gimOranController,
                              decoration: const InputDecoration(labelText: 'GİM Oranı (opsiyonel)'),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Reçete Adı (opsiyonel)'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: descController,
                        decoration: const InputDecoration(labelText: 'Reçete Açıklaması'),
                        maxLines: 2,
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
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.of(context).pop(
                      _RecipeCreateForm(
                        productId: selectedProduct.id,
                        code: codeController.text.trim(),
                        name: nameController.text.trim(),
                        description: descController.text.trim(),
                        yieldQty: double.parse(
                          yieldQtyController.text.trim().replaceAll(',', '.'),
                        ),
                        yieldUnit: yieldUnitController.text.trim().isEmpty
                            ? 'adet'
                            : yieldUnitController.text.trim(),
                        gimOran: double.tryParse(
                          gimOranController.text.trim().replaceAll(',', '.'),
                        ),
                      ),
                    );
                  },
                  child: const Text('Oluştur'),
                ),
              ],
            );
          },
        );
      },
    );

    codeController.dispose();
    nameController.dispose();
    descController.dispose();
    yieldQtyController.dispose();
    yieldUnitController.dispose();
    gimOranController.dispose();

    return result;
  }
}

class InventoryRecipeDetailPage extends ConsumerStatefulWidget {
  const InventoryRecipeDetailPage({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<InventoryRecipeDetailPage> createState() => _InventoryRecipeDetailPageState();
}

class _InventoryRecipeDetailPageState extends ConsumerState<InventoryRecipeDetailPage> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _yieldQtyController = TextEditingController();
  final _yieldUnitController = TextEditingController();
  final _gimOranController = TextEditingController();

  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, TextEditingController> _wasteControllers = {};

  String? _selectedProductId;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _yieldQtyController.dispose();
    _yieldUnitController.dispose();
    _gimOranController.dispose();
    for (final c in _qtyControllers.values) c.dispose();
    for (final c in _wasteControllers.values) c.dispose();
    _qtyControllers.clear();
    _wasteControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final products = ref.watch(inventoryProductsProvider).where((p) => p.isActive).toList();
    final detail = ref.watch(inventoryRecipeDetailProvider(widget.recipeId));

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

        _selectedProductId ??= h.productId;
        _codeController.text = (_codeController.text.isEmpty ? (h.code ?? '') : _codeController.text);
        _nameController.text = (_nameController.text.isEmpty ? h.name : _nameController.text);
        _descController.text = (_descController.text.isEmpty ? (h.description ?? '') : _descController.text);
        _yieldQtyController.text = (_yieldQtyController.text.isEmpty ? h.yieldQty.toString() : _yieldQtyController.text);
        _yieldUnitController.text = (_yieldUnitController.text.isEmpty ? h.yieldUnit : _yieldUnitController.text);
        _gimOranController.text = (_gimOranController.text.isEmpty ? (h.gimOran?.toString() ?? '') : _gimOranController.text);

        for (final l in data.lines) {
          _qtyControllers.putIfAbsent(
            l.ingredientProductId,
            () => TextEditingController(text: l.quantity.toString()),
          );
          _wasteControllers.putIfAbsent(
            l.ingredientProductId,
            () => TextEditingController(text: l.wasteRate.toString()),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text('Yeni Reçete', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                if (canEdit)
                  FilledButton(
                    onPressed: () async {
                      await _save(context, h, data.lines);
                    },
                    child: const Text('Kaydet'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _leftForm(context, canEdit: canEdit, products: products),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 7,
                      child: _rightPanel(context, data, canEdit: canEdit, products: products),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _leftForm(
    BuildContext context, {
    required bool canEdit,
    required List<InventoryProduct> products,
  }) {
    const labelBg = Color(0xFF9BB6D4);
    const border = Color(0xFF999999);

    Widget label(String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: labelBg,
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
    }

    Widget cell(Widget child) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: child,
      );
    }

    return Table(
      columnWidths: const {
        0: FixedColumnWidth(170),
        1: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: const TableBorder(
        top: BorderSide(color: border),
        left: BorderSide(color: border),
        right: BorderSide(color: border),
      ),
      children: [
        TableRow(
          children: [
            label('Ürün Adı'),
            cell(
              DropdownButtonFormField<String>(
                initialValue: _selectedProductId,
                items: [
                  for (final p in products)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text([p.code, p.name].whereType<String>().where((e) => e.isNotEmpty).join(' • ')),
                    ),
                ],
                onChanged: canEdit ? (v) => setState(() => _selectedProductId = v) : null,
                decoration: const InputDecoration(isDense: true),
              ),
            ),
          ],
        ),
        TableRow(
          children: [
            label('Porsiyon Miktarı'),
            cell(
              TextFormField(
                controller: _yieldQtyController,
                enabled: canEdit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(isDense: true),
              ),
            ),
          ],
        ),
        TableRow(
          children: [
            label('Reçete Maliyeti'),
            cell(
              Text(
                NumberFormat('#,##0.0000', 'tr_TR')
                    .format(ref.watch(inventoryRecipeDetailProvider(widget.recipeId)).asData?.value?.totals.recipeCost ?? 0),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        TableRow(
          children: [
            label('Reçete Açıklaması'),
            cell(
              TextFormField(
                controller: _descController,
                enabled: canEdit,
                maxLines: 2,
                decoration: const InputDecoration(isDense: true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rightPanel(
    BuildContext context,
    InventoryRecipeDetail data, {
    required bool canEdit,
    required List<InventoryProduct> products,
  }) {
    const headerBg = Color(0xFF9BB6D4);
    const border = Color(0xFF999999);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: headerBg,
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Ürün Kodu / Reçete Birimi',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (canEdit)
                OutlinedButton(
                  onPressed: () => ref.invalidate(inventoryRecipeDetailProvider(widget.recipeId)),
                  child: const Text('Hesapla'),
                ),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: border),
              right: BorderSide(color: border),
              bottom: BorderSide(color: border),
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _codeController,
                  enabled: canEdit,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Ürün Kodu',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _yieldUnitController,
                  enabled: canEdit,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Reçete Birimi',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _gimOranController,
                  enabled: canEdit,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'GİM Oranı',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            border: Border.all(color: border),
          ),
          child: _ingredientsTable(data, canEdit: canEdit, products: products),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Spacer(),
            if (canEdit)
              OutlinedButton(
                onPressed: products.isEmpty
                    ? null
                    : () async {
                        final pick = await _pickIngredient(context, products: products, existing: data.lines.map((e) => e.ingredientProductId).toSet());
                        if (pick == null) return;
                        setState(() {
                          _qtyControllers.putIfAbsent(
                            pick,
                            () => TextEditingController(text: '1'),
                          );
                          _wasteControllers.putIfAbsent(
                            pick,
                            () => TextEditingController(text: '0'),
                          );
                        });
                      },
                child: const Text('Kalem Ekle'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _ingredientsTable(
    InventoryRecipeDetail data, {
    required bool canEdit,
    required List<InventoryProduct> products,
  }) {
    double asDouble(TextEditingController? c) {
      final raw = (c?.text ?? '').trim().replaceAll(',', '.');
      return double.tryParse(raw) ?? 0;
    }

    final allLines = <InventoryRecipeLine>[
      ...data.lines,
      for (final id in _qtyControllers.keys)
        if (data.lines.every((l) => l.ingredientProductId != id))
          InventoryRecipeLine(
            ingredientProductId: id,
            ingredientProductName: products.where((p) => p.id == id).firstOrNull?.name ?? '?',
            unit: products.where((p) => p.id == id).firstOrNull?.unit ?? 'adet',
            quantity: 0,
            wasteRate: 0,
            avgUnitCost: 0,
            lineCost: 0,
          ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Malzeme')),
          DataColumn(label: Text('Birim')),
          DataColumn(label: Text('Miktar')),
          DataColumn(label: Text('Fire')),
          DataColumn(label: Text('Ort. Maliyet')),
          DataColumn(label: Text('Tutar')),
        ],
        rows: [
          for (var i = 0; i < allLines.length; i++)
            DataRow(
              color: WidgetStatePropertyAll(
                i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
              ),
              cells: [
                DataCell(Text(allLines[i].ingredientProductName)),
                DataCell(Text(allLines[i].unit)),
                DataCell(
                  SizedBox(
                    width: 90,
                    child: TextFormField(
                      enabled: canEdit,
                      controller: _qtyControllers.putIfAbsent(
                        allLines[i].ingredientProductId,
                        () => TextEditingController(text: allLines[i].quantity.toString()),
                      ),
                      decoration: const InputDecoration(isDense: true),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 70,
                    child: TextFormField(
                      enabled: canEdit,
                      controller: _wasteControllers.putIfAbsent(
                        allLines[i].ingredientProductId,
                        () => TextEditingController(text: allLines[i].wasteRate.toString()),
                      ),
                      decoration: const InputDecoration(isDense: true),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ),
                DataCell(Text(allLines[i].avgUnitCost.toStringAsFixed(4))),
                DataCell(
                  Text(
                    allLines[i].ingredientProductId.isNotEmpty
                        ? (allLines[i].lineCost).toStringAsFixed(4)
                        : '0.0000',
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    InventoryRecipe header,
    List<InventoryRecipeLine> existingLines,
  ) async {
    if (_selectedProductId == null) return;
    final yieldQty = double.tryParse(_yieldQtyController.text.trim().replaceAll(',', '.')) ?? 1;
    final gimOran = double.tryParse(_gimOranController.text.trim().replaceAll(',', '.'));

    final lineIds = _qtyControllers.keys.toSet().union(existingLines.map((e) => e.ingredientProductId).toSet());
    final payload = <({String ingredientProductId, double quantity, String? unit, double? wasteRate})>[];
    for (final id in lineIds) {
      final qty = double.tryParse((_qtyControllers[id]?.text ?? '').trim().replaceAll(',', '.')) ?? 0;
      if (qty <= 0) continue;
      final waste = double.tryParse((_wasteControllers[id]?.text ?? '').trim().replaceAll(',', '.'));
      payload.add(
        (ingredientProductId: id, quantity: qty, unit: null, wasteRate: waste),
      );
    }

    final id = await ref.read(inventoryRecipesProvider.notifier).upsert(
          productId: _selectedProductId!,
          code: _codeController.text.trim(),
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          yieldQty: yieldQty,
          yieldUnit: _yieldUnitController.text.trim().isEmpty ? 'adet' : _yieldUnitController.text.trim(),
          gimOran: gimOran,
          lines: payload,
        );

    if (!context.mounted) return;
    if (id != null && id.isNotEmpty && id != widget.recipeId) {
      context.go('/inv/recipes/$id');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedildi.')),
      );
    }
  }

  Future<String?> _pickIngredient(
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
                .take(200)
                .toList();
            selected ??= filtered.isNotEmpty ? filtered.first : null;

            return AlertDialog(
              title: const Text('Malzeme Seç'),
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
                            child: Text([p.code, p.name].whereType<String>().where((e) => e.isNotEmpty).join(' • ')),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        selected = filtered.where((p) => p.id == v).firstOrNull;
                      }),
                      decoration: const InputDecoration(labelText: 'Malzeme'),
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
}

class _RecipeCreateForm {
  const _RecipeCreateForm({
    required this.productId,
    required this.yieldQty,
    required this.yieldUnit,
    this.code,
    this.name,
    this.description,
    this.gimOran,
  });

  final String productId;
  final String? code;
  final String? name;
  final String? description;
  final double yieldQty;
  final String yieldUnit;
  final double? gimOran;
}

extension _FirstOrNullRecipeX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
