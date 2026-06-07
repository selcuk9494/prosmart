import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/config.dart';
import '../../app/api_client.dart';
import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class ReconciliationListPage extends ConsumerStatefulWidget {
  const ReconciliationListPage({super.key});

  @override
  ConsumerState<ReconciliationListPage> createState() =>
      _ReconciliationListPageState();
}

class _ReconciliationListPageState extends ConsumerState<ReconciliationListPage> {
  static DateTime? _persistFromDate;
  static DateTime? _persistToDate;
  static String? _persistBranchId;
  static ReconciliationStatus? _persistStatus;
  static bool _persistOnlyMismatched = false;
  static bool _persistOnlyMissingDocs = false;

  DateTime? _fromDate;
  DateTime? _toDate;
  String? _branchId;
  ReconciliationStatus? _status;
  bool _onlyMismatched = false;
  bool _onlyMissingDocs = false;
  bool _appliedQuery = false;
  bool _isBulkUpdating = false;
  int _bulkDone = 0;
  int _bulkTotal = 0;
  String? _bulkCurrentLabel;

  double _numToDoubleLocal(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  Color _dayColor(DateTime d) {
    final key = d.year * 10000 + d.month * 100 + d.day;
    const palette = <Color>[
      Color(0xFFF7F7F7),
      Color(0xFFF1F8E9),
      Color(0xFFE8F5E9),
      Color(0xFFE0F2F1),
      Color(0xFFE0F7FA),
      Color(0xFFE3F2FD),
      Color(0xFFE8EAF6),
      Color(0xFFF3E5F5),
      Color(0xFFFCE4EC),
      Color(0xFFFFF3E0),
      Color(0xFFFFFDE7),
      Color(0xFFF9FBE7),
    ];
    return palette[key.abs() % palette.length];
  }

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _fromDate = _persistFromDate ?? DateTime(today.year, today.month, today.day);
    _toDate = _persistToDate ?? DateTime(today.year, today.month, today.day);
    _branchId = _persistBranchId;
    _status = _persistStatus;
    _onlyMismatched = _persistOnlyMismatched;
    _onlyMissingDocs = _persistOnlyMissingDocs;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appliedQuery) return;
    final uri = GoRouterState.of(context).uri;
    final statusRaw = uri.queryParameters['status']?.trim().toLowerCase();
    if (statusRaw != null && statusRaw.isNotEmpty) {
      _status = switch (statusRaw) {
        'draft' => ReconciliationStatus.draft,
        'submitted' => ReconciliationStatus.submitted,
        'approved' => ReconciliationStatus.approved,
        'rejected' => ReconciliationStatus.rejected,
        _ => _status,
      };
    }
    final onlyMissingDocsRaw = uri.queryParameters['onlyMissingDocs']?.trim().toLowerCase();
    if (onlyMissingDocsRaw == '1' || onlyMissingDocsRaw == 'true') {
      _onlyMissingDocs = true;
    }
    final onlyMismatchedRaw = uri.queryParameters['onlyMismatched']?.trim().toLowerCase();
    if (onlyMismatchedRaw == '1' || onlyMismatchedRaw == 'true') {
      _onlyMismatched = true;
    }
    _appliedQuery = true;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;

    final branches = ref.watch(branchesProvider);
    final all = ref.watch(reconciliationsProvider);

    final scoped = switch (role) {
      UserRole.manager || UserRole.accounting => all,
      UserRole.branchUser =>
        all.where((e) => e.branchId == session?.branchId).toList(),
    };

    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final filtered = _applyFilters(scoped);
    final showDailyOverview =
        _fromDate != null && _toDate != null && _isSameDay(_fromDate!, _toDate!);

