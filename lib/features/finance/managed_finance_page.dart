import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/stores.dart';

class ManagedFinancePage extends ConsumerStatefulWidget {
  const ManagedFinancePage({
    super.key,
    required this.legacyRef,
    this.moduleTitle,
  });

  final String legacyRef;
  final String? moduleTitle;

  @override
  ConsumerState<ManagedFinancePage> createState() => _ManagedFinancePageState();
}

class _ManagedFinancePageState extends ConsumerState<ManagedFinancePage> {
  final _queryController = TextEditingController();
  late List<_FinanceRecord> _records;
  String _statusFilter = 'Tümü';
  late _ModuleProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = _profileFor(widget.legacyRef);
    _records = _buildRecords(_profile, widget.legacyRef);
  }

  @override
  void didUpdateWidget(covariant ManagedFinancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.legacyRef != widget.legacyRef) {
      _profile = _profileFor(widget.legacyRef);
      _records = _buildRecords(_profile, widget.legacyRef);
      _statusFilter = 'Tümü';
      _queryController.clear();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider);
    final rows = _filteredRows();
    final totals = _totals(_records);
    final statuses = ['Tümü', ..._profile.statuses];

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(
            title: widget.moduleTitle,
            profile: _profile,
            legacyRef: widget.legacyRef,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(
                title: 'Toplam Tutar',
                value: _money(totals.total),
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFF1565C0),
              ),
              _MetricCard(
                title: 'Açık Kayıt',
                value: totals.openCount.toString(),
                icon: Icons.pending_actions_outlined,
                color: const Color(0xFF6A1B9A),
              ),
              _MetricCard(
                title: 'Risk / Fark',
                value: _money(totals.risk),
                icon: Icons.warning_amber_outlined,
                color: const Color(0xFFC62828),
              ),
              _MetricCard(
                title: 'Tamamlanan',
                value: totals.closedCount.toString(),
                icon: Icons.verified_outlined,
                color: const Color(0xFF2E7D32),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _queryController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Kayıt, firma, şube veya açıklama ara',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _statusFilter,
                      decoration: const InputDecoration(labelText: 'Durum'),
                      items: [
                        for (final s in statuses)
                          DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: (v) =>
                          setState(() => _statusFilter = v ?? 'Tümü'),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () =>
                        _openEditor(branches.map((e) => e.name).toList()),
                    icon: const Icon(Icons.add),
                    label: const Text('Yeni Kayıt'),
                  ),
                  OutlinedButton.icon(
                    onPressed: rows.isEmpty ? null : () => _copyCsv(rows),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('CSV'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _refreshScenario,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Listeyi Yenile'),
                  ),
                ],
              ),
            ),
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
                        'Operasyon Listesi',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text('${rows.length} kayıt'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _FinanceTable(
                    rows: rows,
                    profile: _profile,
                    onEdit: (record) => _openEditor(
                      branches.map((e) => e.name).toList(),
                      record: record,
                    ),
                    onAdvance: _advanceRecord,
                    onDelete: _deleteRecord,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _WorkflowPanel(profile: _profile),
        ],
      ),
    );
  }

  List<_FinanceRecord> _filteredRows() {
    final q = _queryController.text.trim().toLowerCase();
    return [
      for (final r in _records)
        if ((_statusFilter == 'Tümü' || r.status == _statusFilter) &&
            (q.isEmpty ||
                r.code.toLowerCase().contains(q) ||
                r.party.toLowerCase().contains(q) ||
                r.branch.toLowerCase().contains(q) ||
                r.description.toLowerCase().contains(q)))
          r,
    ];
  }

  void _refreshScenario() {
    setState(() {
      _records = _buildRecords(
        _profile,
        '${widget.legacyRef}-${DateTime.now().minute}',
      );
    });
    _showMessage('NBOS işlem listesi yenilendi.');
  }

  void _advanceRecord(_FinanceRecord record) {
    final i = _records.indexWhere((e) => e.id == record.id);
    if (i < 0) return;
    final currentStatusIndex = _profile.statuses.indexOf(record.status);
    final nextStatus = _profile
        .statuses[min(currentStatusIndex + 1, _profile.statuses.length - 1)];
    setState(() {
      _records[i] = record.copyWith(
        status: nextStatus,
        updatedAt: DateTime.now(),
      );
    });
    _showMessage('${record.code} durumu "$nextStatus" olarak güncellendi.');
  }

  void _deleteRecord(_FinanceRecord record) {
    setState(() => _records.removeWhere((e) => e.id == record.id));
    _showMessage('${record.code} arşivlendi.');
  }

  Future<void> _copyCsv(List<_FinanceRecord> rows) async {
    final csv = [
      'Kod;Tarih;Şube;Cari;Durum;Tutar;Fark;Açıklama',
      for (final r in rows)
        [
          r.code,
          _date(r.date),
          r.branch,
          r.party,
          r.status,
          r.amount.toStringAsFixed(2),
          r.riskAmount.toStringAsFixed(2),
          r.description,
        ].join(';'),
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    _showMessage('Liste CSV olarak panoya kopyalandı.');
  }

  Future<void> _openEditor(
    List<String> branchNames, {
    _FinanceRecord? record,
  }) async {
    final codeController = TextEditingController(
      text: record?.code ?? _nextCode(_profile),
    );
    final partyController = TextEditingController(
      text: record?.party ?? _profile.sampleParties.first,
    );
    final amountController = TextEditingController(
      text: (record?.amount ?? 12500).toStringAsFixed(2),
    );
    final descriptionController = TextEditingController(
      text: record?.description ?? _profile.defaultDescription,
    );
    var branch =
        record?.branch ??
        (branchNames.isNotEmpty ? branchNames.first : 'Merkez Şube');
    var status = record?.status ?? _profile.statuses.first;

    final saved = await showDialog<_FinanceRecord>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(record == null ? 'Yeni Kayıt' : 'Kayıt Düzenle'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: codeController,
                        decoration: const InputDecoration(
                          labelText: 'Belge/Kayıt No',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: branch,
                        decoration: const InputDecoration(labelText: 'Şube'),
                        items: [
                          for (final b in {
                            ...branchNames,
                            if (branchNames.isEmpty) 'Merkez Şube',
                          })
                            DropdownMenuItem(value: b, child: Text(b)),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => branch = v ?? branch),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: partyController,
                        decoration: InputDecoration(
                          labelText: _profile.partyLabel,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Tutar'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(labelText: 'Durum'),
                        items: [
                          for (final s in _profile.statuses)
                            DropdownMenuItem(value: s, child: Text(s)),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => status = v ?? status),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Açıklama',
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () {
                    final amount =
                        double.tryParse(
                          amountController.text.replaceAll(',', '.'),
                        ) ??
                        0;
                    Navigator.of(context).pop(
                      _FinanceRecord(
                        id:
                            record?.id ??
                            'rec-${DateTime.now().microsecondsSinceEpoch}',
                        code: codeController.text.trim().isEmpty
                            ? _nextCode(_profile)
                            : codeController.text.trim(),
                        date: record?.date ?? DateTime.now(),
                        branch: branch,
                        party: partyController.text.trim().isEmpty
                            ? _profile.sampleParties.first
                            : partyController.text.trim(),
                        status: status,
                        amount: amount,
                        riskAmount: _profile.riskFactor * amount,
                        description: descriptionController.text.trim(),
                        updatedAt: DateTime.now(),
                      ),
                    );
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    codeController.dispose();
    partyController.dispose();
    amountController.dispose();
    descriptionController.dispose();

    if (saved == null) return;
    setState(() {
      final i = _records.indexWhere((e) => e.id == saved.id);
      if (i >= 0) {
        _records[i] = saved;
      } else {
        _records = [saved, ..._records];
      }
    });
    _showMessage('${saved.code} kaydedildi.');
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.profile,
    required this.legacyRef,
  });

  final String? title;
  final _ModuleProfile profile;
  final String legacyRef;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: profile.color.withValues(alpha: 0.12),
              child: Icon(profile.icon, color: profile.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title?.trim().isNotEmpty == true
                        ? title!.trim()
                        : profile.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(profile.summary),
                  const SizedBox(height: 6),
                  Text(
                    'Modül ref: $legacyRef',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Omni: ${profile.omni.service}.${profile.omni.primaryMethod}',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
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

class _FinanceTable extends StatelessWidget {
  const _FinanceTable({
    required this.rows,
    required this.profile,
    required this.onEdit,
    required this.onAdvance,
    required this.onDelete,
  });

  final List<_FinanceRecord> rows;
  final _ModuleProfile profile;
  final ValueChanged<_FinanceRecord> onEdit;
  final ValueChanged<_FinanceRecord> onAdvance;
  final ValueChanged<_FinanceRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('Filtreye uygun kayıt bulunamadı.')),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          const DataColumn(label: Text('Kayıt No')),
          const DataColumn(label: Text('Tarih')),
          const DataColumn(label: Text('Şube')),
          DataColumn(label: Text(profile.partyLabel)),
          const DataColumn(label: Text('Durum')),
          const DataColumn(label: Text('Tutar')),
          const DataColumn(label: Text('Fark/Risk')),
          const DataColumn(label: Text('İşlem')),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                DataCell(Text(r.code)),
                DataCell(Text(_date(r.date))),
                DataCell(Text(r.branch)),
                DataCell(Text(r.party)),
                DataCell(_StatusChip(status: r.status, profile: profile)),
                DataCell(Text(_money(r.amount))),
                DataCell(Text(_money(r.riskAmount))),
                DataCell(
                  Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Düzenle',
                        onPressed: () => onEdit(r),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Sonraki duruma al',
                        onPressed: () => onAdvance(r),
                        icon: const Icon(Icons.playlist_add_check_outlined),
                      ),
                      IconButton(
                        tooltip: 'Arşivle',
                        onPressed: () => onDelete(r),
                        icon: const Icon(Icons.archive_outlined),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.profile});

  final String status;
  final _ModuleProfile profile;

  @override
  Widget build(BuildContext context) {
    final i = profile.statuses.indexOf(status);
    final colors = [
      const Color(0xFF546E7A),
      const Color(0xFFEF6C00),
      const Color(0xFF1565C0),
      const Color(0xFF2E7D32),
    ];
    final color = colors[max(0, min(i, colors.length - 1))];
    return Chip(
      label: Text(status),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color),
    );
  }
}

class _WorkflowPanel extends StatelessWidget {
  const _WorkflowPanel({required this.profile});

  final _ModuleProfile profile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Süreç Akışı', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < profile.statuses.length; i++)
                  Chip(
                    avatar: CircleAvatar(child: Text('${i + 1}')),
                    label: Text(profile.statuses[i]),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(profile.workflowNote),
          ],
        ),
      ),
    );
  }
}

