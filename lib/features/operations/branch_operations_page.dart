import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/api_client.dart';
import '../../app/config.dart';
import '../../domain/models.dart';
import '../../domain/stores.dart';

final branchOperationSummariesProvider =
    FutureProvider.family<List<BranchOperationSummary>, DateTime>((
      ref,
      businessDate,
    ) async {
      final branches = ref
          .watch(branchesProvider)
          .where((e) => e.isActive)
          .toList();
      final dataSources = ref.watch(branchDataSourcesProvider);
      final reconciliations = ref.watch(reconciliationsProvider);
      final posStatuses = await ref
          .watch(posPullStatusesProvider.future)
          .catchError((_) => <PosPullStatus>[]);

      final dataSourceByBranch = {for (final s in dataSources) s.branchId: s};
      final posByBranch = {for (final s in posStatuses) s.branchId: s};
      final dayKey = DateTime(
        businessDate.year,
        businessDate.month,
        businessDate.day,
      );

      final dio = AppConfig.hasApi ? ref.read(dioProvider) : null;
      final summaries = <BranchOperationSummary>[];
      for (final branch in branches) {
        final rec = reconciliations.where((r) {
          final d = DateTime(r.date.year, r.date.month, r.date.day);
          return r.branchId == branch.id && d == dayKey;
        }).firstOrNull;

        var invoiceCount = 0;
        var warehouseCount = 0;
        var onHandCount = 0;
        if (dio != null) {
          final counts = await _loadOperationalCounts(dio, branch.id);
          invoiceCount = counts.invoices;
          warehouseCount = counts.warehouses;
          onHandCount = counts.onHandLines;
        }

        summaries.add(
          BranchOperationSummary(
            branch: branch,
            dataSource: dataSourceByBranch[branch.id],
            posStatus: posByBranch[branch.id],
            todayReconciliation: rec,
            invoiceCount: invoiceCount,
            warehouseCount: warehouseCount,
            onHandCount: onHandCount,
          ),
        );
      }
      return summaries;
    });

Future<({int invoices, int warehouses, int onHandLines})>
_loadOperationalCounts(Dio dio, String branchId) async {
  Future<int> countList(String path, [Map<String, dynamic>? query]) async {
    try {
      final res = await dio.get<List<dynamic>>(
        path,
        queryParameters: {'branchId': branchId, ...?query},
      );
      return (res.data ?? const []).length;
    } on DioException {
      return 0;
    }
  }

  final invoices = await countList('/inv/invoices');
  final warehouses = await countList('/inv/warehouses');
  final onHandLines = await countList('/inv/stock-on-hand');
  return (invoices: invoices, warehouses: warehouses, onHandLines: onHandLines);
}

class BranchOperationSummary {
  const BranchOperationSummary({
    required this.branch,
    required this.dataSource,
    required this.posStatus,
    required this.todayReconciliation,
    required this.invoiceCount,
    required this.warehouseCount,
    required this.onHandCount,
  });

  final Branch branch;
  final BranchDataSource? dataSource;
  final PosPullStatus? posStatus;
  final CashReconciliation? todayReconciliation;
  final int invoiceCount;
  final int warehouseCount;
  final int onHandCount;

  bool get hasActiveConnection => dataSource?.isActive == true;
  bool get hasTodayCash => todayReconciliation != null;
}

class BranchOperationsPage extends ConsumerStatefulWidget {
  const BranchOperationsPage({super.key});

  @override
  ConsumerState<BranchOperationsPage> createState() =>
      _BranchOperationsPageState();
}

class _BranchOperationsPageState extends ConsumerState<BranchOperationsPage> {
  DateTime _businessDate = DateTime.now();
  var _pullingBranchId = '';