    Future<void> bulkUpdateOrCreate() async {
      if (!AppConfig.hasApi) return;
      if (_isBulkUpdating) return;
      if (session == null) return;
      final from = _fromDate == null ? null : DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      final to = _toDate == null ? null : DateTime(_toDate!.year, _toDate!.month, _toDate!.day);
      if (from == null || to == null) return;

      final activeBranches = branches.where((e) => e.isActive).toList();
      final branchTargets = (() {
        if (role == UserRole.branchUser) {
          final id = session.branchId;
          if (id == null) return <Branch>[];
          return activeBranches.where((b) => b.id == id).toList();
        }
        if (_branchId != null) {
          return activeBranches.where((b) => b.id == _branchId).toList();
        }
        return activeBranches;
      })();
      if (role != UserRole.branchUser && _branchId != null && branchTargets.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Seçili şube bulunamadı veya pasif.')),
        );
        return;
      }
      if (branchTargets.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Güncellenecek aktif şube yok.')),
        );
        return;
      }

      final dates = <DateTime>[];
      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
        dates.add(d);
      }

      final total = branchTargets.length * dates.length;
      if (total == 0) return;

      final known = <String, String>{
        for (final r in all)
          '${r.branchId}:${DateFormat('yyyy-MM-dd', 'tr_TR').format(DateTime(r.date.year, r.date.month, r.date.day))}': r.id,
      };
      var createdCount = 0;
      var touchedCount = 0;
      var pulledCount = 0;
      var skippedLockedCount = 0;
      String? lastError;

      setState(() {
        _isBulkUpdating = true;
        _bulkDone = 0;
        _bulkTotal = total;
        _bulkCurrentLabel = null;
      });

      if (context.mounted) {
        final targetLabel = _branchId == null
            ? 'Tüm Şubeler'
            : (branchTargets.isNotEmpty ? branchTargets.first.name : 'Seçili Şube');
        final rangeLabel = dates.length == 1
            ? DateFormat('yyyy-MM-dd', 'tr_TR').format(dates.first)
            : '${DateFormat('yyyy-MM-dd', 'tr_TR').format(dates.first)} → ${DateFormat('yyyy-MM-dd', 'tr_TR').format(dates.last)}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hedef: $targetLabel • Tarih: $rangeLabel')),
        );
      }

      final dio = ref.read(dioProvider);
      try {
        for (final b in branchTargets) {
          for (final d in dates) {
            final dayStr = DateFormat('yyyy-MM-dd', 'tr_TR').format(d);
            final key = '${b.id}:$dayStr';
            if (mounted) {
              final nextLabel = '${b.name} • $dayStr';
              if (_bulkCurrentLabel != nextLabel) {
                setState(() => _bulkCurrentLabel = nextLabel);
              }
            }
            try {
              final created = await dio.post<Map<String, dynamic>>(
                '/cash-reconciliations',
                data: {
                  'branchId': b.id,
                  'businessDate': dayStr,
                },
              );
              final id = created.data?['id']?.toString();
              if (id == null || id.isEmpty) {
                continue;
              }

              CashReconciliation? recon;
              try {
                recon = await ref.read(reconciliationsProvider.notifier).fetchById(id);
                ref.read(reconciliationsProvider.notifier).upsertLocal(recon);
              } catch (_) {}

              final existed = known.containsKey(key);
              if (!existed) {
                createdCount += 1;
              } else {
                touchedCount += 1;
              }
              known[key] = id;

              if (recon == null) {
                final placeholder = CashReconciliation(
                  id: id,
                  branchId: b.id,
                  date: DateTime(d.year, d.month, d.day),
                  expectedSalesTotal: 0,
                  paymentLines: const [],
                  expenseLines: const [],
                  attachments: const [],
                  status: ReconciliationStatus.draft,
                  createdByUserId: session.userId,
                );
                ref.read(reconciliationsProvider.notifier).upsertLocal(placeholder);
              }

              final status = recon?.status;
              final canEditSales =
                  status == null || status == ReconciliationStatus.draft || status == ReconciliationStatus.rejected;

              if (canEditSales) {
                final pullRes = await dio.post<Map<String, dynamic>>(
                  '/pos/pull/branch-daily',
                  data: {
                    'branchId': b.id,
                    'businessDate': dayStr,
                    'businessDayStartHour': b.businessDayStartHour,
                  },
                );
                pulledCount += 1;

                final pullData = pullRes.data ?? const {};
                var totalSales = _numToDoubleLocal(pullData['dailyTotal']);
                if (totalSales.abs() <= 0.0001) {
                  try {
                    final regs = await dio.get<List<dynamic>>(
                      '/sales/daily/registers',
                      queryParameters: {
                        'branchId': b.id,
                        'date': dayStr,
                      },
                    );
                    final rows = regs.data ?? const [];
                    totalSales = 0.0;
                    for (final raw in rows) {
                      if (raw is! Map<String, dynamic>) continue;
                      totalSales += _numToDoubleLocal(raw['grossTotal']);
                    }
                  } catch (_) {}
                }

                if (totalSales.abs() > 0.0001) {
                  await ref.read(reconciliationsProvider.notifier).updateExpectedSalesTotal(
                        id: id,
                        expectedSalesTotal: totalSales,
                      );
                }
              } else {
                skippedLockedCount += 1;
              }
            } catch (e) {
              lastError = e.toString();
            } finally {
              if (!mounted) return;
              setState(() => _bulkDone += 1);
            }
          }
        }
      } finally {
        if (!mounted) return;
        setState(() {
          _isBulkUpdating = false;
          _bulkCurrentLabel = null;
        });
        if (!context.mounted) return;
        final msg = [
          if (createdCount > 0) 'Açılan: $createdCount',
          if (touchedCount > 0) 'Güncellenen: $touchedCount',
          if (pulledCount > 0) 'Satış çekilen: $pulledCount',
          if (skippedLockedCount > 0) 'Kilitli atlanan: $skippedLockedCount',
          if (lastError != null) 'Son hata: $lastError',
        ].join(' • ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.isEmpty ? 'İşlem tamamlandı.' : msg)),
        );
      }
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text('Kasa İcmal', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 12),
              if (_isBulkUpdating && (_bulkCurrentLabel ?? '').isNotEmpty)
                Expanded(
                  child: Text(
                    'Aktarım: $_bulkCurrentLabel',
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              if (AppConfig.hasApi)
                FilledButton.icon(
                  onPressed: _isBulkUpdating ? null : bulkUpdateOrCreate,
                  icon: _isBulkUpdating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: Text(
                    _isBulkUpdating
                        ? 'Güncelleniyor...'
                        : (_branchId == null
                            ? 'Seçili Tarihleri Güncelle (Tümü)'
                            : 'Seçili Tarihleri Güncelle (${branches.firstWhere((b) => b.id == _branchId, orElse: () => const Branch(id: "x", name: "Şube")).name})'),
                  ),
                ),
              if (AppConfig.hasApi) const SizedBox(width: 8),
              IconButton(
                tooltip: 'Excel (CSV) dışa aktar',
                onPressed: filtered.isEmpty ? null : () => _exportCsv(filtered),
                icon: const Icon(Icons.table_view),
              ),
              IconButton(
                tooltip: 'PDF dışa aktar',
                onPressed: filtered.isEmpty ? null : () => _exportPdf(filtered, branches),
                icon: const Icon(Icons.picture_as_pdf),
              ),
              const SizedBox(width: 8),
              Text('${filtered.length} kayıt'),
            ],
          ),
          const SizedBox(height: 12),
          if (_isBulkUpdating)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Güncelleniyor: $_bulkDone / $_bulkTotal'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _bulkTotal == 0 ? null : (_bulkDone / _bulkTotal).clamp(0, 1),
                      minHeight: 6,
                    ),
                  ],
                ),
              ),
            ),
          _FiltersCard(
            branches: branches.where((e) => e.isActive).toList(),
            fromDate: _fromDate,
            toDate: _toDate,
            branchId: _branchId,
            status: _status,
            onlyMismatched: _onlyMismatched,
            onlyMissingDocs: _onlyMissingDocs,
            onChanged: (next) {
              setState(() {
                _fromDate = next.fromDate;
                _toDate = next.toDate;
                _branchId = next.branchId;
                _status = next.status;
                _onlyMismatched = next.onlyMismatched;
                _onlyMissingDocs = next.onlyMissingDocs;

                _persistFromDate = _fromDate;
                _persistToDate = _toDate;
                _persistBranchId = _branchId;
                _persistStatus = _status;
                _persistOnlyMismatched = _onlyMismatched;
                _persistOnlyMissingDocs = _onlyMissingDocs;
              });
            },
          ),
          if (showDailyOverview) ...[
            const SizedBox(height: 12),
            _DailyOverviewCard(
              date: _fromDate!,
              branches: branches.where((e) => e.isActive).toList(),
              items: filtered,
              money: money,
              branchFilterId: _branchId,
            ),
          ],
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Kayıt bulunamadı.'),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Tarih')),
                      DataColumn(label: Text('Şube')),
                      DataColumn(label: Text('Durum')),
                      DataColumn(label: Text('Satış')),
                      DataColumn(label: Text('KK OCR')),
                      DataColumn(label: Text('KK Manuel')),
                      DataColumn(label: Text('Ödeme')),
                      DataColumn(label: Text('Fark')),
                      DataColumn(label: Text('Evrak')),
                    ],
                    rows: [
                      for (final r in filtered)
                        () {
                          String branchName(String id) => branches
                              .firstWhere((b) => b.id == id, orElse: () => const Branch(id: 'x', name: '?'))
                              .name;

                          String statusLabel(ReconciliationStatus s) => switch (s) {
                                ReconciliationStatus.draft => 'Taslak',
                                ReconciliationStatus.submitted => 'Onay Bekliyor',
                                ReconciliationStatus.approved => 'Onaylandı',
                                ReconciliationStatus.rejected => 'Reddedildi',
                              };

                          final missing = missingRequiredAttachmentKinds(r);
                          final hasDiff = r.status != ReconciliationStatus.draft && r.difference.abs() > 0.01;
                          final scheme = Theme.of(context).colorScheme;
                          final rowColor = hasDiff
                              ? (missing.isEmpty ? scheme.tertiaryContainer : scheme.errorContainer)
                              : _dayColor(r.date);

                          final today = DateTime.now();
                          final dayOnly = DateTime(today.year, today.month, today.day);
                          final yesterday = dayOnly.subtract(const Duration(days: 1));
                          final isLiveCheckDay = _isSameDay(r.date, dayOnly) || _isSameDay(r.date, yesterday);
                          final branch = branches.firstWhere(
                            (b) => b.id == r.branchId,
                            orElse: () => const Branch(id: 'x', name: '?'),
                          );
                          final liveTotalAsync = (AppConfig.hasApi && isLiveCheckDay)
                              ? ref.watch(
                                  posLiveDailyTotalProvider(
                                    (
                                      branchId: r.branchId,
                                      date: r.date,
                                      businessDayStartHour: branch.businessDayStartHour,
                                      registerCode: null,
                                    ),
                                  ),
                                )
                              : null;

                          final ocrCard = r.ocrCardTotal;
                          final manualCard = r.manualCardTotal;
                          final hasOcr = r.hasEndOfDayReport && ocrCard.abs() > 0.0001;
                          final hasManual = manualCard.abs() > 0.0001;
                          final showManualWarning = hasManual && !hasOcr;

                          return DataRow(
                            color: WidgetStatePropertyAll(rowColor),
                            onSelectChanged: (_) => context.go('/reconciliations/${r.id}'),
                            cells: [
                              DataCell(Text(DateFormat('yyyy-MM-dd', 'tr_TR').format(r.date))),
                              DataCell(Text(branchName(r.branchId))),
                              DataCell(
                                liveTotalAsync == null
                                    ? Text(statusLabel(r.status))
                                    : liveTotalAsync.when(
                                        data: (liveTotal) {
                                          final hasMissingLive = liveTotal > r.expectedSalesTotal + 0.01;
                                          if (!hasMissingLive) {
                                            return Text(statusLabel(r.status));
                                          }
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(statusLabel(r.status)),
                                              const SizedBox(width: 8),
                                              Chip(
                                                backgroundColor: scheme.errorContainer,
                                                label: Text(
                                                  'Eksik satış',
                                                  style: TextStyle(color: scheme.onErrorContainer),
                                                ),
                                                visualDensity: VisualDensity.compact,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                padding: EdgeInsets.zero,
                                              ),
                                            ],
                                          );
                                        },
                                        loading: () => Text(statusLabel(r.status)),
                                        error: (e, st) => Text(statusLabel(r.status)),
                                      ),
                              ),
                              DataCell(
                                liveTotalAsync == null
                                    ? Text(money.format(r.expectedSalesTotal))
                                    : liveTotalAsync.when(
                                        data: (liveTotal) {
                                          final hasMissingLive = liveTotal > r.expectedSalesTotal + 0.01;
                                          if (!hasMissingLive) {
                                            return Text(money.format(r.expectedSalesTotal));
                                          }
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(money.format(r.expectedSalesTotal)),
                                              const SizedBox(width: 6),
                                              Tooltip(
                                                message:
                                                    'Eksik satış olabilir. POS canlı: ${money.format(liveTotal)} • Form: ${money.format(r.expectedSalesTotal)}',
                                                child: Icon(
                                                  Icons.error_outline,
                                                  size: 18,
                                                  color: Theme.of(context).colorScheme.error,
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                        loading: () => Text(money.format(r.expectedSalesTotal)),
                                        error: (e, st) => Text(money.format(r.expectedSalesTotal)),
                                      ),
                              ),
                              DataCell(Text(hasOcr ? money.format(ocrCard) : '')),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(hasManual ? money.format(manualCard) : ''),
                                    if (showManualWarning) ...[
                                      const SizedBox(width: 6),
                                      Tooltip(
                                        message: 'Kredi kartı tutarı manuel girilmiş (OCR raporu yok).',
                                        child: Icon(
                                          Icons.warning_amber_outlined,
                                          size: 18,
                                          color: scheme.error,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              DataCell(Text(money.format(r.paymentTotal))),
                              DataCell(Text(money.format(r.difference))),
                              DataCell(
                                Text(
                                  missing.isEmpty ? r.attachmentsCount.toString() : 'Eksik: ${missing.length}',
                                ),
                              ),
                            ],
                          );
                        }(),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await _showCreateDialog(context, ref);
          if (created != null && context.mounted) {
            setState(() {
              _fromDate = DateTime(created.date.year, created.date.month, created.date.day);
              _toDate = DateTime(created.date.year, created.date.month, created.date.day);
              _branchId = null;
            });
            context.go('/reconciliations/${created.id}');
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Yeni'),
      ),
    );
  }

  Future<CashReconciliation?> _showCreateDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final branches = ref.read(branchesProvider).where((e) => e.isActive).toList();
    final auth = ref.read(authControllerProvider).asData?.value;
    if (auth == null) return null;
    if (branches.isEmpty) {
      return showDialog<CashReconciliation>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Yeni Kasa İcmal'),
            content: const Text('Şubeler yükleniyor. Lütfen tekrar deneyin.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tamam'),
              ),
            ],
          );
        },
      );
    }

    var selectedBranchId = auth.branchId ?? (branches.isNotEmpty ? branches.first.id : null);
    var selectedDate = DateTime.now();
    selectedDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    var isSaving = false;

    return showDialog<CashReconciliation>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Yeni Kasa İcmal'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedBranchId,
                    items: [
                      for (final b in branches)
                        DropdownMenuItem(value: b.id, child: Text(b.name)),
                    ],
                    onChanged: auth.role == UserRole.branchUser
                        ? null
                        : (v) => setState(() => selectedBranchId = v),
                    decoration: const InputDecoration(labelText: 'Şube'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('yyyy-MM-dd', 'tr_TR').format(selectedDate),
                        ),
                      ),
                      TextButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() {
                                    selectedDate = DateTime(picked.year, picked.month, picked.day);
                                  });
                                }
                              },
                        child: const Text('Tarih Seç'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: (selectedBranchId == null || isSaving)
                      ? null
                      : () async {
                          setState(() => isSaving = true);
                          try {
                            final created = await ref
                                .read(reconciliationsProvider.notifier)
                                .createDraft(
                                  branchId: selectedBranchId!,
                                  date: selectedDate,
                                  userId: auth.userId,
                                );
                            if (context.mounted) {
                              Navigator.of(context).pop(created);
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Hata: $e')),
                            );
                          } finally {
                            if (context.mounted) setState(() => isSaving = false);
                          }
                        },
                  child: Text(isSaving ? 'Oluşturuluyor...' : 'Oluştur'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<CashReconciliation> _applyFilters(List<CashReconciliation> items) {
    DateTime? from = _fromDate;
    DateTime? to = _toDate;
    if (from != null) from = DateTime(from.year, from.month, from.day);
    if (to != null) to = DateTime(to.year, to.month, to.day);

    bool inRange(DateTime date) {
      final d = DateTime(date.year, date.month, date.day);
      if (from != null && d.isBefore(from)) return false;
      if (to != null && d.isAfter(to)) return false;
      return true;
    }

    return [
      for (final r in items)
        if (inRange(r.date) &&
            (_branchId == null || r.branchId == _branchId) &&
            (_status == null || r.status == _status) &&
            (!_onlyMismatched ||
                (r.status != ReconciliationStatus.draft &&
                    r.difference.abs() > 0.01)) &&
            (!_onlyMissingDocs || missingRequiredAttachmentKinds(r).isNotEmpty))
          r,
    ];
  }

  Future<void> _exportCsv(List<CashReconciliation> items) async {
    final branches = ref.read(branchesProvider);
    final header = [
      'Tarih',
      'Şube',
      'Durum',
      'Satış',
      'Ödeme Toplamı',
      'Fark',
      'Eksik Evrak',
      'Evrak Sayısı',
    ].join(';');

    String branchName(String id) => branches
        .firstWhere((b) => b.id == id, orElse: () => const Branch(id: 'x', name: '?'))
        .name;

    String statusLabel(ReconciliationStatus s) => switch (s) {
      ReconciliationStatus.draft => 'Taslak',
      ReconciliationStatus.submitted => 'Onay Bekliyor',
      ReconciliationStatus.approved => 'Onaylandı',
      ReconciliationStatus.rejected => 'Reddedildi',
    };

    String num(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

    final lines = <String>[header];
    for (final r in items) {
      final missing = missingRequiredAttachmentKinds(r);
      lines.add([
        DateFormat('yyyy-MM-dd', 'tr_TR').format(r.date),
        branchName(r.branchId),
        statusLabel(r.status),
        num(r.expectedSalesTotal),
        num(r.paymentTotal),
        num(r.difference),
        missing.map(attachmentKindLabel).join(', '),
        r.attachmentsCount.toString(),
      ].join(';'));
    }

    final csv = lines.join('\n');
    final bytes = Uint8List.fromList(utf8.encode(csv));

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name:
                'prosmart_kasa_icmal_${DateTime.now().millisecondsSinceEpoch}.csv',
            mimeType: 'text/csv',
          ),
        ],
        text: 'Prosmart • Kasa İcmal',
      ),
    );
  }

  Future<void> _exportPdf(
    List<CashReconciliation> items,
    List<Branch> branches,
  ) async {
    String branchName(String id) => branches
        .firstWhere((b) => b.id == id, orElse: () => const Branch(id: 'x', name: '?'))
        .name;

    String statusLabel(ReconciliationStatus s) => switch (s) {
      ReconciliationStatus.draft => 'Taslak',
      ReconciliationStatus.submitted => 'Onay Bekliyor',
      ReconciliationStatus.approved => 'Onaylandı',
      ReconciliationStatus.rejected => 'Reddedildi',
    };

    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) {
          return [
            pw.Text(
              'Prosmart • Kasa İcmal Raporu',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Tarih',
                'Şube',
                'Durum',
                'Satış',
                'Toplam',
                'Fark',
                'Eksik Evrak',
              ],
              data: [
                for (final r in items)
                  [
                    DateFormat('yyyy-MM-dd', 'tr_TR').format(r.date),
                    branchName(r.branchId),
                    statusLabel(r.status),
                    money.format(r.expectedSalesTotal),
                    money.format(r.paymentTotal),
                    money.format(r.difference),
                    missingRequiredAttachmentKinds(r)
                        .map(attachmentKindLabel)
                        .join(', '),
                  ],
              ],
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(),
              cellHeight: 18,
            ),
          ];
        },
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'prosmart_kasa_icmal_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}

