import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';

class AccountingOverviewPage extends ConsumerWidget {
  const AccountingOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final firms = ref.watch(crmFirmsProvider);
    final products = ref.watch(inventoryProductsProvider);
    final invoices = ref.watch(inventoryInvoicesProvider);
    final reconciliations = ref.watch(reconciliationsProvider);

    final invoiceTotal = invoices.fold<double>(
      0,
      (sum, item) => sum + (item.total ?? 0),
    );
    final openDiff = reconciliations
        .where((r) => r.status != ReconciliationStatus.approved)
        .fold<double>(0, (sum, r) => sum + r.difference.abs());
    final missingDocs = reconciliations
        .where((r) => missingRequiredAttachmentKinds(r).isNotEmpty)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Ön Muhasebe', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => context.go('/crm/firms/new'),
              icon: const Icon(Icons.person_add_alt_outlined),
              label: const Text('Cari Ekle'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => context.go('/inv/invoices'),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Fatura'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              title: 'Cari Kart',
              value: firms.length.toString(),
              icon: Icons.groups_outlined,
              tone: _MetricTone.blue,
              onTap: () => context.go('/crm/firms'),
            ),
            _MetricCard(
              title: 'Stok & Hizmet',
              value: products.length.toString(),
              icon: Icons.inventory_2_outlined,
              tone: _MetricTone.green,
              onTap: () => context.go('/inv/products'),
            ),
            _MetricCard(
              title: 'Alış Faturası',
              value: money.format(invoiceTotal),
              icon: Icons.request_quote_outlined,
              tone: _MetricTone.indigo,
              onTap: () => context.go('/inv/invoices'),
            ),
            _MetricCard(
              title: 'Açık Fark',
              value: money.format(openDiff),
              icon: Icons.warning_amber_outlined,
              tone: _MetricTone.red,
              onTap: () => context.go('/reconciliations'),
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
                Row(
                  children: [
                    const Icon(Icons.account_tree_outlined),
                    const SizedBox(width: 8),
                    Text(
                      'İş Akışı',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    if (missingDocs > 0)
                      Chip(label: Text('$missingDocs evrak eksik')),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ActionChip(
                      icon: Icons.people_outline,
                      label: 'Müşteri & Tedarikçi',
                      onTap: () => context.go('/crm/firms'),
                    ),
                    _ActionChip(
                      icon: Icons.shopping_bag_outlined,
                      label: 'Ürünler',
                      onTap: () => context.go('/inv/products'),
                    ),
                    _ActionChip(
                      icon: Icons.request_quote_outlined,
                      label: 'Alış Faturaları',
                      onTap: () => context.go('/inv/invoices'),
                    ),
                    _ActionChip(
                      icon: Icons.inventory_outlined,
                      label: 'Stok Hareketleri',
                      onTap: () => context.go('/inv/transactions'),
                    ),
                    _ActionChip(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Kasalar',
                      onTap: () => context.go('/crm/cash-registers'),
                    ),
                    _ActionChip(
                      icon: Icons.bar_chart_outlined,
                      label: 'Raporlar',
                      onTap: () => context.go('/reports/ana-grup-satis'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Son Alış Faturaları',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (invoices.isEmpty)
                  const Text('Kayıt yok.')
                else
                  DataTable(
                    columns: const [
                      DataColumn(label: Text('Tarih')),
                      DataColumn(label: Text('No')),
                      DataColumn(label: Text('Tedarikçi')),
                      DataColumn(label: Text('Tutar')),
                    ],
                    rows: [
                      for (final item in invoices.take(8))
                        DataRow(
                          cells: [
                            DataCell(
                              Text(
                                DateFormat(
                                  'yyyy-MM-dd',
                                  'tr_TR',
                                ).format(item.invoiceDate),
                              ),
                            ),
                            DataCell(Text(item.invoiceNo)),
                            DataCell(Text(item.vendorName ?? '')),
                            DataCell(Text(money.format(item.total ?? 0))),
                          ],
                          onSelectChanged: (_) =>
                              context.go('/inv/invoices/${item.id}'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _MetricTone { blue, green, indigo, red }

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final _MetricTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _MetricTone.blue => Colors.blue,
      _MetricTone.green => Colors.green,
      _MetricTone.indigo => Colors.indigo,
      _MetricTone.red => Colors.red,
    };
    return SizedBox(
      width: 260,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .12),
                  foregroundColor: color.shade700,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
