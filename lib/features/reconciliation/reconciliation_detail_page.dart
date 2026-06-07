import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';

import '../../app/api_client.dart';
import '../../app/config.dart';
import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class ReconciliationDetailPage extends ConsumerStatefulWidget {
  const ReconciliationDetailPage({super.key, required this.reconciliationId});

  final String reconciliationId;

  @override
  ConsumerState<ReconciliationDetailPage> createState() =>
      _ReconciliationDetailPageState();
}

class _ReconciliationDetailPageState
    extends ConsumerState<ReconciliationDetailPage> {
  final _expectedController = TextEditingController();
  final _rejectionReasonController = TextEditingController();
  final Map<String, TextEditingController> _paymentControllers = {};
  final Map<String, TextEditingController> _expenseControllers = {};
  String? _selectedRegisterCode;
  bool _prefilledFromPos = false;
  bool _isPullingSales = false;
  bool _isLoadingItem = false;
  bool _isUploadingEndOfDay = false;
  String? _loadError;
  bool _autoRetryOnce = false;

  String _normalizeRegisterCode(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final n = int.tryParse(v);
    if (n == null) return v;
    return 'KASA-${n.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadItem());
  }

  Future<void> _loadItem() async {
    if (!AppConfig.hasApi) return;
    if (_isLoadingItem) return;
    setState(() {
      _isLoadingItem = true;
      _loadError = null;
    });
    try {
      final fresh = await ref
          .read(reconciliationsProvider.notifier)
          .fetchById(widget.reconciliationId);
      ref.read(reconciliationsProvider.notifier).upsertLocal(fresh);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingItem = false);
    }
  }

  @override
  void dispose() {
    _expectedController.dispose();
    _rejectionReasonController.dispose();
    for (final c in _paymentControllers.values) {
      c.dispose();
    }
    for (final c in _expenseControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;

    final branches = ref.watch(branchesProvider);
    final paymentTypes = ref.watch(paymentTypesProvider).where((e) => e.isActive).toList();
    final expenseTypes = ref.watch(expenseTypesProvider).where((e) => e.isActive).toList();
    final items = ref.watch(reconciliationsProvider);

    final item = items.where((e) => e.id == widget.reconciliationId).firstOrNull;
    if (item == null) {
      if (AppConfig.hasApi && !_isLoadingItem && _loadError == null && !_autoRetryOnce) {
        _autoRetryOnce = true;
        Future.microtask(() => _loadItem());
      }
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoadingItem) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                const Text('Kayıt yükleniyor...'),
              ] else if (_loadError != null) ...[
                const Icon(Icons.error_outline),
                const SizedBox(height: 12),
                Text('Yüklenemedi: $_loadError', textAlign: TextAlign.center),
              ] else ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                const Text('Kayıt aranıyor...'),
              ],
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _isLoadingItem ? null : _loadItem,
                child: const Text('Yenile'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go('/reconciliations'),
                child: const Text('Listeye Dön'),
              ),
            ],
          ),
        ),
      );
    }

    final canEdit = _canEdit(item, session);
    _ensureControllers(item, paymentTypes, expenseTypes);

    final scheme = Theme.of(context).colorScheme;
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final dateText = DateFormat('yyyy-MM-dd', 'tr_TR').format(item.date);
    final branch = branches.firstWhere(
      (b) => b.id == item.branchId,
      orElse: () => const Branch(id: 'x', name: '?'),
    );
    final branchName = branch.name;
    final businessDayStartHour = branch.businessDayStartHour;

    final expected = _parseMoney(_expectedController.text);
    final paymentTotal = _computeTotal(paymentTypes, _paymentControllers);
    final expenseTotal = _computeTotal(expenseTypes, _expenseControllers);
    final diff = paymentTotal - expected;
    final showDiff = diff.abs() > 0.01;

    final today = DateTime.now();
    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final dayOnly = DateTime(today.year, today.month, today.day);
    final yesterday = dayOnly.subtract(const Duration(days: 1));
    final isToday = isSameDay(item.date, dayOnly);
    final isLiveCheckDay = isToday || isSameDay(item.date, yesterday);

    final requiresAttachments =
        item.status != ReconciliationStatus.draft && showDiff;

    final posRegisters =
        ref.watch(posRegisterDailySalesProvider((branchId: item.branchId, date: item.date)));
    final posPayments =
        ref.watch(posRegisterDailyPaymentsProvider((branchId: item.branchId, date: item.date)));
    final posProducts =
        ref.watch(posDailyProductSalesProvider((branchId: item.branchId, date: item.date, registerCode: _selectedRegisterCode)));
    final posAdjustments =
        ref.watch(posDailyAdjustmentsProvider((branchId: item.branchId, date: item.date, registerCode: _selectedRegisterCode)));
    final posGroups =
        ref.watch(posDailySalesGroupsProvider((branchId: item.branchId, date: item.date, registerCode: _selectedRegisterCode)));
    final posCancelledItems = ref.watch(
      posCancelledItemsProvider(
        (
          branchId: item.branchId,
          date: item.date,
          businessDayStartHour: businessDayStartHour,
          registerCode: _selectedRegisterCode,
        ),
      ),
    );
    final endOfDayReports = ref.watch(endOfDayReportsProvider(item.id));
    final branchCashRegistersAsync = ref.watch(branchCashRegistersProvider(item.branchId));

    final liveTotalAsync = (AppConfig.hasApi && isLiveCheckDay)
        ? ref.watch(
            posLiveDailyTotalProvider(
              (
                branchId: item.branchId,
                date: item.date,
                businessDayStartHour: businessDayStartHour,
                registerCode: _selectedRegisterCode,
              ),
            ),
          )
        : null;
    final liveTotalNow = liveTotalAsync?.asData?.value;
    final hasMissingLive = liveTotalNow != null && liveTotalNow > expected + 0.01;
    final submitBlockedReason = (isLiveCheckDay && hasMissingLive)
        ? 'Şimdi veya bir sonraki gün satışlar çekilmeden onaya gönderilemez. POS canlı: ${money.format(liveTotalNow)} • Form: ${money.format(expected)}'
        : null;

    final assignedRegisters = branchCashRegistersAsync.asData?.value ?? const <CashRegister>[];
    final assignedByCode = <String, CashRegister>{
      for (final r in assignedRegisters) _normalizeRegisterCode(r.code): r,
    };
    final assignedCodes = assignedByCode.keys.where((e) => e.isNotEmpty).toSet();
    final posRegsNow = posRegisters.asData?.value;
    final posRegsEffective = posRegsNow == null
        ? null
        : (assignedCodes.isEmpty
            ? posRegsNow
            : posRegsNow.where((e) => assignedCodes.contains(e.registerCode)).toList());
    final posSalesNowTotal = posRegsEffective == null
        ? null
        : posRegsEffective.fold<double>(0, (p, e) => p + e.grossTotal);
    final hasMissingSalesNow = isToday &&
        posSalesNowTotal != null &&
        expected + 0.01 < posSalesNowTotal;

    final posCodes = posRegsNow?.map((e) => e.registerCode).toSet() ?? const <String>{};
    final registerCodes = assignedCodes.isEmpty ? posCodes : assignedCodes;
    final selectedRegisterCode =
        (_selectedRegisterCode != null && registerCodes.contains(_selectedRegisterCode))
            ? _selectedRegisterCode
            : null;

    Widget registerFilterCard() {
      if (registerCodes.length <= 1) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String?>(
            initialValue: selectedRegisterCode,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Tüm Kasalar'),
              ),
              for (final c in (registerCodes.toList()..sort()))
                DropdownMenuItem<String?>(
                  value: c,
                  child: Text(
                    () {
                      final a = assignedByCode[c];
                      if (a == null) return c;
                      return '${a.code} • ${a.name}';
                    }(),
                  ),
                ),
            ],
            onChanged: !canEdit ? null : (v) => setState(() => _selectedRegisterCode = v),
            decoration: const InputDecoration(
              labelText: 'Kasa',
              prefixIcon: Icon(Icons.point_of_sale_outlined),
              filled: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      );
    }

    if (!_prefilledFromPos &&
        canEdit &&
        (item.status == ReconciliationStatus.draft ||
            item.status == ReconciliationStatus.rejected)) {
      final regs = posRegisters.asData?.value;
      final pays = posPayments.asData?.value;
      if (regs != null && pays != null) {
        var changed = false;

        final expectedEmpty =
            _expectedController.text.trim().isEmpty || expected.abs() < 0.0001;
        if (expectedEmpty) {
          final selected = _selectedRegisterCode;
          final effectiveRegs = assignedCodes.isEmpty
              ? regs
              : regs.where((e) => assignedCodes.contains(e.registerCode)).toList();
          final sum = selected == null
              ? effectiveRegs.fold<double>(0, (prev, e) => prev + e.grossTotal)
              : (effectiveRegs.where((e) => e.registerCode == selected).firstOrNull?.grossTotal ?? 0);
          if (sum.abs() > 0.0001) {
            _expectedController.text = sum.toStringAsFixed(2);
            changed = true;
          }
        }

        final hasAnyPayment = _paymentControllers.values.any((c) {
          final v = _parseMoney(c.text);
          return v.abs() > 0.0001;
        });
        if (!hasAnyPayment) {
          final pts = paymentTypes.where((e) => (e.code ?? '').trim().isNotEmpty).toList();
          if (pts.isNotEmpty) {
            final totals = <String, double>{};
            for (final r in pays) {
              if (assignedCodes.isNotEmpty && !assignedCodes.contains(r.registerCode)) {
                continue;
              }
              if (_selectedRegisterCode != null && r.registerCode != _selectedRegisterCode) {
                continue;
              }
              final key = r.paymentCode.trim().toLowerCase();
              if (key.isEmpty) continue;
              totals[key] = (totals[key] ?? 0) + r.amount;
            }
            for (final p in pts) {
              final codeKey = (p.code ?? '').trim().toLowerCase();
              final amount = totals[codeKey];
              if (amount != null) {
                _paymentControllers[p.id]?.text = amount.toStringAsFixed(2);
                changed = true;
              }
            }
          }
        }

        if (changed) {
          _prefilledFromPos = true;
          Future.microtask(() {
            if (mounted) setState(() {});
          });
        }
      }
    }

    Widget productsTab() {
      final productsCard = posProducts.when(
        data: (items) {
          if (items.isEmpty) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('POS ürün satışı bulunamadı.'),
              ),
            );
          }
          final overall = items.fold(0.0, (p, e) => p + e.grossTotal);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shopping_bag_outlined),
                      const SizedBox(width: 8),
                      Text(
                        _selectedRegisterCode == null
                            ? 'POS Ürün Satışları'
                            : 'POS Ürün Satışları (${_selectedRegisterCode!})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Chip(label: Text(money.format(overall))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTableTheme(
                      data: DataTableThemeData(
                        headingRowColor: WidgetStatePropertyAll(
                          Theme.of(context).colorScheme.primaryContainer,
                        ),
                        headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Kod')),
                          DataColumn(label: Text('Ürün')),
                          DataColumn(label: Text('Adet')),
                          DataColumn(label: Text('Ciro')),
                        ],
                        rows: [
                          for (final r in items.take(80))
                            DataRow(
                              cells: [
                                DataCell(Text(r.productCode)),
                                DataCell(Text(r.productName)),
                                DataCell(Text(r.quantity.toStringAsFixed(2))),
                                DataCell(Text(money.format(r.grossTotal))),
                              ],
                            ),
                          DataRow(
                            cells: [
                              const DataCell(Text('')),
                              const DataCell(Text('Toplam')),
                              const DataCell(Text('')),
                              DataCell(Text(money.format(overall))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        ),
        error: (e, st) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Hata: $e'),
          ),
        ),
      );

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          registerFilterCard(),
          const SizedBox(height: 12),
          productsCard,
        ],
      );
    }

    String adjustmentLabel(String kind) {
      final v = kind.trim().toLowerCase();
      return switch (v) {
        'discount' => 'İskonto/İndirim',
        'cancel' => 'İptal',
        'iptal' => 'İptal',
        'comp' => 'İkram',
        'ikram' => 'İkram',
        'refund' => 'İade',
        'iade' => 'İade',
        'debt' => 'Borç',
        _ => kind,
      };
    }

    Widget adjustmentsCard({
      required String title,
      required IconData icon,
      required Set<String> allowedKinds,
      required String emptyText,
    }) {
      return posAdjustments.when(
        data: (items) {
          final filtered = items
              .where((e) => allowedKinds.contains(e.kind.trim().toLowerCase()))
              .toList()
            ..sort((a, b) => a.kind.compareTo(b.kind));

          if (filtered.isEmpty) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(emptyText),
              ),
            );
          }

          final totalAmount = filtered.fold<double>(0, (p, e) => p + e.amount);
          final totalCount = filtered.fold<int>(0, (p, e) => p + e.count);

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(icon),
                      const SizedBox(width: 8),
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      Chip(label: Text('${totalCount} adet')),
                      const SizedBox(width: 8),
                      Chip(label: Text(money.format(totalAmount))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTableTheme(
                      data: DataTableThemeData(
                        headingRowColor: WidgetStatePropertyAll(
                          Theme.of(context).colorScheme.primaryContainer,
                        ),
                        headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Tür')),
                          DataColumn(label: Text('Adet')),
                          DataColumn(label: Text('Tutar')),
                        ],
                        rows: [
                          for (final r in filtered)
                            DataRow(
                              cells: [
                                DataCell(Text(adjustmentLabel(r.kind))),
                                DataCell(Text(r.count.toString())),
                                DataCell(Text(money.format(r.amount))),
                              ],
                            ),
                          DataRow(
                            cells: [
                              const DataCell(Text('Toplam')),
                              DataCell(Text(totalCount.toString())),
                              DataCell(Text(money.format(totalAmount))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        ),
        error: (e, st) {
          final dio = e is DioException ? e : null;
          final status = dio?.response?.statusCode;
          final message = status == 404
              ? 'Sunucu bu raporu desteklemiyor (404). Server güncel değilse yeniden başlatın.'
              : 'Hata: $e';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(message),
            ),
          );
        },
      );
    }

    Widget adjustmentsTab({
      required String title,
      required IconData icon,
      required Set<String> allowedKinds,
      required String emptyText,
    }) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          registerFilterCard(),
          const SizedBox(height: 12),
          adjustmentsCard(
            title: title,
            icon: icon,
            allowedKinds: allowedKinds,
            emptyText: emptyText,
          ),
        ],
      );
    }

    Widget cancelledItemsCard() {
      final fmt = DateFormat('HH:mm', 'tr_TR');
      return posCancelledItems.when(
        data: (items) {
          if (items.isEmpty) {
            return const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('İptal/ikram/iade kalem detayı bulunamadı.'),
              ),
            );
          }
          final rows = [...items]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.playlist_remove_outlined),
                      const SizedBox(width: 8),
                      Text('Kalem Detayı', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      Chip(label: Text('${rows.length} satır')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTableTheme(
                      data: DataTableThemeData(
                        headingRowColor: WidgetStatePropertyAll(
                          Theme.of(context).colorScheme.primaryContainer,
                        ),
                        headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Kasa')),
                          DataColumn(label: Text('Saat')),
                          DataColumn(label: Text('Personel')),
                          DataColumn(label: Text('Tür')),
                          DataColumn(label: Text('Ürün')),
                          DataColumn(label: Text('Adet')),
                          DataColumn(label: Text('Tutar')),
                          DataColumn(label: Text('Açıklama')),
                        ],
                        rows: [
                          for (final r in rows.take(200))
                            DataRow(
                              cells: [
                                DataCell(Text(r.registerCode)),
                                DataCell(Text(fmt.format(r.occurredAt))),
                                DataCell(Text(r.cancelledByName ?? '')),
                                DataCell(Text(adjustmentLabel(r.type))),
                                DataCell(Text(r.productName)),
                                DataCell(Text(r.quantity.toStringAsFixed(2))),
                                DataCell(Text(money.format(r.total))),
                                DataCell(Text(r.reason ?? '')),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        ),
        error: (e, st) {
          final dio = e is DioException ? e : null;
          final status = dio?.response?.statusCode;
          final message = status == 404
              ? 'Sunucu iptal detay endpointini bulamadı (404). Server güncel değilse yeniden başlatın.'
              : 'Hata: $e';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(message),
            ),
          );
        },
      );
    }

    String groupLabel(String code) {
      final v = code.trim().toLowerCase();
      return switch (v) {
        'adisyon' => 'Adisyon',
        'paket' => 'Paket',
        'hizli' => 'Hızlı',
        _ => code,
      };
    }

    Widget groupsTab() {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          registerFilterCard(),
          const SizedBox(height: 12),
          posGroups.when(
            data: (items) {
              if (items.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('POS grup satış verisi bulunamadı.'),
                  ),
                );
              }
              final rows = [...items]..sort((a, b) => a.groupCode.compareTo(b.groupCode));
              final totalOrders =
                  rows.fold<int>(0, (p, e) => p + e.orderCount);
              final totalGross =
                  rows.fold<double>(0, (p, e) => p + e.grossTotal);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.category_outlined),
                          const SizedBox(width: 8),
                          Text('Grup Satış', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          Chip(label: Text('${totalOrders} adet')),
                          const SizedBox(width: 8),
                          Chip(label: Text(money.format(totalGross))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTableTheme(
                          data: DataTableThemeData(
                            headingRowColor: WidgetStatePropertyAll(
                              Theme.of(context).colorScheme.primaryContainer,
                            ),
                            headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Grup')),
                              DataColumn(label: Text('Adet')),
                              DataColumn(label: Text('Ciro')),
                            ],
                            rows: [
                              for (final r in rows)
                                DataRow(
                                  cells: [
                                    DataCell(Text(groupLabel(r.groupCode))),
                                    DataCell(Text(r.orderCount.toString())),
                                    DataCell(Text(money.format(r.grossTotal))),
                                  ],
                                ),
                              DataRow(
                                cells: [
                                  const DataCell(Text('Toplam')),
                                  DataCell(Text(totalOrders.toString())),
                                  DataCell(Text(money.format(totalGross))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            ),
            error: (e, st) {
              final dio = e is DioException ? e : null;
              final status = dio?.response?.statusCode;
              final message = status == 404
                  ? 'Sunucu bu raporu desteklemiyor (404). Server güncel değilse yeniden başlatın.'
                  : 'Hata: $e';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(message),
                ),
              );
            },
          ),
        ],
      );
    }

    Widget mainTab() {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isToday && canEdit) ...[
            Card(
              color: hasMissingSalesNow
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      hasMissingSalesNow ? Icons.warning_amber_outlined : Icons.info_outline,
                      color: hasMissingSalesNow
                          ? Theme.of(context).colorScheme.onErrorContainer
                          : Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bugün için icmal',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: hasMissingSalesNow
                                      ? Theme.of(context).colorScheme.onErrorContainer
                                      : Theme.of(context).colorScheme.onTertiaryContainer,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            hasMissingSalesNow
                                ? 'Gün bitmeden icmal yapılmış olabilir. Şu anki POS ciro (${money.format(posSalesNowTotal)}) form cirosundan (${money.format(expected)}) yüksek. Eksik satış olabilir. Satışı Çek ile güncelle.'
                                : 'Gün bitmeden icmal yapılmış olabilir. Satışlar gün içinde artabilir. Satışı Çek ile güncel POS verisini alabilirsiniz.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: hasMissingSalesNow
                                      ? Theme.of(context).colorScheme.onErrorContainer
                                      : Theme.of(context).colorScheme.onTertiaryContainer,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, c) {
              final isNarrow = c.maxWidth < 920;
              final cards = Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: isNarrow ? c.maxWidth : (c.maxWidth - 36) / 4,
                    child: _MetricCard(
                      title: 'Şube Satış Tutarı (Ciro)',
                      value: money.format(expected),
                      icon: Icons.receipt_long_outlined,
                      tone: MetricTone.primary,
                    ),
                  ),
                  SizedBox(
                    width: isNarrow ? c.maxWidth : (c.maxWidth - 36) / 4,
                    child: _MetricCard(
                      title: 'Ödeme Toplamı',
                      value: money.format(paymentTotal),
                      icon: Icons.account_balance_wallet_outlined,
                      tone: MetricTone.success,
                    ),
                  ),
                  SizedBox(
                    width: isNarrow ? c.maxWidth : (c.maxWidth - 36) / 4,
                    child: _MetricCard(
                      title: 'Masraf Toplamı',
                      value: money.format(expenseTotal),
                      icon: Icons.receipt_outlined,
                      tone: MetricTone.warning,
                    ),
                  ),
                  SizedBox(
                    width: isNarrow ? c.maxWidth : (c.maxWidth - 36) / 4,
                    child: _MetricCard(
                      title: 'Fark',
                      value: money.format(diff),
                      icon: Icons.compare_arrows_outlined,
                      tone: showDiff ? MetricTone.danger : MetricTone.neutral,
                    ),
                  ),
                ],
              );
              return cards;
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 980;
                  final expectedField = TextFormField(
                    controller: _expectedController,
                    enabled: canEdit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Şube Satış Tutarı (Ciro)',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                      suffixText: '₺',
                      filled: true,
                      border: OutlineInputBorder(),
                    ),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.right,
                    onTap: () {
                      _expectedController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _expectedController.text.length,
                      );
                    },
                  );

                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: canEdit
                            ? () async {
                                if (!AppConfig.hasApi) return;
                                if (_isPullingSales) return;
                                try {
                                  setState(() => _isPullingSales = true);
                                  final dio = ref.read(dioProvider);
                                  final day = item.date.toIso8601String().substring(0, 10);
                                  await dio.post<Map<String, dynamic>>(
                                    '/pos/pull/branch-daily',
                                    data: {
                                      'branchId': item.branchId,
                                      'businessDate': day,
                                      'businessDayStartHour': businessDayStartHour,
                                    },
                                  );

                                  _prefilledFromPos = false;

                                  final salesArgs = (branchId: item.branchId, date: item.date);
                                  final regs = await ref.refresh(
                                    posRegisterDailySalesProvider(salesArgs).future,
                                  );
                                  ref.invalidate(
                                    posRegisterDailyPaymentsProvider(
                                      (branchId: item.branchId, date: item.date),
                                    ),
                                  );
                                  ref.invalidate(
                                    posDailyProductSalesProvider(
                                      (branchId: item.branchId, date: item.date, registerCode: _selectedRegisterCode),
                                    ),
                                  );
                                  ref.invalidate(
                                    posDailyAdjustmentsProvider(
                                      (branchId: item.branchId, date: item.date, registerCode: _selectedRegisterCode),
                                    ),
                                  );
                                  ref.invalidate(
                                    posDailySalesGroupsProvider(
                                      (branchId: item.branchId, date: item.date, registerCode: _selectedRegisterCode),
                                    ),
                                  );

                                  final selected = _selectedRegisterCode;
                                  final effectiveRegs = assignedCodes.isEmpty
                                      ? regs
                                      : regs.where((e) => assignedCodes.contains(e.registerCode)).toList();
                                  final total = selected == null
                                      ? effectiveRegs.fold<double>(0, (prev, e) => prev + e.grossTotal)
                                      : (effectiveRegs
                                              .where((e) => e.registerCode == selected)
                                              .firstOrNull
                                              ?.grossTotal ??
                                          0);

                                  _expectedController.text = total.toStringAsFixed(2);
                                  await ref
                                      .read(reconciliationsProvider.notifier)
                                      .updateExpectedSalesTotal(
                                        id: item.id,
                                        expectedSalesTotal: total,
                                      );

                                  ref.invalidate(
                                    posDailyProductSalesProvider(
                                      (
                                        branchId: item.branchId,
                                        date: item.date,
                                        registerCode: _selectedRegisterCode,
                                      ),
                                    ),
                                  );

                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Satış çekildi.')),
                                  );
                                  setState(() {});
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Hata: $e')),
                                  );
                                } finally {
                                  if (mounted) setState(() => _isPullingSales = false);
                                }
                              }
                            : null,
                        icon: _isPullingSales
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download),
                        label: Text(_isPullingSales ? 'Çekiliyor...' : 'Satışı Çek'),
                      ),
                      OutlinedButton.icon(
                        onPressed: canEdit
                            ? () {
                                final pts = paymentTypes
                                    .where((e) => (e.code ?? '').trim().isNotEmpty)
                                    .toList();
                                if (pts.isEmpty) return;
                                posPayments.whenData((rows) {
                                  final totals = <String, double>{};
                                  for (final r in rows) {
                                    if (assignedCodes.isNotEmpty &&
                                        !assignedCodes.contains(r.registerCode)) {
                                      continue;
                                    }
                                    if (_selectedRegisterCode != null &&
                                        r.registerCode != _selectedRegisterCode) {
                                      continue;
                                    }
                                    final key = r.paymentCode.trim().toLowerCase();
                                    if (key.isEmpty) continue;
                                    totals[key] = (totals[key] ?? 0) + r.amount;
                                  }
                                  for (final p in pts) {
                                    final codeKey = (p.code ?? '').trim().toLowerCase();
                                    final amount = totals[codeKey];
                                    if (amount != null) {
                                      _paymentControllers[p.id]?.text =
                                          amount.toStringAsFixed(2);
                                    }
                                  }
                                  setState(() {});
                                });
                              }
                            : null,
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('POS Ödemeleri'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => DefaultTabController.of(context).animateTo(1),
                        icon: const Icon(Icons.shopping_bag_outlined),
                        label: const Text('Ürün Satışları'),
                      ),
                    ],
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isPullingSales) ...[
                        const LinearProgressIndicator(minHeight: 3),
                        const SizedBox(height: 12),
                      ],
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: expectedField),
                            const SizedBox(width: 12),
                            actions,
                          ],
                        )
                      else ...[
                        expectedField,
                        const SizedBox(height: 12),
                        actions,
                      ],
                      if (requiresAttachments) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Farklılık var. İmzalı evrak ve sayım fişi eklenmeli.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          posRegisters.when(
            data: (items) {
              if (items.isEmpty) return const SizedBox.shrink();
              final posCodes = items.map((e) => e.registerCode).toSet();
              final registerCodes = assignedCodes.isEmpty ? posCodes : assignedCodes;

              if (registerCodes.length == 1) {
                final only = registerCodes.first;
                if (_selectedRegisterCode != only) {
                  Future.microtask(() {
                    if (mounted) setState(() => _selectedRegisterCode = only);
                  });
                }
              }

              final selected =
                  (_selectedRegisterCode != null && registerCodes.contains(_selectedRegisterCode))
                      ? _selectedRegisterCode
                      : null;
              final effectiveItems = assignedCodes.isEmpty
                  ? items
                  : items.where((e) => assignedCodes.contains(e.registerCode)).toList();
              final shown = selected == null
                  ? effectiveItems
                  : effectiveItems.where((e) => e.registerCode == selected).toList();
              final total = shown.fold(0.0, (p, e) => p + e.grossTotal);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.point_of_sale_outlined),
                          const SizedBox(width: 8),
                          Text('POS Kasa Bazlı Ciro', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          Chip(label: Text(money.format(total))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (registerCodes.length > 1) ...[
                        DropdownButtonFormField<String?>(
                          initialValue: selected,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Tüm Kasalar'),
                            ),
                            for (final c in (registerCodes.toList()..sort()))
                              DropdownMenuItem<String?>(
                                value: c,
                                child: Text(
                                  () {
                                    final a = assignedByCode[c];
                                    if (a == null) return c;
                                    return '${a.code} • ${a.name}';
                                  }(),
                                ),
                              ),
                          ],
                          onChanged: !canEdit
                              ? null
                              : (v) {
                                  setState(() => _selectedRegisterCode = v);
                                },
                          decoration: const InputDecoration(labelText: 'Kasa'),
                        ),
                        const SizedBox(height: 8),
                      ],
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTableTheme(
                          data: DataTableThemeData(
                            headingRowColor: WidgetStatePropertyAll(
                              Theme.of(context).colorScheme.primaryContainer,
                            ),
                            headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Kasa')),
                              DataColumn(label: Text('Ciro')),
                            ],
                            rows: [
                              for (final r in shown)
                                DataRow(
                                  cells: [
                                    DataCell(Text(r.registerCode)),
                                    DataCell(Text(money.format(r.grossTotal))),
                                  ],
                                ),
                              DataRow(
                                cells: [
                                  const DataCell(Text('Toplam')),
                                  DataCell(Text(money.format(total))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          posPayments.when(
            data: (items) {
              if (items.isEmpty) return const SizedBox.shrink();
              final byBranchRegisters = assignedCodes.isEmpty
                  ? items
                  : items.where((e) => assignedCodes.contains(e.registerCode)).toList();
              final filtered = _selectedRegisterCode == null
                  ? byBranchRegisters
                  : byBranchRegisters.where((e) => e.registerCode == _selectedRegisterCode).toList();
              final totals = <String, double>{};
              for (final r in filtered) {
                final key = r.paymentCode.trim();
                if (key.isEmpty) continue;
                totals[key] = (totals[key] ?? 0) + r.amount;
              }
              final sortedKeys = totals.keys.toList()..sort((a, b) => a.compareTo(b));
              final overall = totals.values.fold(0.0, (p, e) => p + e);
              final ptByCode = <String, PaymentType>{
                for (final p in paymentTypes)
                  if ((p.code ?? '').trim().isNotEmpty) p.code!.trim().toLowerCase(): p,
              };

              final palette = <Color>[
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.tertiary,
                Theme.of(context).colorScheme.secondary,
                Theme.of(context).colorScheme.error,
                Theme.of(context).colorScheme.primaryContainer,
              ];
              final segments = <_DonutSegment>[];
              final pairs = [
                for (final k in sortedKeys)
                  MapEntry(k, totals[k] ?? 0),
              ]..sort((a, b) => b.value.compareTo(a.value));
              final top = pairs.take(5).toList();
              final otherTotal = pairs.skip(5).fold<double>(0, (p, e) => p + e.value);
              for (var i = 0; i < top.length; i++) {
                final k = top[i].key;
                segments.add(
                  _DonutSegment(
                    label: k,
                    value: top[i].value,
                    color: palette[i % palette.length],
                  ),
                );
              }
              if (otherTotal > 0.0001) {
                segments.add(
                  _DonutSegment(
                    label: 'Diğer',
                    value: otherTotal,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                );
              }

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final isWide = c.maxWidth >= 980;
                      final header = Row(
                        children: [
                          const Icon(Icons.pie_chart_outline),
                          const SizedBox(width: 8),
                          Text(
                            _selectedRegisterCode == null
                                ? 'POS Ödeme Dağılımı'
                                : 'POS Ödeme Dağılımı (${_selectedRegisterCode!})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          Chip(label: Text(money.format(overall))),
                        ],
                      );

                      final donut = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 180,
                            child: _DonutChart(segments: segments),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              for (final s in segments)
                                _LegendChip(
                                  color: s.color,
                                  label: () {
                                    final p = ptByCode[s.label.trim().toLowerCase()];
                                    return p == null ? s.label : p.name;
                                  }(),
                                ),
                            ],
                          ),
                        ],
                      );

                      final table = SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTableTheme(
                          data: DataTableThemeData(
                            headingRowColor: WidgetStatePropertyAll(
                              Theme.of(context).colorScheme.primaryContainer,
                            ),
                            headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Ödeme Tipi')),
                              DataColumn(label: Text('Tutar')),
                              DataColumn(label: Text('Oran')),
                            ],
                            rows: [
                              for (final k in sortedKeys)
                                () {
                                  final amount = totals[k] ?? 0;
                                  final pct = overall.abs() < 0.0001 ? 0 : (amount / overall) * 100;
                                  final p = ptByCode[k.trim().toLowerCase()];
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(p?.name ?? k)),
                                      DataCell(Text(money.format(amount))),
                                      DataCell(Text('${pct.toStringAsFixed(1)}%')),
                                    ],
                                  );
                                }(),
                              DataRow(
                                cells: [
                                  const DataCell(Text('Toplam')),
                                  DataCell(Text(money.format(overall))),
                                  const DataCell(Text('100%')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          const SizedBox(height: 12),
                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 360, child: donut),
                                const SizedBox(width: 12),
                                Expanded(child: table),
                              ],
                            )
                          else ...[
                            donut,
                            const SizedBox(height: 12),
                            table,
                          ],
                        ],
                      );
                    },
                  ),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, st) => const SizedBox.shrink(),
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
                      const Icon(Icons.receipt_outlined),
                      const SizedBox(width: 8),
                      Text(
                        'Kredi Kartı Günsonu',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: (!canEdit || _isUploadingEndOfDay)
                            ? null
                            : () async {
                                if (!AppConfig.hasApi) return;
                                final picked = await FilePicker.pickFiles(
                                  allowMultiple: false,
                                  withData: true,
                                  type: FileType.image,
                                );
                                if (picked == null || picked.files.isEmpty) return;
                                final f = picked.files.first;
                                final bytes = f.bytes;
                                if (bytes == null || bytes.isEmpty) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Dosya okunamadı.')),
                                  );
                                  return;
                                }

                                try {
                                  setState(() => _isUploadingEndOfDay = true);
                                  final dio = ref.read(dioProvider);
                                  final form = FormData.fromMap({
                                    'file': MultipartFile.fromBytes(bytes, filename: f.name),
                                  });
                                  final res = await dio.post<Map<String, dynamic>>(
                                    '/cash-reconciliations/${item.id}/end-of-day/card-from-image',
                                    data: form,
                                  );
                                  final data = res.data ?? const {};
                                  final rawTotal = data['cardTotal'];
                                  final cardTotal = rawTotal is num
                                      ? rawTotal.toDouble()
                                      : double.tryParse((rawTotal ?? '').toString()) ?? 0;
                                  final rawFast = data['fastTotal'];
                                  final fastTotal = rawFast is num
                                      ? rawFast.toDouble()
                                      : double.tryParse((rawFast ?? '').toString()) ?? 0;

                                  final cardType = paymentTypes.firstWhere(
                                    (p) {
                                      final name = p.name.toLowerCase();
                                      final code = (p.code ?? '').toLowerCase();
                                      return name.contains('kredi') ||
                                          name.contains('kart') ||
                                          code.contains('card') ||
                                          code.contains('kredi') ||
                                          code.contains('kk');
                                    },
                                    orElse: () => paymentTypes.first,
                                  );
                                  _paymentControllers[cardType.id]?.text =
                                      cardTotal.toStringAsFixed(2);

                                  PaymentType? fastType;
                                  for (final p in paymentTypes) {
                                    final name = p.name.toLowerCase();
                                    final code = (p.code ?? '').toLowerCase();
                                    if (name.contains('fast') || code.contains('fast')) {
                                      fastType = p;
                                      break;
                                    }
                                  }
                                  if (fastType != null && fastTotal.abs() > 0.0001) {
                                    _paymentControllers[fastType.id]?.text =
                                        fastTotal.toStringAsFixed(2);
                                  }

                                  final updatedPayments = <MoneyLine>[];
                                  for (final p in paymentTypes) {
                                    final amount = _parseMoney(_paymentControllers[p.id]?.text ?? '');
                                    if (amount.abs() > 0.0001) {
                                      updatedPayments.add(MoneyLine(typeId: p.id, amount: amount));
                                    }
                                  }
                                  final updatedExpenses = <MoneyLine>[];
                                  for (final e in expenseTypes) {
                                    final amount = _parseMoney(_expenseControllers[e.id]?.text ?? '');
                                    if (amount.abs() > 0.0001) {
                                      updatedExpenses.add(MoneyLine(typeId: e.id, amount: amount));
                                    }
                                  }
                                  final updated = item.copyWith(
                                    expectedSalesTotal: _parseMoney(_expectedController.text),
                                    paymentLines: updatedPayments,
                                    expenseLines: updatedExpenses,
                                  );
                                  await ref.read(reconciliationsProvider.notifier).save(updated);
                                  ref.invalidate(endOfDayReportsProvider(item.id));
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        fastType != null && fastTotal.abs() > 0.0001
                                            ? 'Okundu: ${money.format(cardTotal)} (${cardType.name}) • FAST: ${money.format(fastTotal)}'
                                            : 'Okundu: ${money.format(cardTotal)} (${cardType.name})',
                                      ),
                                    ),
                                  );
                                  setState(() {});
                                } on DioException catch (e) {
                                  final status = e.response?.statusCode;
                                  final data = e.response?.data;
                                  if (context.mounted) {
                                    String msg = 'Günsonu okunamadı: $e';
                                    if (data is Map<String, dynamic>) {
                                      final err = (data['error'] ?? '').toString();
                                      final requestId = (data['requestId'] ?? '').toString().trim();
                                      if (err == 'DATE_MISMATCH') {
                                        msg =
                                            'Tarih uyuşmuyor. Rapor: ${data['reportDate']} • Form: ${data['expectedDate']}';
                                      } else if (err == 'DATE_NOT_FOUND') {
                                        msg = 'Raporda tarih okunamadı.';
                                      } else if (err == 'DATE_REQUIRED') {
                                        msg = 'Form tarihi okunamadı. Sayfayı yenileyip tekrar deneyin.';
                                      } else if (err == 'EOD_ALREADY_USED') {
                                        msg = 'Bu günsonu raporu başka bir şubeye eklenmiş. Bu şube için kullanılamaz.';
                                      } else if (err == 'FILE_TOO_LARGE') {
                                        msg = 'Dosya çok büyük. Daha küçük bir görsel ile tekrar deneyin.';
                                      } else if (err == 'OCR_INTERNAL') {
                                        final detail = (data['message'] ?? '').toString().trim();
                                        msg = detail.isNotEmpty ? 'Günsonu okunamadı: $detail' : 'Günsonu okunamadı.';
                                      } else if (err.isNotEmpty) {
                                        msg = 'Günsonu okunamadı: $err';
                                      }
                                      if (requestId.isNotEmpty) {
                                        msg = '$msg (Kod: $requestId)';
                                      }
                                    } else if (status == 404) {
                                      msg = 'Sunucu günsonu OCR endpointini bulamadı (404).';
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg)),
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => _isUploadingEndOfDay = false);
                                }
                              },
                        icon: _isUploadingEndOfDay
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.document_scanner_outlined),
                        label: Text(_isUploadingEndOfDay ? 'Okunuyor...' : 'Rapor Yükle'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  endOfDayReports.when(
                    data: (rows) {
                      if (rows.isEmpty) {
                        return const Text('Henüz günsonu raporu eklenmedi.');
                      }
                      final fmt = DateFormat('yyyy-MM-dd HH:mm', 'tr_TR');
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTableTheme(
                          data: DataTableThemeData(
                            headingRowColor: WidgetStatePropertyAll(
                              Theme.of(context).colorScheme.primaryContainer,
                            ),
                            headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Rapor Tarihi')),
                              DataColumn(label: Text('Ünvan')),
                              DataColumn(label: Text('İşyeri No')),
                              DataColumn(label: Text('Terminal No')),
                              DataColumn(label: Text('Kredi Kartı')),
                              DataColumn(label: Text('FAST')),
                              DataColumn(label: Text('Eklendi')),
                            ],
                            rows: [
                              for (final r in rows.take(30))
                                DataRow(
                                  cells: [
                                    DataCell(Text(DateFormat('yyyy-MM-dd', 'tr_TR').format(r.reportDate))),
                                    DataCell(Text(r.merchantTitle ?? '')),
                                    DataCell(Text(r.workplaceNo ?? '')),
                                    DataCell(Text(r.terminalNo ?? '')),
                                    DataCell(Text(money.format(r.cardTotal))),
                                    DataCell(Text(money.format(r.fastTotal))),
                                    DataCell(Text(fmt.format(r.createdAt))),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (e, st) => Text('Hata: $e'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined),
              const SizedBox(width: 8),
              Text('Ödemeler', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Chip(label: Text('Toplam: ${money.format(paymentTotal)}')),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  final itemWidth = isWide ? 360.0 : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final p in paymentTypes)
                        SizedBox(
                          width: itemWidth,
                          child: TextFormField(
                            controller: _paymentControllers[p.id],
                            enabled: canEdit,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: p.name,
                              prefixIcon: const Icon(Icons.payments_outlined),
                              suffixText: '₺',
                              filled: true,
                              border: const OutlineInputBorder(),
                            ),
                            textAlign: TextAlign.right,
                            onTap: () {
                              final c = _paymentControllers[p.id];
                              if (c == null) return;
                              c.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: c.text.length,
                              );
                            },
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.receipt_outlined),
              const SizedBox(width: 8),
              Text('Masraflar', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Chip(label: Text('Toplam: ${money.format(expenseTotal)}')),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  final itemWidth = isWide ? 360.0 : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final e in expenseTypes)
                        SizedBox(
                          width: itemWidth,
                          child: TextFormField(
                            controller: _expenseControllers[e.id],
                            enabled: canEdit,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: e.name,
                              prefixIcon: const Icon(Icons.remove_circle_outline),
                              suffixText: '₺',
                              filled: true,
                              border: const OutlineInputBorder(),
                            ),
                            textAlign: TextAlign.right,
                            onTap: () {
                              final c = _expenseControllers[e.id];
                              if (c == null) return;
                              c.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: c.text.length,
                              );
                            },
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Evrak', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: canEdit
                        ? () async {
                            final kind = await _pickAttachmentKind(context);
                            if (kind == null) return;
                            final picked = await FilePicker.pickFiles(
                              withData: false,
                              allowMultiple: true,
                            );
                            if (picked == null) return;
                            for (final f in picked.files) {
                              await ref.read(reconciliationsProvider.notifier).addAttachment(
                                    reconciliationId: item.id,
                                    kind: kind,
                                    fileName: f.name,
                                    mimeType: lookupMimeType(f.name) ?? 'application/octet-stream',
                                    sizeBytes: f.size,
                                  );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Dosya Ekle'),
                  ),
                  const SizedBox(height: 12),
                  if (item.attachments.isEmpty)
                    const Text('Evrak eklenmedi.')
                  else
                    Column(
                      children: [
                        for (final a in item.attachments)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.insert_drive_file_outlined),
                            title: Text(a.fileName),
                            subtitle: Text(
                              '${attachmentKindLabel(a.kind)} • ${a.mimeType} • ${(a.sizeBytes / 1024).toStringAsFixed(1)} KB',
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (role == UserRole.manager && item.status == ReconciliationStatus.submitted)
            _ManagerActions(itemId: item.id)
          else
            _UserActions(
              item: item,
              canEdit: canEdit,
              canSubmit: submitBlockedReason == null,
              submitBlockedReason: submitBlockedReason,
              expected: expected,
              paymentTypes: paymentTypes,
              expenseTypes: expenseTypes,
              paymentControllers: _paymentControllers,
              expenseControllers: _expenseControllers,
            ),
        ],
      );
    }

    return Scaffold(
      body: DefaultTabController(
        length: 6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Geri',
                        onPressed: () => context.go('/reconciliations'),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Text('Kasa İcmal', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(width: 12),
                      Chip(label: Text(_statusLabel(item.status))),
                      const Spacer(),
                      Chip(
                        avatar: const Icon(Icons.store_outlined, size: 16),
                        label: Text(branchName),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        avatar: const Icon(Icons.calendar_month_outlined, size: 16),
                        label: Text(dateText),
                      ),
                    ],
                  ),
                  if (submitBlockedReason != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: scheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_outlined, color: scheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                submitBlockedReason,
                                style: TextStyle(color: scheme.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (item.status == ReconciliationStatus.rejected &&
                      (item.rejectionReason?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('Red Nedeni: ${item.rejectionReason}'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: scheme.surface,
              child: TabBar(
                isScrollable: true,
                labelColor: scheme.onSurface,
                unselectedLabelColor: scheme.onSurfaceVariant,
                indicatorColor: scheme.primary,
                tabs: const [
                  Tab(icon: Icon(Icons.receipt_long_outlined), text: 'İcmal'),
                  Tab(icon: Icon(Icons.shopping_bag_outlined), text: 'Ürün Satışları'),
                  Tab(icon: Icon(Icons.undo_outlined), text: 'İptal/İade/İkram'),
                  Tab(icon: Icon(Icons.percent_outlined), text: 'İskonto/İndirim'),
                  Tab(icon: Icon(Icons.credit_score_outlined), text: 'Borç'),
                  Tab(icon: Icon(Icons.category_outlined), text: 'Grup Satış'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  mainTab(),
                  productsTab(),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      registerFilterCard(),
                      const SizedBox(height: 12),
                      adjustmentsCard(
                        title: 'İptal / İade / İkram',
                        icon: Icons.undo_outlined,
                        allowedKinds: const {'cancel', 'refund', 'comp'},
                        emptyText: 'POS iptal/iade/ikram özeti bulunamadı.',
                      ),
                      const SizedBox(height: 12),
                      cancelledItemsCard(),
                    ],
                  ),
                  adjustmentsTab(
                    title: 'İskonto / İndirim',
                    icon: Icons.percent_outlined,
                    allowedKinds: const {'discount'},
                    emptyText: 'POS iskonto/indirim verisi bulunamadı.',
                  ),
                  adjustmentsTab(
                    title: 'Borç',
                    icon: Icons.credit_score_outlined,
                    allowedKinds: const {'debt'},
                    emptyText: 'POS borca atılan verisi bulunamadı.',
                  ),
                  groupsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canEdit(CashReconciliation item, AuthSession? session) {
    if (session == null) return false;
    if (session.role == UserRole.manager) return item.status != ReconciliationStatus.approved;
    if (item.createdByUserId != session.userId) return false;
    return item.status == ReconciliationStatus.draft ||
        item.status == ReconciliationStatus.rejected;
  }

  void _ensureControllers(
    CashReconciliation item,
    List<PaymentType> paymentTypes,
    List<ExpenseType> expenseTypes,
  ) {
    _expectedController.text =
        _expectedController.text.isEmpty ? item.expectedSalesTotal.toStringAsFixed(2) : _expectedController.text;

    final paymentMap = {for (final l in item.paymentLines) l.typeId: l.amount};
    for (final p in paymentTypes) {
      _paymentControllers.putIfAbsent(p.id, () {
        return TextEditingController(
          text: (paymentMap[p.id] ?? 0).toStringAsFixed(2),
        );
      });
    }

    final expenseMap = {for (final l in item.expenseLines) l.typeId: l.amount};
    for (final e in expenseTypes) {
      _expenseControllers.putIfAbsent(e.id, () {
        return TextEditingController(
          text: (expenseMap[e.id] ?? 0).toStringAsFixed(2),
        );
      });
    }
  }

  double _computeTotal<T>(
    List<T> types,
    Map<String, TextEditingController> controllers,
  ) {
    var total = 0.0;
    for (final entry in controllers.entries) {
      total += _parseMoney(entry.value.text);
    }
    return total;
  }

  double _parseMoney(String raw) {
    final normalized = raw.replaceAll(' ', '').replaceAll(',', '.').trim();
    return double.tryParse(normalized) ?? 0;
  }

  String _statusLabel(ReconciliationStatus status) {
    return switch (status) {
      ReconciliationStatus.draft => 'Taslak',
      ReconciliationStatus.submitted => 'Onay Bekliyor',
      ReconciliationStatus.approved => 'Onaylandı',
      ReconciliationStatus.rejected => 'Reddedildi',
    };
  }

  Future<AttachmentKind?> _pickAttachmentKind(BuildContext context) async {
    return showDialog<AttachmentKind>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Evrak Türü'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(AttachmentKind.countSlip),
              child: const Text('Para sayım fişi'),
            ),
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(context).pop(AttachmentKind.signedStatement),
              child: const Text('İmzalı tutanak'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(AttachmentKind.other),
              child: const Text('Diğer'),
            ),
          ],
        );
      },
    );
  }
}

class _UserActions extends ConsumerWidget {
  const _UserActions({
    required this.item,
    required this.canEdit,
    required this.canSubmit,
    required this.submitBlockedReason,
    required this.expected,
    required this.paymentTypes,
    required this.expenseTypes,
    required this.paymentControllers,
    required this.expenseControllers,
  });

  final CashReconciliation item;
  final bool canEdit;
  final bool canSubmit;
  final String? submitBlockedReason;
  final double expected;
  final List<PaymentType> paymentTypes;
  final List<ExpenseType> expenseTypes;
  final Map<String, TextEditingController> paymentControllers;
  final Map<String, TextEditingController> expenseControllers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canEdit) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Bu kayıtta düzenleme yetkiniz yok.'),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (submitBlockedReason != null) ...[
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.block, color: scheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      submitBlockedReason!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  final updated = _buildUpdated(item);
                  await ref.read(reconciliationsProvider.notifier).save(updated);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Kaydedildi.')),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text('Kaydet'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: !canSubmit
                    ? null
                    : () async {
                        final updated = _buildUpdated(item);
                        final hasDiff =
                            (updated.paymentTotal - updated.expectedSalesTotal).abs() > 0.01;
                        if (hasDiff) {
                          final missing = missingRequiredAttachmentKinds(updated);
                          if (missing.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Farklılık varsa evrak eklenmeli: ${missing.map(attachmentKindLabel).join(', ')}',
                                ),
                              ),
                            );
                            return;
                          }
                        }
                        await ref.read(reconciliationsProvider.notifier).save(updated);
                        await ref.read(reconciliationsProvider.notifier).submit(updated.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Onaya gönderildi.')),
                        );
                      },
                icon: const Icon(Icons.send),
                label: const Text('Onaya Gönder'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  CashReconciliation _buildUpdated(CashReconciliation base) {
    final payments = <MoneyLine>[];
    for (final p in paymentTypes) {
      final amount = _parseMoney(paymentControllers[p.id]?.text ?? '');
      if (amount.abs() > 0.0001) {
        payments.add(MoneyLine(typeId: p.id, amount: amount));
      }
    }

    final expenses = <MoneyLine>[];
    for (final e in expenseTypes) {
      final amount = _parseMoney(expenseControllers[e.id]?.text ?? '');
      if (amount.abs() > 0.0001) {
        expenses.add(MoneyLine(typeId: e.id, amount: amount));
      }
    }

    return base.copyWith(
      expectedSalesTotal: expected,
      paymentLines: payments,
      expenseLines: expenses,
    );
  }

  double _parseMoney(String raw) {
    final normalized = raw.replaceAll(' ', '').replaceAll(',', '.').trim();
    return double.tryParse(normalized) ?? 0;
  }
}

class _ManagerActions extends ConsumerStatefulWidget {
  const _ManagerActions({required this.itemId});

  final String itemId;

  @override
  ConsumerState<_ManagerActions> createState() => _ManagerActionsState();
}

class _ManagerActionsState extends ConsumerState<_ManagerActions> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final managerId = session?.userId;
    final items = ref.watch(reconciliationsProvider);
    final item = items.where((e) => e.id == widget.itemId).firstOrNull;

    if (item == null || managerId == null) {
      return const SizedBox.shrink();
    }

    final hasDiff = item.difference.abs() > 0.01;
    final missing = hasDiff ? missingRequiredAttachmentKinds(item) : const <AttachmentKind>[];
    final missingAttachment = missing.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (missingAttachment)
              Text(
                'Fark var. Onay için evraklar tamamlanmalı: ${missing.map(attachmentKindLabel).join(', ')}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: missingAttachment
                        ? null
                        : () async {
                            await ref.read(reconciliationsProvider.notifier).approve(item.id);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Onaylandı.')),
                            );
                          },
                    icon: const Icon(Icons.verified),
                    label: const Text('Onayla'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final reason = await _rejectDialog(context);
                      if (!context.mounted) return;
                      if (reason == null || reason.trim().isEmpty) return;
                      await ref
                          .read(reconciliationsProvider.notifier)
                          .reject(item.id, reason.trim());
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Reddedildi.')),
                      );
                    },
                    icon: const Icon(Icons.block),
                    label: const Text('Reddet'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _rejectDialog(BuildContext context) async {
    _reasonController.clear();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Red Nedeni'),
          content: TextField(
            controller: _reasonController,
            decoration: const InputDecoration(
              labelText: 'Açıklama',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_reasonController.text),
              child: const Text('Reddet'),
            ),
          ],
        );
      },
    );
  }
}

enum MetricTone { primary, success, warning, danger, neutral }

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.tone = MetricTone.neutral,
  });

  final String title;
  final String value;
  final IconData icon;
  final MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (tone) {
      MetricTone.primary => scheme.primary,
      MetricTone.success => Colors.green.shade700,
      MetricTone.warning => Colors.orange.shade800,
      MetricTone.danger => scheme.error,
      MetricTone.neutral => scheme.outline,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
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
  const _DonutSegment({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.segments});
  final List<_DonutSegment> segments;

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
              total.toStringAsFixed(0),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(
              'Ödeme tipi',
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
    return oldDelegate.total != total || oldDelegate.segments != segments || oldDelegate.trackColor != trackColor;
  }
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