class _FiltersCard extends StatelessWidget {
  const _FiltersCard({
    required this.branches,
    required this.fromDate,
    required this.toDate,
    required this.branchId,
    required this.status,
    required this.onlyMismatched,
    required this.onlyMissingDocs,
    required this.onChanged,
  });

  final List<Branch> branches;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? branchId;
  final ReconciliationStatus? status;
  final bool onlyMismatched;
  final bool onlyMissingDocs;
  final ValueChanged<_FilterState> onChanged;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

    DateTime weekStart(DateTime d) {
      final wd = d.weekday;
      return d.subtract(Duration(days: wd - DateTime.monday));
    }

    DateTime monthStart(DateTime d) => DateTime(d.year, d.month, 1);
    DateTime monthEnd(DateTime d) => DateTime(d.year, d.month + 1, 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Filtreler', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    final today = DateTime.now();
                    onChanged(
                      _FilterState(
                        fromDate: DateTime(today.year, today.month, today.day),
                        toDate: DateTime(today.year, today.month, today.day),
                        branchId: null,
                        status: null,
                        onlyMismatched: false,
                        onlyMissingDocs: false,
                      ),
                    );
                  },
                  child: const Text('Sıfırla'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Bugün'),
                  selected: fromDate != null && toDate != null && sameDay(fromDate!, today) && sameDay(toDate!, today),
                  onSelected: (_) => onChanged(
                    _FilterState(
                      fromDate: today,
                      toDate: today,
                      branchId: branchId,
                      status: status,
                      onlyMismatched: onlyMismatched,
                      onlyMissingDocs: onlyMissingDocs,
                    ),
                  ),
                ),
                ChoiceChip(
                  label: const Text('Dün'),
                  selected: fromDate != null &&
                      toDate != null &&
                      sameDay(fromDate!, today.subtract(const Duration(days: 1))) &&
                      sameDay(toDate!, today.subtract(const Duration(days: 1))),
                  onSelected: (_) {
                    final d = today.subtract(const Duration(days: 1));
                    onChanged(
                      _FilterState(
                        fromDate: d,
                        toDate: d,
                        branchId: branchId,
                        status: status,
                        onlyMismatched: onlyMismatched,
                        onlyMissingDocs: onlyMissingDocs,
                      ),
                    );
                  },
                ),
                ChoiceChip(
                  label: const Text('Bu hafta'),
                  selected: fromDate != null && toDate != null && sameDay(fromDate!, weekStart(today)) && sameDay(toDate!, today),
                  onSelected: (_) => onChanged(
                    _FilterState(
                      fromDate: weekStart(today),
                      toDate: today,
                      branchId: branchId,
                      status: status,
                      onlyMismatched: onlyMismatched,
                      onlyMissingDocs: onlyMissingDocs,
                    ),
                  ),
                ),
                ChoiceChip(
                  label: const Text('Bu ay'),
                  selected: fromDate != null && toDate != null && sameDay(fromDate!, monthStart(today)) && sameDay(toDate!, today),
                  onSelected: (_) => onChanged(
                    _FilterState(
                      fromDate: monthStart(today),
                      toDate: today,
                      branchId: branchId,
                      status: status,
                      onlyMismatched: onlyMismatched,
                      onlyMissingDocs: onlyMissingDocs,
                    ),
                  ),
                ),
                ChoiceChip(
                  label: const Text('Geçen ay'),
                  selected: () {
                    if (fromDate == null || toDate == null) return false;
                    final lastMonth = DateTime(today.year, today.month - 1, 1);
                    return sameDay(fromDate!, monthStart(lastMonth)) && sameDay(toDate!, monthEnd(lastMonth));
                  }(),
                  onSelected: (_) {
                    final lastMonth = DateTime(today.year, today.month - 1, 1);
                    onChanged(
                      _FilterState(
                        fromDate: monthStart(lastMonth),
                        toDate: monthEnd(lastMonth),
                        branchId: branchId,
                        status: status,
                        onlyMismatched: onlyMismatched,
                        onlyMissingDocs: onlyMissingDocs,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _DateFilter(
                  label: 'Başlangıç',
                  value: fromDate,
                  onPick: (d) => onChanged(
                    _FilterState(
                      fromDate: d,
                      toDate: toDate ?? d,
                      branchId: branchId,
                      status: status,
                      onlyMismatched: onlyMismatched,
                      onlyMissingDocs: onlyMissingDocs,
                    ),
                  ),
                ),
                _DateFilter(
                  label: 'Bitiş',
                  value: toDate,
                  onPick: (d) => onChanged(
                    _FilterState(
                      fromDate: fromDate ?? d,
                      toDate: d,
                      branchId: branchId,
                      status: status,
                      onlyMismatched: onlyMismatched,
                      onlyMissingDocs: onlyMissingDocs,
                    ),
                  ),
                ),
                SizedBox(
                  width: isWide ? 260 : double.infinity,
                  child: DropdownButtonFormField<String?>(
                    initialValue: branchId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Tüm Şubeler')),
                      for (final b in branches)
                        DropdownMenuItem(value: b.id, child: Text(b.name)),
                    ],
                    onChanged: (v) => onChanged(
                      _FilterState(
                        fromDate: fromDate,
                        toDate: toDate,
                        branchId: v,
                        status: status,
                        onlyMismatched: onlyMismatched,
                        onlyMissingDocs: onlyMissingDocs,
                      ),
                    ),
                    decoration: const InputDecoration(labelText: 'Şube'),
                  ),
                ),
                SizedBox(
                  width: isWide ? 260 : double.infinity,
                  child: DropdownButtonFormField<ReconciliationStatus?>(
                    initialValue: status,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Tüm Durumlar')),
                      DropdownMenuItem(
                        value: ReconciliationStatus.draft,
                        child: Text('Taslak'),
                      ),
                      DropdownMenuItem(
                        value: ReconciliationStatus.submitted,
                        child: Text('Onay Bekliyor'),
                      ),
                      DropdownMenuItem(
                        value: ReconciliationStatus.approved,
                        child: Text('Onaylandı'),
                      ),
                      DropdownMenuItem(
                        value: ReconciliationStatus.rejected,
                        child: Text('Reddedildi'),
                      ),
                    ],
                    onChanged: (v) => onChanged(
                      _FilterState(
                        fromDate: fromDate,
                        toDate: toDate,
                        branchId: branchId,
                        status: v,
                        onlyMismatched: onlyMismatched,
                        onlyMissingDocs: onlyMissingDocs,
                      ),
                    ),
                    decoration: const InputDecoration(labelText: 'Durum'),
                  ),
                ),
                SizedBox(
                  width: isWide ? 260 : double.infinity,
                  child: SwitchListTile.adaptive(
                    value: onlyMismatched,
                    onChanged: (v) => onChanged(
                      _FilterState(
                        fromDate: fromDate,
                        toDate: toDate,
                        branchId: branchId,
                        status: status,
                        onlyMismatched: v,
                        onlyMissingDocs: onlyMissingDocs,
                      ),
                    ),
                    title: const Text('Sadece farklılık'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                SizedBox(
                  width: isWide ? 260 : double.infinity,
                  child: SwitchListTile.adaptive(
                    value: onlyMissingDocs,
                    onChanged: (v) => onChanged(
                      _FilterState(
                        fromDate: fromDate,
                        toDate: toDate,
                        branchId: branchId,
                        status: status,
                        onlyMismatched: onlyMismatched,
                        onlyMissingDocs: v,
                      ),
                    ),
                    title: const Text('Sadece evrak eksiği'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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

class _DateFilter extends StatelessWidget {
  const _DateFilter({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final text = value == null
        ? 'Seçiniz'
        : DateFormat('yyyy-MM-dd', 'tr_TR').format(value!);

    return SizedBox(
      width: isWide ? 260 : double.infinity,
      child: OutlinedButton(
        onPressed: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (picked != null) onPick(picked);
        },
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('$label: $text'),
        ),
      ),
    );
  }
}

class _DailyOverviewCard extends ConsumerWidget {
  const _DailyOverviewCard({
    required this.date,
    required this.branches,
    required this.items,
    required this.money,
    required this.branchFilterId,
  });

  final DateTime date;
  final List<Branch> branches;
  final List<CashReconciliation> items;
  final NumberFormat money;
  final String? branchFilterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredBranches = branchFilterId == null
        ? branches
        : branches.where((b) => b.id == branchFilterId).toList();

    CashReconciliation? findForBranch(String branchId) {
      for (final r in items) {
        if (r.branchId == branchId &&
            r.date.year == date.year &&
            r.date.month == date.month &&
            r.date.day == date.day) {
          return r;
        }
      }
      return null;
    }

    final scheme = Theme.of(context).colorScheme;
    final dateText = DateFormat('yyyy-MM-dd', 'tr_TR').format(date);
    final today = DateTime.now();
    final dayOnly = DateTime(today.year, today.month, today.day);
    final yesterday = dayOnly.subtract(const Duration(days: 1));
    final isLiveCheckDay =
        (date.year == dayOnly.year && date.month == dayOnly.month && date.day == dayOnly.day) ||
            (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Günlük Kontrol • $dateText',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final b in filteredBranches)
              Builder(
                builder: (context) {
                  final rec = findForBranch(b.id);
                  final liveTotalAsync = (AppConfig.hasApi && isLiveCheckDay)
                      ? ref.watch(
                          posLiveDailyTotalProvider(
                            (
                              branchId: b.id,
                              date: date,
                              businessDayStartHour: b.businessDayStartHour,
                              registerCode: null,
                            ),
                          ),
                        )
                      : null;
                  if (rec == null) {
                    if (liveTotalAsync != null) {
                      return liveTotalAsync.when(
                        data: (liveTotal) {
                          final hasSales = liveTotal > 0.01;
                          return Card(
                            color: hasSales ? scheme.errorContainer : scheme.surfaceContainerHighest,
                            child: ListTile(
                              title: Text(b.name),
                              subtitle: hasSales
                                  ? Text('İcmal yok • POS canlı: ${money.format(liveTotal)}')
                                  : const Text('Kayıt yok'),
                              trailing: hasSales ? const Icon(Icons.error_outline) : null,
                            ),
                          );
                        },
                        loading: () => Card(
                          color: scheme.surfaceContainerHighest,
                          child: ListTile(
                            title: Text(b.name),
                            subtitle: const Text('Kayıt yok'),
                          ),
                        ),
                        error: (e, st) => Card(
                          color: scheme.errorContainer,
                          child: ListTile(
                            title: Text(b.name),
                            subtitle: const Text('Kayıt yok'),
                            trailing: const Icon(Icons.error_outline),
                          ),
                        ),
                      );
                    }
                    return Card(
                      color: scheme.errorContainer,
                      child: ListTile(
                        title: Text(b.name),
                        subtitle: const Text('Kayıt yok'),
                        trailing: const Icon(Icons.error_outline),
                      ),
                    );
                  }

                  final hasDiff = rec.status != ReconciliationStatus.draft &&
                      rec.difference.abs() > 0.01;
                  final missing = missingRequiredAttachmentKinds(rec);
                  final color = hasDiff
                      ? (missing.isEmpty
                          ? scheme.tertiaryContainer
                          : scheme.errorContainer)
                      : scheme.surfaceContainerHighest;

                  return Card(
                    color: color,
                    child: ListTile(
                      onTap: () => context.go('/reconciliations/${rec.id}'),
                      title: Text(b.name),
                      subtitle: Text(
                        liveTotalAsync == null
                            ? 'Satış: ${money.format(rec.expectedSalesTotal)} • Toplam: ${money.format(rec.paymentTotal)} • Fark: ${money.format(rec.difference)}'
                            : liveTotalAsync.when(
                                data: (liveTotal) {
                                  final hasMissing = liveTotal > rec.expectedSalesTotal + 0.01;
                                  return hasMissing
                                      ? 'Satış: ${money.format(rec.expectedSalesTotal)} • Toplam: ${money.format(rec.paymentTotal)} • Fark: ${money.format(rec.difference)} • Eksik satış olabilir (POS canlı: ${money.format(liveTotal)})'
                                      : 'Satış: ${money.format(rec.expectedSalesTotal)} • Toplam: ${money.format(rec.paymentTotal)} • Fark: ${money.format(rec.difference)}';
                                },
                                loading: () =>
                                    'Satış: ${money.format(rec.expectedSalesTotal)} • Toplam: ${money.format(rec.paymentTotal)} • Fark: ${money.format(rec.difference)}',
                                error: (e, st) =>
                                    'Satış: ${money.format(rec.expectedSalesTotal)} • Toplam: ${money.format(rec.paymentTotal)} • Fark: ${money.format(rec.difference)}',
                              ),
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          Chip(label: Text(_statusLabel(rec.status))),
                          if (hasDiff && missing.isNotEmpty)
                            Chip(
                              label: Text('Evrak: ${missing.length} eksik'),
                              backgroundColor: scheme.errorContainer,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
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

class _FilterState {
  const _FilterState({
    required this.fromDate,
    required this.toDate,
    required this.branchId,
    required this.status,
    required this.onlyMismatched,
    required this.onlyMissingDocs,
  });

  final DateTime? fromDate;
  final DateTime? toDate;
  final String? branchId;
  final ReconciliationStatus? status;
  final bool onlyMismatched;
  final bool onlyMissingDocs;
}
