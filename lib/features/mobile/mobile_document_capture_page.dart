import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';

import '../../app/api_client.dart';
import '../../app/config.dart';
import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class MobileDocumentCapturePage extends ConsumerStatefulWidget {
  const MobileDocumentCapturePage({super.key});

  @override
  ConsumerState<MobileDocumentCapturePage> createState() =>
      _MobileDocumentCapturePageState();
}

class _MobileDocumentCapturePageState
    extends ConsumerState<MobileDocumentCapturePage> {
  final _picker = ImagePicker();
  DateTime _fromDate = _dayOnly(DateTime.now());
  DateTime _toDate = _dayOnly(DateTime.now());
  String _busyKey = '';
  bool _didInitialLoad = false;

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<DateTime> get _days {
    final out = <DateTime>[];
    for (
      var d = _fromDate;
      !d.isAfter(_toDate);
      d = d.add(const Duration(days: 1))
    ) {
      out.add(d);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_initialLoad);
  }

  Future<void> _initialLoad() async {
    if (_didInitialLoad || !AppConfig.hasApi) return;
    _didInitialLoad = true;
    await Future.wait([
      ref.read(branchesProvider.notifier).refresh(),
      ref.read(reconciliationsProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final allBranches = ref.watch(branchesProvider).where((b) {
      if (!b.isActive) return false;
      return true;
    }).toList();
    final assignedBranchId = session?.branchId?.trim();
    final branches =
        role == UserRole.branchUser &&
            assignedBranchId != null &&
            assignedBranchId.isNotEmpty
        ? allBranches.where((b) => b.id == assignedBranchId).toList()
        : allBranches;
    final reconciliations = ref.watch(reconciliationsProvider);
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    final rows = [
      for (final day in _days)
        for (final branch in branches)
          _MobileDocumentRow(
            day: day,
            branch: branch,
            reconciliation: reconciliations
                .where((r) => r.branchId == branch.id && _sameDay(r.date, day))
                .firstOrNull,
          ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MobileHeader(
          fromDate: _fromDate,
          toDate: _toDate,
          onPickFrom: () => _pickDate(isFrom: true),
          onPickTo: () => _pickDate(isFrom: false),
          onToday: () => setState(() {
            _fromDate = _dayOnly(DateTime.now());
            _toDate = _dayOnly(DateTime.now());
          }),
          onRefresh: () async {
            await ref.read(reconciliationsProvider.notifier).refresh();
            await ref.read(branchesProvider.notifier).refresh();
          },
          branchCount: branches.length,
          reconciliationCount: reconciliations.length,
        ),
        const SizedBox(height: 12),
        if (role == UserRole.branchUser &&
            (assignedBranchId == null || assignedBranchId.isEmpty))
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Bu kullanıcıya bağlı şube bulunamadı; geçici olarak tüm aktif şubeler gösteriliyor.',
              ),
            ),
          ),
        if (role == UserRole.branchUser &&
            assignedBranchId != null &&
            assignedBranchId.isNotEmpty &&
            branches.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Kullanıcının bağlı olduğu şube aktif şube listesinde bulunamadı. Şube ID: $assignedBranchId',
              ),
            ),
          ),
        if ((role == UserRole.branchUser &&
                (assignedBranchId == null || assignedBranchId.isEmpty)) ||
            (role == UserRole.branchUser &&
                assignedBranchId != null &&
                assignedBranchId.isNotEmpty &&
                branches.isEmpty))
          const SizedBox(height: 12),
        if (rows.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('Seçili tarihler için aktif şube bulunamadı.'),
            ),
          )
        else
          for (final row in rows) ...[
            _MobileBranchCard(
              row: row,
              money: money,
              isBusy: _busyKey.startsWith(
                '${row.branch.id}:${_dateKey(row.day)}',
              ),
              onUploadEndOfDay: () =>
                  _captureAndUpload(row, _MobileDocKind.endOfDay),
              onUploadCountSlip: () =>
                  _captureAndUpload(row, _MobileDocKind.countSlip),
              onUploadSigned: () =>
                  _captureAndUpload(row, _MobileDocKind.signedStatement),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked == null) return;
    final day = _dayOnly(picked);
    setState(() {
      if (isFrom) {
        _fromDate = day;
        if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
      } else {
        _toDate = day;
        if (_fromDate.isAfter(_toDate)) _fromDate = _toDate;
      }
    });
    await ref.read(reconciliationsProvider.notifier).refresh();
  }

  Future<CashReconciliation> _ensureReconciliation(
    _MobileDocumentRow row,
  ) async {
    final existing = row.reconciliation;
    if (existing != null) return existing;
    final session = ref.read(authControllerProvider).asData?.value;
    if (session == null) throw StateError('Oturum bulunamadı');
    return ref
        .read(reconciliationsProvider.notifier)
        .createDraft(
          branchId: row.branch.id,
          date: row.day,
          userId: session.userId,
        );
  }

  Future<void> _captureAndUpload(
    _MobileDocumentRow row,
    _MobileDocKind kind,
  ) async {
    if (!AppConfig.hasApi) return;
    final source = await _pickSource();
    if (source == null) return;

    final busyKey = '${row.branch.id}:${_dateKey(row.day)}:${kind.name}';
    if (_busyKey.isNotEmpty) return;
    setState(() => _busyKey = busyKey);
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (picked == null) return;

      final rec = await _ensureReconciliation(row);
      final bytes = await picked.readAsBytes();
      final fileName = picked.name.isNotEmpty
          ? picked.name
          : '${kind.name}-${_dateKey(row.day)}.jpg';
      final mimeType =
          picked.mimeType ??
          lookupMimeType(fileName, headerBytes: bytes) ??
          'image/jpeg';

      if (kind == _MobileDocKind.endOfDay) {
        await _uploadEndOfDay(rec.id, fileName, mimeType, bytes);
      } else {
        await ref
            .read(reconciliationsProvider.notifier)
            .uploadAttachmentFile(
              reconciliationId: rec.id,
              kind: kind == _MobileDocKind.countSlip
                  ? AttachmentKind.countSlip
                  : AttachmentKind.signedStatement,
              fileName: fileName,
              mimeType: mimeType,
              bytes: bytes,
            );
      }

      await ref.read(reconciliationsProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${row.branch.name} ${_kindLabel(kind)} yüklendi.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Yükleme başarısız: $e')));
    } finally {
      if (mounted) setState(() => _busyKey = '');
    }
  }

  Future<ImageSource?> _pickSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Kameradan çek'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Galeriden seç'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _uploadEndOfDay(
    String reconciliationId,
    String fileName,
    String mimeType,
    List<int> bytes,
  ) async {
    final dio = ref.read(dioProvider);
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    await dio.post<Map<String, dynamic>>(
      '/cash-reconciliations/$reconciliationId/end-of-day/card-from-image',
      data: form,
    );
    ref.invalidate(endOfDayReportsProvider(reconciliationId));
  }

  String _dateKey(DateTime d) => DateFormat('yyyy-MM-dd', 'tr_TR').format(d);

  String _kindLabel(_MobileDocKind kind) => switch (kind) {
    _MobileDocKind.endOfDay => 'günsonu fişi',
    _MobileDocKind.countSlip => 'para evrağı',
    _MobileDocKind.signedStatement => 'imzalı evrak',
  };
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.fromDate,
    required this.toDate,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onToday,
    required this.onRefresh,
    required this.branchCount,
    required this.reconciliationCount,
  });

  final DateTime fromDate;
  final DateTime toDate;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onToday;
  final Future<void> Function() onRefresh;
  final int branchCount;
  final int reconciliationCount;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy', 'tr_TR');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.document_scanner_outlined),
                const SizedBox(width: 8),
                Text(
                  'Mobil Evrak',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Yenile',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onPickFrom,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(fmt.format(fromDate)),
                ),
                OutlinedButton.icon(
                  onPressed: onPickTo,
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(fmt.format(toDate)),
                ),
                FilledButton.tonalIcon(
                  onPressed: onToday,
                  icon: const Icon(Icons.today_outlined),
                  label: const Text('Bugün'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniMetric(label: 'Şube', value: branchCount.toString()),
                _MiniMetric(
                  label: 'İcmal',
                  value: reconciliationCount.toString(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileBranchCard extends StatelessWidget {
  const _MobileBranchCard({
    required this.row,
    required this.money,
    required this.isBusy,
    required this.onUploadEndOfDay,
    required this.onUploadCountSlip,
    required this.onUploadSigned,
  });

  final _MobileDocumentRow row;
  final NumberFormat money;
  final bool isBusy;
  final VoidCallback onUploadEndOfDay;
  final VoidCallback onUploadCountSlip;
  final VoidCallback onUploadSigned;

  @override
  Widget build(BuildContext context) {
    final rec = row.reconciliation;
    final date = DateFormat('dd MMM yyyy', 'tr_TR').format(row.day);
    final canEdit =
        rec == null ||
        rec.status == ReconciliationStatus.draft ||
        rec.status == ReconciliationStatus.rejected;
    final hasCountSlip =
        rec?.attachments.any((a) => a.kind == AttachmentKind.countSlip) ??
        false;
    final hasSigned =
        rec?.attachments.any((a) => a.kind == AttachmentKind.signedStatement) ??
        false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.branch.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(date),
                    ],
                  ),
                ),
                _StatusChip(text: _statusText(rec), icon: _statusIcon(rec)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniMetric(
                  label: 'Satış',
                  value: money.format(rec?.expectedSalesTotal ?? 0),
                ),
                _MiniMetric(
                  label: 'Ödeme',
                  value: money.format(rec?.paymentTotal ?? 0),
                ),
                _MiniMetric(
                  label: 'Evrak',
                  value: '${rec?.attachmentsCount ?? 0}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isBusy)
              const LinearProgressIndicator()
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: canEdit ? onUploadEndOfDay : null,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Günsonu'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: canEdit ? onUploadCountSlip : null,
                    icon: Icon(
                      hasCountSlip
                          ? Icons.check_circle_outline
                          : Icons.payments_outlined,
                    ),
                    label: const Text('Para Evrakı'),
                  ),
                  OutlinedButton.icon(
                    onPressed: canEdit ? onUploadSigned : null,
                    icon: Icon(
                      hasSigned
                          ? Icons.check_circle_outline
                          : Icons.edit_document,
                    ),
                    label: const Text('İmzalı Evrak'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static String _statusText(CashReconciliation? rec) {
    if (rec == null) return 'İcmal yok';
    return switch (rec.status) {
      ReconciliationStatus.draft => 'Taslak',
      ReconciliationStatus.submitted => 'Onayda',
      ReconciliationStatus.approved => 'Onaylandı',
      ReconciliationStatus.rejected => 'Reddedildi',
    };
  }

  static IconData _statusIcon(CashReconciliation? rec) {
    if (rec == null) return Icons.add_circle_outline;
    return switch (rec.status) {
      ReconciliationStatus.draft => Icons.edit_note,
      ReconciliationStatus.submitted => Icons.verified_outlined,
      ReconciliationStatus.approved => Icons.check_circle_outline,
      ReconciliationStatus.rejected => Icons.error_outline,
    };
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MobileDocumentRow {
  const _MobileDocumentRow({
    required this.day,
    required this.branch,
    required this.reconciliation,
  });

  final DateTime day;
  final Branch branch;
  final CashReconciliation? reconciliation;
}

enum _MobileDocKind { endOfDay, countSlip, signedStatement }
