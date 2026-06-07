import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api_client.dart';
import '../../app/config.dart';
import '../../domain/stores.dart';

class AnaGrupSatisRaporuPage extends ConsumerStatefulWidget {
  const AnaGrupSatisRaporuPage({super.key});

  @override
  ConsumerState<AnaGrupSatisRaporuPage> createState() => _AnaGrupSatisRaporuPageState();
}

class _AnaGrupSatisRaporuPageState extends ConsumerState<AnaGrupSatisRaporuPage> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  String? _selectedBranchId;
  var _loading = false;
  List<Map<String, dynamic>> _rows = const [];

  @override
  Widget build(BuildContext context) {
    final branches = ref.watch(branchesProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Ana Grup Satış Raporu', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _BluePanel(
                        title: 'Şubeler ve Tarihler',
                        child: Column(
                          children: [
                            _DateRow(
                              label: 'Tarih Aralığı',
                              from: _from,
                              to: _to,
                              onPickFrom: () => _pickDate(isFrom: true),
                              onPickTo: () => _pickDate(isFrom: false),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String?>(
                                    initialValue: _selectedBranchId,
                                    decoration: const InputDecoration(labelText: 'Şube'),
                                    items: [
                                      const DropdownMenuItem(
                                        value: null,
                                        child: Text('Seçiniz'),
                                      ),
                                      for (final b in branches)
                                        DropdownMenuItem(
                                          value: b.id,
                                          child: Text(b.name),
                                        ),
                                    ],
                                    onChanged: (v) => setState(() => _selectedBranchId = v),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 8,
                                children: const [
                                  _TinyCheck(label: 'Pazartesi'),
                                  _TinyCheck(label: 'Salı'),
                                  _TinyCheck(label: 'Çarşamba'),
                                  _TinyCheck(label: 'Perşembe'),
                                  _TinyCheck(label: 'Cuma'),
                                  _TinyCheck(label: 'Cumartesi'),
                                  _TinyCheck(label: 'Pazar'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _BluePanel(
                        title: 'Şube Seçimi',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 12,
                              children: const [
                                _TinyRadio(label: 'Şube', selected: true),
                                _TinyRadio(label: 'Bölge'),
                                _TinyRadio(label: 'Şehir'),
                                _TinyRadio(label: 'Profil'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 210,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: const Color(0xFFBDBDBD)),
                              ),
                              child: ListView(
                                children: [
                                  for (final b in branches)
                                    ListTile(
                                      dense: true,
                                      title: Text(b.name),
                                      trailing: _selectedBranchId == b.id
                                          ? const Icon(Icons.check_circle, size: 18)
                                          : null,
                                      onTap: () => setState(() => _selectedBranchId = b.id),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Spacer(),
                    SizedBox(
                      width: 120,
                      child: FilledButton(
                        onPressed: _loading ? null : _runReport,
                        child: Text(_loading ? '...' : 'Ara'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 120,
                      child: OutlinedButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _from = DateTime.now();
                                  _to = DateTime.now();
                                  _selectedBranchId = null;
                                  _rows = const [];
                                });
                              },
                        child: const Text('Temizle'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_rows.isNotEmpty) _buildResultTable(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Şube')),
          DataColumn(label: Text('Ciro')),
        ],
        rows: [
          for (var i = 0; i < _rows.length; i++)
            DataRow(
              color: WidgetStatePropertyAll(
                i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
              ),
              cells: [
                DataCell(Text((_rows[i]['branchName'] ?? '').toString())),
                DataCell(Text((_rows[i]['grossTotal'] ?? '0').toString())),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _runReport() async {
    setState(() => _loading = true);
    try {
      if (!AppConfig.hasApi) {
        _rows = [
          {'branchName': 'Şube 1', 'grossTotal': '12345.67'},
          {'branchName': 'Şube 2', 'grossTotal': '8901.23'},
        ];
        return;
      }

      final dio = ref.read(dioProvider);
      final res = await dio.get<List<dynamic>>(
        '/reports/ana-grup-satis',
        queryParameters: {
          'from': _fmt(_from),
          'to': _fmt(_to),
          if (_selectedBranchId != null) 'branchId': _selectedBranchId,
        },
      );
      final data = res.data ?? const [];
      _rows = [
        for (final raw in data)
          if (raw is Map<String, dynamic>) raw,
      ];
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rapor alınamadı: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

class _BluePanel extends StatelessWidget {
  const _BluePanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFB7CBE6),
        border: Border.all(color: const Color(0xFF9BB2D1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFBDBDBD)),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.from,
    required this.to,
    required this.onPickFrom,
    required this.onPickTo,
  });

  final String label;
  final DateTime from;
  final DateTime to;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(labelText: '$label I'),
            child: InkWell(
              onTap: onPickFrom,
              child: Text(_fmt(from)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(labelText: '$label II'),
            child: InkWell(
              onTap: onPickTo,
              child: Text(_fmt(to)),
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final mon = d.month.toString().padLeft(2, '0');
    final y = d.year.toString().padLeft(4, '0');
    return '$day.$mon.$y';
  }
}

class _TinyCheck extends StatelessWidget {
  const _TinyCheck({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: Checkbox(value: true, onChanged: null),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _TinyRadio extends StatelessWidget {
  const _TinyRadio({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
