import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class PurchaseOrdersPage extends ConsumerStatefulWidget {
  const PurchaseOrdersPage({super.key});

  @override
  ConsumerState<PurchaseOrdersPage> createState() => _PurchaseOrdersPageState();
}

class _PurchaseOrdersPageState extends ConsumerState<PurchaseOrdersPage> {
  String? _selectedBranchId;
  String _mode = 'orders';
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final branches = ref
        .watch(branchesProvider)
        .where((e) => e.isActive)
        .toList();
    _selectedBranchId ??=
        session?.branchId ?? (branches.isNotEmpty ? branches.first.id : null);

    final selectedBranchId = _selectedBranchId;
    final ordersAsync = selectedBranchId == null
        ? const AsyncValue<List<InventoryOpenDocument>>.data([])
        : ref.watch(inventoryOpenPurchaseOrdersProvider(selectedBranchId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PurchaseToolbar(
          title: 'Satınalma Sipariş Yönetimi',
          subtitle: 'Talep, teklif, sipariş ve sipariş formu arama akışı',
          actions: [
            OutlinedButton.icon(
              onPressed: selectedBranchId == null
                  ? null
                  : () => ref.invalidate(
                      inventoryOpenPurchaseOrdersProvider(selectedBranchId),
                    ),
              icon: const Icon(Icons.refresh),
              label: const Text('Yenile'),
            ),
            FilledButton.icon(
              onPressed: () => context.go('/inv/transactions'),
              icon: const Icon(Icons.add),
              label: const Text('Yeni Sipariş'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PurchaseFilterPanel(
          branches: branches,
          selectedBranchId: _selectedBranchId,
          role: role,
          mode: _mode,
          queryController: _queryController,
          onBranchChanged: (value) => setState(() => _selectedBranchId = value),
          onModeChanged: (value) => setState(() => _mode = value),
          onQueryChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        ordersAsync.when(
          data: (items) {
            final filtered = _filter(items);
            final total = filtered.fold<double>(
              0,
              (sum, item) => sum + (item.total ?? 0),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _PurchaseMetric(
                      label: 'Kayıt',
                      value: filtered.length.toString(),
                      icon: Icons.list_alt_outlined,
                    ),
                    _PurchaseMetric(
                      label: 'Toplam',
                      value: total.toStringAsFixed(2),
                      icon: Icons.payments_outlined,
                    ),
                    _PurchaseMetric(
                      label: 'Akış',
                      value: _modeLabel(_mode),
                      icon: Icons.account_tree_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _PurchaseOrdersTable(items: filtered),
              ],
            );
          },
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, st) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Siparişler yüklenemedi: $e'),
            ),
          ),
        ),
      ],
    );
  }

  List<InventoryOpenDocument> _filter(List<InventoryOpenDocument> items) {
    final query = _queryController.text.trim().toLowerCase();
    return [
      for (final item in items)
        if ((_mode == 'all' || _kindMatchesMode(item.kind)) &&
            (query.isEmpty ||
                item.docNo.toLowerCase().contains(query) ||
                (item.vendorName ?? '').toLowerCase().contains(query)))
          item,
    ];
  }

  bool _kindMatchesMode(String? kind) {
    final k = (kind ?? '').toLowerCase();
    return switch (_mode) {
      'requests' => k == 'purchase_request',
      'quotes' => k == 'purchase_quote',
      'orders' => k == 'purchase_order' || k.isEmpty,
      _ => true,
    };
  }
}

class _PurchaseToolbar extends StatelessWidget {
  const _PurchaseToolbar({
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
              child: const Icon(Icons.shopping_cart_outlined),
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

class _PurchaseFilterPanel extends StatelessWidget {
  const _PurchaseFilterPanel({
    required this.branches,
    required this.selectedBranchId,
    required this.role,
    required this.mode,
    required this.queryController,
    required this.onBranchChanged,
    required this.onModeChanged,
    required this.onQueryChanged,
  });

  final List<Branch> branches;
  final String? selectedBranchId;
  final UserRole role;
  final String mode;
  final TextEditingController queryController;
  final ValueChanged<String?> onBranchChanged;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<String>(
                initialValue: selectedBranchId,
                decoration: const InputDecoration(labelText: 'Şube'),
                items: [
                  for (final b in branches)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: role == UserRole.branchUser ? null : onBranchChanged,
              ),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'orders',
                  label: Text('Sipariş'),
                  icon: Icon(Icons.shopping_cart_checkout_outlined),
                ),
                ButtonSegment(
                  value: 'requests',
                  label: Text('Talep'),
                  icon: Icon(Icons.assignment_outlined),
                ),
                ButtonSegment(
                  value: 'quotes',
                  label: Text('Teklif'),
                  icon: Icon(Icons.request_quote_outlined),
                ),
                ButtonSegment(
                  value: 'all',
                  label: Text('Tümü'),
                  icon: Icon(Icons.list_outlined),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (value) => onModeChanged(value.first),
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: queryController,
                decoration: const InputDecoration(
                  labelText: 'Sipariş no / tedarikçi ara',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => onQueryChanged(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseMetric extends StatelessWidget {
  const _PurchaseMetric({
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

class _PurchaseOrdersTable extends StatelessWidget {
  const _PurchaseOrdersTable({required this.items});

  final List<InventoryOpenDocument> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Arama kriterlerine uygun satınalma kaydı bulunamadı.'),
        ),
      );
    }

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.primaryContainer,
          ),
          columns: const [
            DataColumn(label: Text('Belge Tipi')),
            DataColumn(label: Text('Sipariş No')),
            DataColumn(label: Text('Tarih')),
            DataColumn(label: Text('Tedarikçi / Açıklama')),
            DataColumn(label: Text('Kalem')),
            DataColumn(label: Text('Tutar')),
            DataColumn(label: Text('Durum')),
          ],
          rows: [
            for (var i = 0; i < items.length; i++)
              DataRow(
                color: WidgetStatePropertyAll(
                  i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
                ),
                cells: [
                  DataCell(Text(_kindLabel(items[i].kind))),
                  DataCell(Text(items[i].docNo)),
                  DataCell(Text(_dateText(items[i].docDate))),
                  DataCell(Text(items[i].vendorName ?? '')),
                  DataCell(Text((items[i].linesCount ?? 0).toString())),
                  DataCell(Text((items[i].total ?? 0).toStringAsFixed(2))),
                  const DataCell(
                    Chip(
                      label: Text('Açık'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _modeLabel(String mode) {
  return switch (mode) {
    'requests' => 'Satınalma Talep',
    'quotes' => 'Satınalma Teklif',
    'all' => 'Tüm Kayıtlar',
    _ => 'Satınalma Sipariş',
  };
}

String _kindLabel(String? kind) {
  return switch ((kind ?? '').toLowerCase()) {
    'purchase_request' => 'Talep',
    'purchase_quote' => 'Teklif',
    _ => 'Sipariş',
  };
}

String _dateText(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  return '$day.$month.${d.year}';
}
