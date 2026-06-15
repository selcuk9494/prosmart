import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/api_client.dart';
import '../../app/config.dart';
import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  DateTime _businessDate = _dayOnly(DateTime.now());
  String? _branchId;
  var _syncingBranchId = '';
  var _approvingId = '';

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final branches = ref
        .watch(branchesProvider)
        .where((e) => e.isActive)
        .toList();
    final reconciliations = ref.watch(reconciliationsProvider);
    final dataSources = ref.watch(branchDataSourcesProvider);
    final posStatuses = ref.watch(posPullStatusesProvider);
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final dateLabel = DateFormat('yyyy-MM-dd', 'tr_TR').format(_businessDate);
    final dateQuery = 'from=$dateLabel&to=$dateLabel';

    final accessibleBranches = switch (role) {
      UserRole.branchUser =>
        branches.where((b) => b.id == session?.branchId).toList(),
      _ => branches,
    };
    final selectedBranches = _branchId == null
        ? accessibleBranches
        : accessibleBranches.where((b) => b.id == _branchId).toList();

    final dataSourceByBranch = {for (final d in dataSources) d.branchId: d};
    final posByBranch = {
      for (final p in posStatuses.asData?.value ?? const <PosPullStatus>[])
        p.branchId: p,
    };

    final rows = [
      for (final branch in selectedBranches)
        _CloseRow(
          branch: branch,
          dataSource: dataSourceByBranch[branch.id],
          posStatus: posByBranch[branch.id],
          reconciliation: reconciliations.where((r) {
            return r.branchId == branch.id &&
                _sameDay(_dayOnly(r.date), _businessDate);
          }).firstOrNull,
        ),
    ];

    final totalSales = rows.fold<double>(
      0,
      (sum, r) => sum + (r.reconciliation?.expectedSalesTotal ?? 0),
    );
    final missingReconciliation = rows
        .where((r) => r.reconciliation == null)
        .length;
    final needsAccounting = rows.where((r) => r.needsAccounting).length;
    final hasDifference = rows.where((r) => r.hasDifference).length;
    final waitingApproval = rows
        .where(
          (r) => r.reconciliation?.status == ReconciliationStatus.submitted,
        )
        .length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Toolbar(
          dateLabel: dateLabel,
          branches: accessibleBranches,
          selectedBranchId: _branchId,
          onPickDate: _pickDate,
          onToday: () =>
              setState(() => _businessDate = _dayOnly(DateTime.now())),
          onBranchChanged: role == UserRole.branchUser
              ? null
              : (value) => setState(() => _branchId = value),
          onRefresh: _refresh,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cardWidth = width >= 1100 ? (width - 48) / 5 : 220.0;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatCard(
                  width: cardWidth,
                  title: 'Eksik İcmal',
                  value: missingReconciliation.toString(),
                  icon: Icons.note_add_outlined,
                  color: Colors.orange.shade800,
                  onTap: missingReconciliation == 0
                      ? null
                      : () => context.go('/reconciliations?$dateQuery'),
                ),
                _StatCard(
                  width: cardWidth,
                  title: 'Muhasebe Bekliyor',
                  value: needsAccounting.toString(),
                  icon: Icons.payments_outlined,
                  color: Colors.blue.shade800,
                  onTap: needsAccounting == 0
                      ? null
                      : () => context.go('/reconciliations?$dateQuery'),
                ),
                _StatCard(
                  width: cardWidth,
                  title: 'Fark Var',
                  value: hasDifference.toString(),
                  icon: Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  onTap: hasDifference == 0
                      ? null
                      : () => context.go(
                          '/reconciliations?$dateQuery&onlyMismatched=1',
                        ),
                ),
                _StatCard(
                  width: cardWidth,
                  title: 'Onay Bekliyor',
                  value: waitingApproval.toString(),
                  icon: Icons.verified_outlined,
                  color: Colors.purple.shade700,
                  onTap: waitingApproval == 0
                      ? null
                      : () => context.go(
                          '/reconciliations?$dateQuery&status=submitted',
                        ),
                ),
                _StatCard(
                  width: cardWidth,
                  title: 'Ciro',
                  value: money.format(totalSales),
                  icon: Icons.trending_up,
                  color: Colors.green.shade700,
                  onTap: null,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Günlük Kapanış',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text('${rows.length} şube'),
                  ],
                ),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aktif şube bulunamadı.'),
                  )
                else
                  for (final row in rows) ...[
                    _BranchCloseTile(
                      row: row,
                      role: role,
                      money: money,
                      isSyncing: _syncingBranchId == row.branch.id,
                      isApproving: _approvingId == row.reconciliation?.id,
                      onSync: row.hasConnection && _syncingBranchId.isEmpty
                          ? () => _syncBranch(row.branch)
                          : null,
                      onOpen: row.reconciliation == null
                          ? null
                          : () => context.go(
                              '/reconciliations/${row.reconciliation!.id}',
                            ),
                      onCreateOrOpen: () => _createOrOpen(row),
                      onApprove:
                          role == UserRole.manager &&
                              row.reconciliation?.status ==
                                  ReconciliationStatus.submitted &&
                              _approvingId.isEmpty
                          ? () => _approve(row.reconciliation!)
                          : null,
                    ),
                    if (row != rows.last) const Divider(height: 1),
                  ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ApprovalFocusCard(
          rows: rows.where((r) {
            final rec = r.reconciliation;
            return rec != null &&
                (rec.status == ReconciliationStatus.submitted ||
                    r.hasDifference ||
                    r.missingDocs.isNotEmpty);
          }).toList(),
          money: money,
          onOpen: (id) => context.go('/reconciliations/$id'),
        ),
      ],
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
    setState(() => _businessDate = _dayOnly(picked));
  }

  Future<void> _refresh() async {
    ref.invalidate(posPullStatusesProvider);
    await ref.read(reconciliationsProvider.notifier).refresh();
    await ref.read(branchesProvider.notifier).refresh();
    await ref.read(branchDataSourcesProvider.notifier).refresh();
  }

  Future<CashReconciliation> _ensureReconciliation(Branch branch) async {
    final session = ref.read(authControllerProvider).asData?.value;
    if (session == null) throw StateError('Oturum bulunamadı');
    final existing = ref.read(reconciliationsProvider).where((r) {
      return r.branchId == branch.id &&
          _sameDay(_dayOnly(r.date), _businessDate);
    }).firstOrNull;
    if (existing != null) return existing;
    return ref
        .read(reconciliationsProvider.notifier)
        .createDraft(
          branchId: branch.id,
          date: _businessDate,
          userId: session.userId,
        );
  }

  Future<void> _syncBranch(Branch branch) async {
    if (!AppConfig.hasApi) return;
    if (_syncingBranchId.isNotEmpty) return;
    setState(() => _syncingBranchId = branch.id);
    final dayStr = DateFormat('yyyy-MM-dd', 'tr_TR').format(_businessDate);
    try {
      final rec = await _ensureReconciliation(branch);
      final dio = ref.read(dioProvider);
      final pullRes = await dio.post<Map<String, dynamic>>(
        '/pos/pull/branch-daily',
        data: {
          'branchId': branch.id,
          'businessDate': dayStr,
          'businessDayStartHour': branch.businessDayStartHour,
          'summaryOnly': true,
        },
      );
      final totalSales = _numToDouble(pullRes.data?['dailyTotal']);
      await ref
          .read(reconciliationsProvider.notifier)
          .updateExpectedSalesTotal(
            id: rec.id,
            expectedSalesTotal: totalSales,
          );
      ref.invalidate(posPullStatusesProvider);
      await ref.read(reconciliationsProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${branch.name} satışları çekildi ve icmal güncellendi.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${branch.name} aktarımı başarısız: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncingBranchId = '');
    }
  }

  Future<void> _createOrOpen(_CloseRow row) async {
    try {
      final rec = row.reconciliation ?? await _ensureReconciliation(row.branch);
      if (!mounted) return;
      context.go('/reconciliations/${rec.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('İcmal açılamadı: $e')));
    }
  }

  Future<void> _approve(CashReconciliation rec) async {
    setState(() => _approvingId = rec.id);
    try {
      await ref.read(reconciliationsProvider.notifier).approve(rec.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İcmal onaylandı.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Onaylanamadı: $e')));
    } finally {
      if (mounted) setState(() => _approvingId = '');
    }
  }

  double _numToDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }
}

