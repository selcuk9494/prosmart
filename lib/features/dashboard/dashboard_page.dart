import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  DateTime? _fromDate;
  DateTime? _toDate;

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    final today = _dayOnly(DateTime.now());
    _fromDate = today.subtract(const Duration(days: 13));
    _toDate = today;
  }

  DateTime _weekStart(DateTime d) {
    final wd = d.weekday;
    return d.subtract(Duration(days: wd - DateTime.monday));
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _monthEnd(DateTime d) => DateTime(d.year, d.month + 1, 0);

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _pickFromDate() async {
    final current = _fromDate ?? _dayOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: current,
    );
    if (picked == null) return;
    setState(() {
      _fromDate = _dayOnly(picked);
      if (_toDate == null || _toDate!.isBefore(_fromDate!)) {
        _toDate = _fromDate;
      }
    });
  }

  Future<void> _pickToDate() async {
    final current = _toDate ?? _dayOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: current,
    );
    if (picked == null) return;
    setState(() {
      _toDate = _dayOnly(picked);
      if (_fromDate == null || _fromDate!.isAfter(_toDate!)) {
        _fromDate = _toDate;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingApprovalsCountProvider);
    final mismatches = ref.watch(mismatchesCountProvider);
    final branches = ref.watch(branchesProvider).where((e) => e.isActive).toList();
    final allRecs = ref.watch(reconciliationsProvider);
    final recent = allRecs.take(6).toList();
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    final today = _dayOnly(DateTime.now());
    final from = _fromDate ?? today.subtract(const Duration(days: 13));
    final to = _toDate ?? today;
    final window = allRecs.where((r) {
      final d = _dayOnly(r.date);
      return !d.isBefore(from) && !d.isAfter(to);
    }).toList();

    final statusCounts = <ReconciliationStatus, int>{
      ReconciliationStatus.draft: 0,
      ReconciliationStatus.submitted: 0,
      ReconciliationStatus.approved: 0,
      ReconciliationStatus.rejected: 0,
    };
    for (final r in window) {
      statusCounts[r.status] = (statusCounts[r.status] ?? 0) + 1;
    }

    final okCount = window
        .where((r) => r.status != ReconciliationStatus.draft && r.difference.abs() <= 0.01)
        .length;
    final mismatchCount = window
        .where((r) => r.status != ReconciliationStatus.draft && r.difference.abs() > 0.01)
        .length;
    final missingDocsCount = window
        .where((r) => r.status != ReconciliationStatus.draft && missingRequiredAttachmentKinds(r).isNotEmpty)
        .length;

    final statusSegments = <_DonutSegment>[
      _DonutSegment(
        label: 'Taslak',
        value: (statusCounts[ReconciliationStatus.draft] ?? 0).toDouble(),
        color: Theme.of(context).colorScheme.outline,
      ),
      _DonutSegment(
        label: 'Onay Bekliyor',
        value: (statusCounts[ReconciliationStatus.submitted] ?? 0).toDouble(),
        color: Colors.orange.shade700,
      ),
      _DonutSegment(
        label: 'Onaylandı',
        value: (statusCounts[ReconciliationStatus.approved] ?? 0).toDouble(),
        color: Colors.green.shade700,
      ),
      _DonutSegment(
        label: 'Reddedildi',
        value: (statusCounts[ReconciliationStatus.rejected] ?? 0).toDouble(),
        color: Theme.of(context).colorScheme.error,
      ),
    ];

    final qualitySegments = <_DonutSegment>[
      _DonutSegment(
        label: 'Sorunsuz',
        value: okCount.toDouble(),
        color: Colors.green.shade700,
      ),
      _DonutSegment(
        label: 'Fark Var',
        value: mismatchCount.toDouble(),
        color: Theme.of(context).colorScheme.error,
      ),
      _DonutSegment(
        label: 'Evrak Eksik',
        value: missingDocsCount.toDouble(),
        color: Colors.orange.shade800,
      ),
    ];

    final days = <DateTime>[];
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    final salesSeries = <DateTime, double>{
      for (final d in days) d: 0,
    };
    for (final r in window) {
      final d = _dayOnly(r.date);
      salesSeries[d] = (salesSeries[d] ?? 0) + r.expectedSalesTotal;
    }

    final branchSales = <String, double>{};
    for (final r in window) {
      branchSales[r.branchId] = (branchSales[r.branchId] ?? 0) + r.expectedSalesTotal;
    }
    final branchNameById = {for (final b in branches) b.id: b.name};
    final branchSalesSorted = branchSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final palette = [
      Colors.blue.shade700,
      Colors.green.shade700,
      Colors.orange.shade700,
      Colors.purple.shade700,
      Colors.teal.shade700,
      Colors.indigo.shade700,
      Colors.red.shade700,
      Colors.brown.shade700,
    ];
    final branchSegments = <_DonutSegment>[];
    var otherTotal = 0.0;
    for (var i = 0; i < branchSalesSorted.length; i++) {
      final e = branchSalesSorted[i];
      final name = branchNameById[e.key] ?? '?';
      if (i < 8) {
        branchSegments.add(_DonutSegment(label: name, value: e.value, color: palette[i % palette.length]));
      } else {
        otherTotal += e.value;
      }
    }
    if (otherTotal > 0) {
      branchSegments.add(_DonutSegment(label: 'Diğer', value: otherTotal, color: Theme.of(context).colorScheme.outline));
    }

    final isSingleDay = _sameDay(from, to);
    final missingBranches = <Branch>[];
    final draftBranches = <Branch>[];
    if (isSingleDay) {
      for (final b in branches) {
        CashReconciliation? rec;
        for (final r in allRecs) {
          if (r.branchId == b.id && _sameDay(_dayOnly(r.date), from)) {
            rec = r;
            break;
          }
        }
        if (rec == null) {
          missingBranches.add(b);
        } else if (rec.status == ReconciliationStatus.draft) {
          draftBranches.add(b);
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Tarih', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _fromDate = today.subtract(const Duration(days: 13));
                          _toDate = today;
                        });
                      },
                      child: const Text('Sıfırla'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Bugün'),
                      selected: _fromDate != null && _toDate != null && _sameDay(_fromDate!, today) && _sameDay(_toDate!, today),
                      onSelected: (_) => setState(() {
                        _fromDate = today;
                        _toDate = today;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('Dün'),
                      selected: _fromDate != null &&
                          _toDate != null &&
                          _sameDay(_fromDate!, today.subtract(const Duration(days: 1))) &&
                          _sameDay(_toDate!, today.subtract(const Duration(days: 1))),
                      onSelected: (_) => setState(() {
                        final d = today.subtract(const Duration(days: 1));
                        _fromDate = d;
                        _toDate = d;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('Bu hafta'),
                      selected: _fromDate != null && _toDate != null && _sameDay(_fromDate!, _weekStart(today)) && _sameDay(_toDate!, today),
                      onSelected: (_) => setState(() {
                        _fromDate = _weekStart(today);
                        _toDate = today;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('Son 7 gün'),
                      selected: _fromDate != null &&
                          _toDate != null &&
                          _sameDay(_fromDate!, today.subtract(const Duration(days: 6))) &&
                          _sameDay(_toDate!, today),
                      onSelected: (_) => setState(() {
                        _fromDate = today.subtract(const Duration(days: 6));
                        _toDate = today;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('Bu ay'),
                      selected: _fromDate != null && _toDate != null && _sameDay(_fromDate!, _monthStart(today)) && _sameDay(_toDate!, today),
                      onSelected: (_) => setState(() {
                        _fromDate = _monthStart(today);
                        _toDate = today;
                      }),
                    ),
                    ChoiceChip(
                      label: const Text('Geçen ay'),
                      selected: () {
                        if (_fromDate == null || _toDate == null) return false;
                        final lastMonth = DateTime(today.year, today.month - 1, 1);
                        return _sameDay(_fromDate!, _monthStart(lastMonth)) && _sameDay(_toDate!, _monthEnd(lastMonth));
                      }(),
                      onSelected: (_) => setState(() {
                        final lastMonth = DateTime(today.year, today.month - 1, 1);
                        _fromDate = _monthStart(lastMonth);
                        _toDate = _monthEnd(lastMonth);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 260,
                      child: OutlinedButton(
                        onPressed: _pickFromDate,
                        child: Text('Başlangıç: ${DateFormat('yyyy-MM-dd', 'tr_TR').format(from)}'),
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: OutlinedButton(
                        onPressed: _pickToDate,
                        child: Text('Bitiş: ${DateFormat('yyyy-MM-dd', 'tr_TR').format(to)}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _KpiCard(
              title: 'Onay Bekleyen',
              value: pending.toString(),
              icon: Icons.verified_outlined,
              color: Colors.orange,
              onTap: pending == 0 ? null : () => context.go('/reconciliations'),
            ),
            _KpiCard(
              title: 'Farklılık Olan',
              value: mismatches.toString(),
              icon: Icons.warning_amber,
              color: Colors.red,
              onTap: mismatches == 0 ? null : () => context.go('/reconciliations'),
            ),
            _TodaySalesCard(branches: branches),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Akış Özeti (${DateFormat('yyyy-MM-dd', 'tr_TR').format(from)} → ${DateFormat('yyyy-MM-dd', 'tr_TR').format(to)})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final isWide = c.maxWidth >= 1100;
            final charts = [
              Expanded(
                child: _ChartCard(
                  title: 'Durum Dağılımı',
                  subtitle: 'Taslak / Onay Bekliyor / Onaylandı / Reddedildi',
                  child: _DonutWithLegend(segments: statusSegments),
                ),
              ),
              const SizedBox(width: 12, height: 12),
              Expanded(
                child: _ChartCard(
                  title: 'Kalite',
                  subtitle: 'Sorunsuz / Fark Var / Evrak Eksik',
                  child: _DonutWithLegend(segments: qualitySegments),
                ),
              ),
              const SizedBox(width: 12, height: 12),
              Expanded(
                child: _ChartCard(
                  title: 'Günlük Ciro (Toplam)',
                  subtitle: 'Seçili tarih aralığında gün gün toplam ciro. Her çubuk = o günün tüm şubeler toplamı.',
                  child: _BarChart(
                    series: [
                      for (final e in salesSeries.entries) _BarPoint(date: e.key, value: e.value),
                    ],
                  ),
                ),
              ),
            ];

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: charts,
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChartCard(
                  title: 'Durum Dağılımı',
                  subtitle: 'Taslak / Onay Bekliyor / Onaylandı / Reddedildi',
                  child: _DonutWithLegend(segments: statusSegments),
                ),
                const SizedBox(height: 12),
                _ChartCard(
                  title: 'Kalite',
                  subtitle: 'Sorunsuz / Fark Var / Evrak Eksik',
                  child: _DonutWithLegend(segments: qualitySegments),
                ),
                const SizedBox(height: 12),
                _ChartCard(
                  title: 'Günlük Ciro (Toplam)',
                  subtitle: 'Seçili tarih aralığında gün gün toplam ciro. Her çubuk = o günün tüm şubeler toplamı.',
                  child: _BarChart(
                    series: [
                      for (final e in salesSeries.entries) _BarPoint(date: e.key, value: e.value),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _ChartCard(
          title: 'Şube Ciro Dağılımı',
          subtitle: 'Seçili tarihlerde şube bazlı ciro',
          child: branchSegments.isEmpty
              ? const Center(child: Text('Veri yok.'))
              : _DonutWithLegend(
                  segments: branchSegments,
                  valueFormatter: (v) => money.format(v),
                  centerLabel: 'Toplam',
                ),
        ),
        if (isSingleDay) ...[
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Eksik İcmal',
            subtitle: 'Seçili gün için icmali olmayan / taslak kalan şubeler',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Chip(label: Text('Eksik: ${missingBranches.length}')),
                    const SizedBox(width: 8),
                    Chip(label: Text('Taslak: ${draftBranches.length}')),
                  ],
                ),
                const SizedBox(height: 8),
                if (missingBranches.isEmpty && draftBranches.isEmpty)
                  const Text('Hepsi tamam.'),
                if (missingBranches.isNotEmpty) ...[
                  Text('İcmali yok', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in missingBranches) Chip(label: Text(b.name)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (draftBranches.isNotEmpty) ...[
                  Text('Taslak', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in draftBranches) Chip(label: Text(b.name)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Son Kasa İcmal', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            TextButton.icon(
              onPressed: () => context.go('/reconciliations'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Tümü'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Henüz kayıt yok. Kasa icmali oluşturarak başlayın.'),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final r in recent) _ReconciliationTile(item: r),
              ],
            ),
          ),
      ],
    );
  }
}

class _TodaySalesCard extends ConsumerWidget {
  const _TodaySalesCard({required this.branches});

  final List<Branch> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(salesRepositoryProvider);
    final today = DateTime.now();

    return FutureBuilder<double>(
      future: () async {
        var total = 0.0;
        for (final b in branches) {
          total += await repo.getDailySales(branchId: b.id, date: today);
        }
        return total;
      }(),
      builder: (context, snapshot) {
        final value = snapshot.hasData
            ? NumberFormat.currency(locale: 'tr_TR', symbol: '₺')
                .format(snapshot.data)
            : '...';
        return _KpiCard(
          title: 'Bugün Toplam Ciro',
          value: value,
          icon: Icons.trending_up,
          color: Colors.blue,
          onTap: null,
        );
      },
    );
  }
}

class _ReconciliationTile extends ConsumerWidget {
  const _ReconciliationTile({required this.item});

  final CashReconciliation item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchesProvider);
    final branchName =
        branches.firstWhere((b) => b.id == item.branchId, orElse: () => const Branch(id: 'x', name: '?')).name;

    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final date = DateFormat('yyyy-MM-dd', 'tr_TR').format(item.date);

    final diff = item.difference;
    final hasDiff = diff.abs() > 0.01 && item.status != ReconciliationStatus.draft;

    return ListTile(
      onTap: () => context.go('/reconciliations/${item.id}'),
      title: Text('$branchName • $date'),
      subtitle: Text(
        '${_statusLabel(item.status)} • Satış: ${money.format(item.expectedSalesTotal)} • Toplam: ${money.format(item.paymentTotal)}',
      ),
      trailing: hasDiff
          ? Chip(
              label: Text('Fark: ${money.format(diff)}'),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
            )
          : null,
    );
  }

  String _statusLabel(ReconciliationStatus status) {
    return switch (status) {
      ReconciliationStatus.draft => 'Taslak',
      ReconciliationStatus.submitted => 'Onay Bekliyor',
      ReconciliationStatus.approved => 'Onaylandı',
      ReconciliationStatus.rejected => 'Reddedildi',
    };
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  foregroundColor: color,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 6),
                      Text(
                        value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
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

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _DonutWithLegend extends StatelessWidget {
  const _DonutWithLegend({
    required this.segments,
    this.valueFormatter,
    this.centerLabel,
  });

  final List<_DonutSegment> segments;
  final String Function(double value)? valueFormatter;
  final String? centerLabel;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (p, e) => p + e.value);
    final shown = segments.where((e) => e.value > 0.0001).toList();
    final fmt = valueFormatter ?? (v) => v.toStringAsFixed(0);
    final label = centerLabel ?? 'Kayıt';

    return LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 520;
        final donut = SizedBox(
          width: 220,
          height: 220,
          child: _DonutChart(
            segments: shown,
            centerText: fmt(total),
            centerLabel: label,
          ),
        );

        final legend = Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final s in shown)
              _LegendChip(
                color: s.color,
                label: '${s.label}: ${fmt(s.value)}',
              ),
          ],
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              donut,
              const SizedBox(width: 16),
              Expanded(child: legend),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: donut),
            const SizedBox(height: 12),
            legend,
          ],
        );
      },
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _DonutSegment {
  const _DonutSegment({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({
    required this.segments,
    required this.centerText,
    required this.centerLabel,
  });

  final List<_DonutSegment> segments;
  final String centerText;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (p, e) => p + e.value);
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _DonutPainter(
        segments: segments,
        total: total,
        trackColor: scheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              centerText,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              centerLabel,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.total,
    required this.trackColor,
  });

  final List<_DonutSegment> segments;
  final double total;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final stroke = math.max(10.0, radius * 0.22);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, track);

    if (total <= 0.0001) return;
    var start = -math.pi / 2;
    for (final s in segments) {
      final sweep = (s.value / total) * math.pi * 2;
      if (sweep <= 0) continue;
      final p = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.total != total ||
        oldDelegate.segments != segments ||
        oldDelegate.trackColor != trackColor;
  }
}

class _BarPoint {
  const _BarPoint({required this.date, required this.value});
  final DateTime date;
  final double value;
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.series});

  final List<_BarPoint> series;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final maxValue = series.fold<double>(0, (p, e) => math.max(p, e.value));

    return SizedBox(
      height: 260,
      child: CustomPaint(
        painter: _BarChartPainter(
          series: series,
          maxValue: maxValue <= 0 ? 1 : maxValue,
          barColor: Theme.of(context).colorScheme.primary,
          gridColor: Theme.of(context).colorScheme.outlineVariant,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.topRight,
            child: Chip(
              label: Text('Max: ${money.format(maxValue)}'),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.series,
    required this.maxValue,
    required this.barColor,
    required this.gridColor,
  });

  final List<_BarPoint> series;
  final double maxValue;
  final Color barColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final left = 8.0;
    final top = 8.0;
    final right = size.width - 8.0;
    final bottom = size.height - 8.0;
    final width = right - left;
    final height = bottom - top;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      final y = top + (height * i / 4);
      canvas.drawLine(Offset(left, y), Offset(right, y), gridPaint);
    }

    if (series.isEmpty) return;
    final barCount = series.length;
    final gap = 4.0;
    final barWidth = (width - gap * (barCount - 1)) / barCount;

    for (var i = 0; i < barCount; i++) {
      final v = series[i].value;
      final h = (v / maxValue) * height;
      final x = left + i * (barWidth + gap);
      final y = bottom - h;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, h),
        const Radius.circular(6),
      );

      final fill = Paint()
        ..color = barColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rect, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) {
    return oldDelegate.series != series ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.barColor != barColor ||
        oldDelegate.gridColor != gridColor;
  }
}