class _ModuleProfile {
  const _ModuleProfile({
    required this.title,
    required this.summary,
    required this.partyLabel,
    required this.defaultDescription,
    required this.workflowNote,
    required this.statuses,
    required this.sampleParties,
    required this.icon,
    required this.color,
    required this.prefix,
    required this.riskFactor,
    required this.omni,
  });

  final String title;
  final String summary;
  final String partyLabel;
  final String defaultDescription;
  final String workflowNote;
  final List<String> statuses;
  final List<String> sampleParties;
  final IconData icon;
  final Color color;
  final String prefix;
  final double riskFactor;
  final _OmniBinding omni;
}

class _OmniBinding {
  const _OmniBinding({
    required this.service,
    required this.primaryMethod,
    required this.detailMethod,
    required this.saveMethod,
  });

  final String service;
  final String primaryMethod;
  final String detailMethod;
  final String saveMethod;
}

class _FinanceRecord {
  const _FinanceRecord({
    required this.id,
    required this.code,
    required this.date,
    required this.branch,
    required this.party,
    required this.status,
    required this.amount,
    required this.riskAmount,
    required this.description,
    required this.updatedAt,
  });

  final String id;
  final String code;
  final DateTime date;
  final String branch;
  final String party;
  final String status;
  final double amount;
  final double riskAmount;
  final String description;
  final DateTime updatedAt;