class _CloseRow {
  const _CloseRow({
    required this.branch,
    required this.dataSource,
    required this.posStatus,
    required this.reconciliation,
  });

  final Branch branch;
  final BranchDataSource? dataSource;
  final PosPullStatus? posStatus;
  final CashReconciliation? reconciliation;

  bool get hasConnection => dataSource?.isActive == true;
  bool get posPulledForDate {
    final d = posStatus?.lastBusinessDate;
    if (d == null || reconciliation == null) return false;
    return d.year == reconciliation!.date.year &&
        d.month == reconciliation!.date.month &&
        d.day == reconciliation!.date.day;
  }

  bool get needsAccounting {
    final rec = reconciliation;
    if (rec == null) return false;
    return rec.status == ReconciliationStatus.draft &&
        rec.expectedSalesTotal.abs() > 0.01 &&
        rec.paymentTotal.abs() <= 0.01;
  }

  bool get hasDifference {
    final rec = reconciliation;
    if (rec == null || rec.status == ReconciliationStatus.draft) return false;
    return rec.difference.abs() > 0.01;
  }

  List<AttachmentKind> get missingDocs {
    final rec = reconciliation;
    if (rec == null) return const [];
    return missingRequiredAttachmentKinds(rec);
  }

  _CloseState get state {
    final rec = reconciliation;
    if (!hasConnection && rec == null) return _CloseState.noConnection;
    if (rec == null) return _CloseState.missingReconciliation;
    if (needsAccounting) return _CloseState.needsAccounting;
    if (missingDocs.isNotEmpty) return _CloseState.missingDocs;
    if (hasDifference) return _CloseState.hasDifference;
    return switch (rec.status) {
      ReconciliationStatus.draft => _CloseState.readyToSubmit,
      ReconciliationStatus.submitted => _CloseState.waitingApproval,
      ReconciliationStatus.approved => _CloseState.approved,
      ReconciliationStatus.rejected => _CloseState.rejected,
    };
  }
}