  @override
  Widget build(BuildContext context) {
    final day = DateTime(
      _businessDate.year,
      _businessDate.month,
      _businessDate.day,
    );
    final summariesAsync = ref.watch(branchOperationSummariesProvider(day));
    final dayLabel = DateFormat('yyyy-MM-dd', 'tr_TR').format(day);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text(
                'Şube Operasyonları',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(dayLabel),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  ref.invalidate(branchOperationSummariesProvider(day));
                  ref.invalidate(posPullStatusesProvider);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Yenile'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _OperationIntro(dateLabel: dayLabel),
          const SizedBox(height: 12),
          summariesAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aktif şube bulunamadı.'),
                  ),
                );
              }
              return Column(
                children: [
                  for (final item in items) ...[
                    _BranchOperationCard(
                      item: item,
                      dateLabel: dayLabel,
                      isPulling: _pullingBranchId == item.branch.id,
                      onPullPos: () => _pullPos(item.branch),
                      onCash: () => context.go(
                        '/reconciliations?branchId=${item.branch.id}',
                      ),
                      onInvoices: () => context.go('/inv/invoices'),
                      onStock: () => context.go('/inv/onhand'),
                      onCost: () => context.go('/legacy/ps_cost_analysis'),
                      onBranchSettings: () => context.go('/crm/branches'),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Operasyon özeti alınamadı: $e'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _businessDate,
    );
    if (picked == null) return;
    setState(
      () => _businessDate = DateTime(picked.year, picked.month, picked.day),
    );
  }

  Future<void> _pullPos(Branch branch) async {
    if (!AppConfig.hasApi) return;
    if (_pullingBranchId.isNotEmpty) return;
    final day = DateTime(
      _businessDate.year,
      _businessDate.month,
      _businessDate.day,
    );
    final dayStr = DateFormat('yyyy-MM-dd', 'tr_TR').format(day);
    setState(() => _pullingBranchId = branch.id);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post<Map<String, dynamic>>(
        '/pos/pull/branch-daily',
        data: {
          'branchId': branch.id,
          'businessDate': dayStr,
          'businessDayStartHour': branch.businessDayStartHour,
          'summaryOnly': true,
        },
      );
      ref.invalidate(posPullStatusesProvider);
      ref.invalidate(branchOperationSummariesProvider(day));
      await ref.read(reconciliationsProvider.notifier).refresh();
      final total = res.data?['dailyTotal']?.toString() ?? '0';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${branch.name} POS çekimi tamamlandı. Ciro: $total'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${branch.name} POS çekimi başarısız: $e')),
      );
    } finally {
      if (mounted) setState(() => _pullingBranchId = '');
    }
  }
}

class _OperationIntro extends StatelessWidget {
  const _OperationIntro({required this.dateLabel});

  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(child: Icon(Icons.hub_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Şube merkezli yönetim',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$dateLabel için POS çekimi, kasa icmal, alım faturası, stok ve maliyet adımlarını şube bazında yönetin.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchOperationCard extends StatelessWidget {
  const _BranchOperationCard({
    required this.item,
    required this.dateLabel,
    required this.isPulling,
    required this.onPullPos,
    required this.onCash,
    required this.onInvoices,
    required this.onStock,
    required this.onCost,
    required this.onBranchSettings,
  });

  final BranchOperationSummary item;
  final String dateLabel;
  final bool isPulling;
  final VoidCallback onPullPos;
  final VoidCallback onCash;
  final VoidCallback onInvoices;
  final VoidCallback onStock;
  final VoidCallback onCost;
  final VoidCallback onBranchSettings;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final recon = item.todayReconciliation;
    final statusLabel = recon == null
        ? 'Kasa kaydı yok'
        : _statusLabel(recon.status);
    final lastPull = item.posStatus?.lastPulledAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  item.hasActiveConnection
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.branch.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        item.hasActiveConnection
                            ? '${item.dataSource!.host}:${item.dataSource!.port}/${item.dataSource!.database}'
                            : 'Şube POS/veri kaynağı bağlantısı yok',
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  label: statusLabel,
                  color: recon == null
                      ? Colors.orange.shade800
                      : Colors.green.shade700,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MiniMetric(
                  title: 'Son POS Çekimi',
                  value: lastPull == null
                      ? '-'
                      : DateFormat(
                          'yyyy-MM-dd HH:mm',
                          'tr_TR',
                        ).format(lastPull),
                ),
                _MiniMetric(
                  title: 'Günlük Ciro',
                  value: money.format(recon?.expectedSalesTotal ?? 0),
                ),
                _MiniMetric(
                  title: 'Alım Faturası',
                  value: item.invoiceCount.toString(),
                ),
                _MiniMetric(
                  title: 'Depo',
                  value: item.warehouseCount.toString(),
                ),
                _MiniMetric(
                  title: 'Stok Satırı',
                  value: item.onHandCount.toString(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: item.hasActiveConnection && !isPulling
                      ? onPullPos
                      : null,
                  icon: isPulling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(isPulling ? 'Çekiliyor' : 'POS Çek'),
                ),
                OutlinedButton.icon(
                  onPressed: onCash,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Kasa İcmal'),
                ),
                OutlinedButton.icon(
                  onPressed: onInvoices,
                  icon: const Icon(Icons.request_quote_outlined),
                  label: const Text('Alım Faturaları'),
                ),
                OutlinedButton.icon(
                  onPressed: onStock,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Stok'),
                ),
                OutlinedButton.icon(
                  onPressed: onCost,
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Maliyet'),
                ),
                TextButton.icon(
                  onPressed: onBranchSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Şube Ayarı'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(ReconciliationStatus status) {
    return switch (status) {
      ReconciliationStatus.draft => 'Taslak',
      ReconciliationStatus.submitted => 'Onay bekliyor',
      ReconciliationStatus.approved => 'Onaylandı',
      ReconciliationStatus.rejected => 'Reddedildi',
    };
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: InputDecorator(
        decoration: InputDecoration(labelText: title),
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color),
    );
  }
}