  _FinanceRecord copyWith({String? status, DateTime? updatedAt}) {
    return _FinanceRecord(
      id: id,
      code: code,
      date: date,
      branch: branch,
      party: party,
      status: status ?? this.status,
      amount: amount,
      riskAmount: riskAmount,
      description: description,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class _Totals {
  const _Totals({
    required this.total,
    required this.risk,
    required this.openCount,
    required this.closedCount,
  });

  final double total;
  final double risk;
  final int openCount;
  final int closedCount;
}

_Totals _totals(List<_FinanceRecord> rows) {
  final total = rows.fold<double>(0, (sum, r) => sum + r.amount);
  final risk = rows.fold<double>(0, (sum, r) => sum + r.riskAmount.abs());
  final closed = rows
      .where((r) => r.status == 'Tamamlandı' || r.status == 'Onaylandı')
      .length;
  return _Totals(
    total: total,
    risk: risk,
    openCount: rows.length - closed,
    closedCount: closed,
  );
}

List<_FinanceRecord> _buildRecords(_ModuleProfile profile, String seedText) {
  final branches = ['Merkez Şube', 'Lefkoşa', 'Girne', 'Mağusa', 'Depo Merkez'];
  final seed = seedText.codeUnits.fold<int>(0, (sum, e) => sum + e);
  final rnd = Random(seed);
  return [
    for (var i = 0; i < 12; i++)
      _FinanceRecord(
        id: '${profile.prefix}-$i',
        code:
            '${profile.prefix}-${DateTime.now().year}-${(1000 + i).toString()}',
        date: DateTime.now().subtract(Duration(days: i * 2 + rnd.nextInt(3))),
        branch: branches[i % branches.length],
        party: profile.sampleParties[i % profile.sampleParties.length],
        status: profile.statuses[i % profile.statuses.length],
        amount: 2500 + rnd.nextInt(84000) + (i * 137.45),
        riskAmount: i.isEven ? rnd.nextInt(2400) * profile.riskFactor : 0,
        description: profile.defaultDescription,
        updatedAt: DateTime.now().subtract(Duration(hours: i * 3)),
      ),
  ];
}

_ModuleProfile _profileFor(String legacyRef) {
  final ref = legacyRef.toLowerCase();
  if (ref.contains('rapor') ||
      ref.contains('report') ||
      ref.contains('analiz')) {
    return const _ModuleProfile(
      title: 'Finans Raporları',
      summary: 'Kasa, stok, satış ve maliyet raporları tek ekranda izlenir.',
      partyLabel: 'Rapor Kırılımı',
      defaultDescription: 'Rapor kırılımı onaylı verilerden oluşturuldu.',
      workflowNote:
          'Raporlar filtrelenir, kontrol edilir, yönetim onayına sunulur ve CSV olarak alınır.',
      statuses: ['Hazırlandı', 'Kontrolde', 'Onaylandı', 'Tamamlandı'],
      sampleParties: [
        'Kasa Raporu',
        'Stok Raporu',
        'Food Cost',
        'Şube Ciro',
        'Masraf Analizi',
      ],
      icon: Icons.query_stats_outlined,
      color: Color(0xFF00695C),
      prefix: 'RPR',
      riskFactor: 0.08,
      omni: _OmniBinding(
        service: 'Report',
        primaryMethod: 'GetDashboardData',
        detailMethod: 'GetAccountStatementReportData',
        saveMethod: 'GetAll',
      ),
    );
  }
  if (ref.contains('siparis') ||
      ref.contains('talep') ||
      ref.contains('satinalim')) {
    return const _ModuleProfile(
      title: 'Satınalma ve Sipariş Yönetimi',
      summary:
          'Talep, teklif, sipariş, mal kabul ve fatura eşleştirme akışı yönetilir.',
      partyLabel: 'Tedarikçi',
      defaultDescription: 'Sipariş bütçe ve stok seviyesine göre planlandı.',
      workflowNote:
          'Talep açılır, tedarikçi teklifi alınır, sipariş onaylanır ve mal kabul sonrası fatura kapatılır.',
      statuses: ['Taslak', 'Onay Bekliyor', 'Siparişte', 'Tamamlandı'],
      sampleParties: [
        'Akdeniz Gıda',
        'Kıbrıs Et',
        'Ada İçecek',
        'Fresh Sebze',
        'Teknik Servis Ltd.',
      ],
      icon: Icons.shopping_cart_checkout_outlined,
      color: Color(0xFF5D4037),
      prefix: 'SIP',
      riskFactor: 0.04,
      omni: _OmniBinding(
        service: 'OrderItem',
        primaryMethod: 'GetOrders',
        detailMethod: 'GetOrderAsync',
        saveMethod: 'CreateOrder',
      ),
    );
  }
  if (ref.contains('fatura') ||
      ref.contains('irsaliye') ||
      ref.contains('odeme') ||
      ref.contains('banka')) {
    return const _ModuleProfile(
      title: 'Finans Belge Yönetimi',
      summary:
          'Fatura, irsaliye, ödeme ve banka talimatları kontrol altında tutulur.',
      partyLabel: 'Cari Hesap',
      defaultDescription: 'Belge cari hesap ve kasa akışı ile eşleştirildi.',
      workflowNote:
          'Belge girilir, cari bakiyesi kontrol edilir, ödeme planına alınır ve muhasebe kapatması yapılır.',
      statuses: ['Taslak', 'Kontrolde', 'Onaylandı', 'Tamamlandı'],
      sampleParties: [
        'Nova Group',
        'Ada Tedarik',
        'Levant Foods',
        'Merkez Banka',
        'POS Mutabakat',
      ],
      icon: Icons.receipt_long_outlined,
      color: Color(0xFF283593),
      prefix: 'FIN',
      riskFactor: 0.03,
      omni: _OmniBinding(
        service: 'Invoice',
        primaryMethod: 'GetInvoiceData',
        detailMethod: 'GetInvoiceDetail',
        saveMethod: 'SaveInvoice',
      ),
    );
  }
  if (ref.contains('stok') ||
      ref.contains('depo') ||
      ref.contains('transfer') ||
      ref.contains('uretim') ||
      ref.contains('sayim')) {
    return const _ModuleProfile(
      title: 'Stok ve Depo Yönetimi',
      summary:
          'Stok hareketi, transfer, sayım, üretim ve fire süreçleri yönetilir.',
      partyLabel: 'Depo / Ürün Grubu',
      defaultDescription:
          'Stok fişi depo bakiyesi ve maliyet etkisiyle işlendi.',
      workflowNote:
          'Fiş oluşturulur, depo sorumlusu kontrol eder, farklar onaylanır ve stok maliyetine yansıtılır.',
      statuses: ['Taslak', 'Sayımda', 'Fark Var', 'Tamamlandı'],
      sampleParties: [
        'Ana Depo',
        'Soğuk Depo',
        'Bar Deposu',
        'Mutfak Üretim',
        'Transfer Deposu',
      ],
      icon: Icons.inventory_2_outlined,
      color: Color(0xFF455A64),
      prefix: 'STK',
      riskFactor: 0.06,
      omni: _OmniBinding(
        service: 'FicheStock',
        primaryMethod: 'GetFicheList',
        detailMethod: 'GetFicheDetail',
        saveMethod: 'CreateOrUpdateFicheStocks',
      ),
    );
  }
  if (ref.contains('servis') ||
      ref.contains('ariza') ||
      ref.contains('bakim') ||
      ref.contains('kalibrasyon')) {
    return const _ModuleProfile(
      title: 'Servis ve Bakım Yönetimi',
      summary:
          'Arıza, bakım, kalibrasyon ve yedek parça talepleri takip edilir.',
      partyLabel: 'Müşteri / Varlık',
      defaultDescription: 'Servis kaydı planlanan iş emrine bağlandı.',
      workflowNote:
          'Bildirim alınır, teknisyen atanır, parça/maliyet işlenir ve servis kapanışı onaylanır.',
      statuses: ['Açık', 'Atandı', 'Sahada', 'Tamamlandı'],
      sampleParties: [
        'POS Terminal 03',
        'Soğutucu Hat',
        'Mutfak Ekipmanı',
        'Jeneratör',
        'Kalibrasyon Seti',
      ],
      icon: Icons.build_circle_outlined,
      color: Color(0xFF6D4C41),
      prefix: 'SRV',
      riskFactor: 0.05,
      omni: _OmniBinding(
        service: 'WorkOrder',
        primaryMethod: 'GetAllWorkOrderData',
        detailMethod: 'GetOrderDetails',
        saveMethod: 'SaveOrderItemData',
      ),
    );
  }
  if (ref.contains('kullanici') ||
      ref.contains('yetki') ||
      ref.contains('grup') ||
      ref.contains('logon')) {
    return const _ModuleProfile(
      title: 'Yetki ve Kullanıcı Yönetimi',
      summary: 'Kullanıcı, grup, menü yetkisi ve erişim denetimi yönetilir.',
      partyLabel: 'Kullanıcı / Grup',
      defaultDescription: 'Yetki değişikliği denetim kaydına alındı.',
      workflowNote:
          'Talep açılır, rol seti seçilir, yönetici onayı sonrası erişim aktif edilir.',
      statuses: ['Talep', 'Kontrolde', 'Onaylandı', 'Tamamlandı'],
      sampleParties: [
        'Şube Kullanıcıları',
        'Muhasebe Grubu',
        'Yönetici',
        'Depo Sorumluları',
        'Rapor Kullanıcıları',
      ],
      icon: Icons.admin_panel_settings_outlined,
      color: Color(0xFFAD1457),
      prefix: 'YTK',
      riskFactor: 0.02,
      omni: _OmniBinding(
        service: 'User',
        primaryMethod: 'GetAllUsers',
        detailMethod: 'GetUserInfoWithRole',
        saveMethod: 'CreateUser',
      ),
    );
  }
  if (ref.contains('teklif') ||
      ref.contains('proje') ||
      ref.contains('kampanya') ||
      ref.contains('sozlesme') ||
      ref.contains('firsat')) {
    return const _ModuleProfile(
      title: 'Satış ve Ticari Yönetim',
      summary:
          'Fırsat, teklif, kampanya, proje ve sözleşme gelir etkisiyle izlenir.',
      partyLabel: 'Müşteri / Proje',
      defaultDescription:
          'Ticari kayıt karlılık ve tahsilat planı ile oluşturuldu.',
      workflowNote:
          'Fırsat açılır, teklif hazırlanır, onay sonrası sözleşme ve faturalama adımlarına aktarılır.',
      statuses: ['Hazırlık', 'Onay Bekliyor', 'Kazanıldı', 'Tamamlandı'],
      sampleParties: [
        'Kurumsal Müşteri',
        'Ada Otel',
        'Nova Franchise',
        'Catering Projesi',
        'Bayi Kampanyası',
      ],
      icon: Icons.trending_up_outlined,
      color: Color(0xFF2E7D32),
      prefix: 'SAT',
      riskFactor: 0.07,
      omni: _OmniBinding(
        service: 'Customer',
        primaryMethod: 'GetCustomers',
        detailMethod: 'GetById',
        saveMethod: 'CreateCustomer',
      ),
    );
  }
  return const _ModuleProfile(
    title: 'Yönetilen Finans Modülü',
    summary:
        'Bu NBOS menüsü çalışan Flutter finans ekranı olarak yönetilebilir hale getirildi.',
    partyLabel: 'Cari / Operasyon',
    defaultDescription: 'Kayıt finans operasyon akışına bağlandı.',
    workflowNote:
        'Kayıt oluşturulur, kontrol edilir, onaylanır ve tamamlanan operasyon arşive alınır.',
    statuses: ['Taslak', 'Kontrolde', 'Onaylandı', 'Tamamlandı'],
    sampleParties: [
      'Merkez Operasyon',
      'Şube Süreci',
      'Cari Hesap',
      'Muhasebe',
      'Yönetim',
    ],
    icon: Icons.account_balance_outlined,
    color: Color(0xFF37474F),
    prefix: 'OPS',
    riskFactor: 0.04,
    omni: _OmniBinding(
      service: 'StaticData',
      primaryMethod: 'GetAll',
      detailMethod: 'GetById',
      saveMethod: 'CreateAsync',
    ),
  );
}

String _nextCode(_ModuleProfile profile) {
  final n = DateTime.now().millisecondsSinceEpoch.remainder(90000) + 10000;
  return '${profile.prefix}-$n';
}

String _date(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String _money(double value) {
  final sign = value < 0 ? '-' : '';
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final chars = parts.first.split('').reversed.toList();
  final grouped = <String>[];
  for (var i = 0; i < chars.length; i++) {
    if (i > 0 && i % 3 == 0) grouped.add('.');
    grouped.add(chars[i]);
  }
  return '$sign₺${grouped.reversed.join()},${parts.last}';
}