enum _CloseState {
  noConnection,
  missingReconciliation,
  needsAccounting,
  missingDocs,
  hasDifference,
  readyToSubmit,
  waitingApproval,
  approved,
  rejected,
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.dateLabel,
    required this.branches,
    required this.selectedBranchId,
    required this.onPickDate,
    required this.onToday,
    required this.onBranchChanged,
    required this.onRefresh,
  });

  final String dateLabel;
  final List<Branch> branches;
  final String? selectedBranchId;
  final VoidCallback onPickDate;
  final VoidCallback onToday;
  final ValueChanged<String?>? onBranchChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 210,
              child: OutlinedButton.icon(
                onPressed: onPickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(dateLabel),
              ),
            ),
            OutlinedButton(onPressed: onToday, child: const Text('Bugün')),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String?>(
                initialValue: selectedBranchId,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tüm şubeler'),
                  ),
                  for (final b in branches)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: onBranchChanged,
                decoration: const InputDecoration(
                  labelText: 'Şube',
                  isDense: true,
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: 'Yenile',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final double width;
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 96,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  foregroundColor: color,
                  child: Icon(icon),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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

class _BranchCloseTile extends StatelessWidget {
  const _BranchCloseTile({
    required this.row,
    required this.role,
    required this.money,
    required this.isSyncing,
    required this.isApproving,
    required this.onSync,
    required this.onOpen,
    required this.onCreateOrOpen,
    required this.onApprove,
  });

  final _CloseRow row;
  final UserRole role;
  final NumberFormat money;
  final bool isSyncing;
  final bool isApproving;
  final VoidCallback? onSync;
  final VoidCallback? onOpen;
  final VoidCallback onCreateOrOpen;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final rec = row.reconciliation;
    final scheme = Theme.of(context).colorScheme;
    final stateStyle = _stateStyle(row.state, scheme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          final metrics = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Metric(
                label: 'Satış',
                value: money.format(rec?.expectedSalesTotal ?? 0),
              ),
              _Metric(
                label: 'Ödeme',
                value: money.format(rec?.paymentTotal ?? 0),
              ),
              _Metric(
                label: 'Fark',
                value: money.format(rec?.difference ?? 0),
                highlight: row.hasDifference,
              ),
              _Metric(
                label: 'Evrak',
                value: row.missingDocs.isEmpty
                    ? '${rec?.attachmentsCount ?? 0}'
                    : 'Eksik ${row.missingDocs.length}',
                highlight: row.missingDocs.isNotEmpty,
              ),
            ],
          );

          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onSync,
                icon: isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(isSyncing ? 'Çekiliyor' : 'Satış Çek'),
              ),
              OutlinedButton.icon(
                onPressed: onCreateOrOpen,
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(rec == null ? 'İcmal Aç' : 'Ödeme Gir'),
              ),
              if (onApprove != null)
                FilledButton.tonalIcon(
                  onPressed: onApprove,
                  icon: isApproving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(isApproving ? 'Onaylanıyor' : 'Onayla'),
                ),
              if (onOpen != null)
                IconButton.outlined(
                  tooltip: 'Detay',
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new),
                ),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    row.hasConnection
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.branch.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          row.hasConnection
                              ? 'POS bağlı${row.posStatus?.lastPulledAt == null ? '' : ' • Son çekim ${DateFormat('dd.MM HH:mm', 'tr_TR').format(row.posStatus!.lastPulledAt!.toLocal())}'}'
                              : 'POS bağlantısı yok',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _StatePill(label: stateStyle.label, color: stateStyle.color),
                ],
              ),
              const SizedBox(height: 10),
              if (compact) ...[
                metrics,
                const SizedBox(height: 10),
                actions,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: metrics),
                    actions,
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  ({String label, Color color}) _stateStyle(
    _CloseState state,
    ColorScheme scheme,
  ) {
    return switch (state) {
      _CloseState.noConnection => (label: 'Bağlantı yok', color: scheme.error),
      _CloseState.missingReconciliation => (
        label: 'İcmal yok',
        color: Colors.orange.shade800,
      ),
      _CloseState.needsAccounting => (
        label: 'Ödeme bekliyor',
        color: Colors.blue.shade800,
      ),
      _CloseState.missingDocs => (
        label: 'Evrak eksik',
        color: Colors.orange.shade900,
      ),
      _CloseState.hasDifference => (label: 'Fark var', color: scheme.error),
      _CloseState.readyToSubmit => (
        label: 'Kontrol edilecek',
        color: Colors.teal.shade700,
      ),
      _CloseState.waitingApproval => (
        label: 'Onay bekliyor',
        color: Colors.purple.shade700,
      ),
      _CloseState.approved => (
        label: 'Onaylandı',
        color: Colors.green.shade700,
      ),
      _CloseState.rejected => (label: 'Reddedildi', color: scheme.error),
    };
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 136,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: highlight ? scheme.error : scheme.outlineVariant,
        ),
        color: highlight ? scheme.errorContainer.withValues(alpha: 0.35) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }
}

class _ApprovalFocusCard extends StatelessWidget {
  const _ApprovalFocusCard({
    required this.rows,
    required this.money,
    required this.onOpen,
  });

  final List<_CloseRow> rows;
  final NumberFormat money;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Onay Odak Listesi',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row.branch.name),
                subtitle: Text(
                  'Satış ${money.format(row.reconciliation!.expectedSalesTotal)} • Ödeme ${money.format(row.reconciliation!.paymentTotal)} • Fark ${money.format(row.reconciliation!.difference)}',
                ),
                trailing: IconButton(
                  tooltip: 'İncele',
                  onPressed: () => onOpen(row.reconciliation!.id),
                  icon: const Icon(Icons.open_in_new),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
