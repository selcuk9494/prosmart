import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class CrmAccountPeriodsPage extends ConsumerStatefulWidget {
  const CrmAccountPeriodsPage({super.key});

  @override
  ConsumerState<CrmAccountPeriodsPage> createState() => _CrmAccountPeriodsPageState();
}

class _CrmAccountPeriodsPageState extends ConsumerState<CrmAccountPeriodsPage> {
  final _nameController = TextEditingController();
  DateTime _start = DateTime(DateTime.now().year, 1, 1);
  DateTime _end = DateTime(DateTime.now().year, 12, 31);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final items = ref.watch(accountPeriodsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Hesap Dönemi', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            OutlinedButton(
              onPressed: () => context.go('/'),
              child: const Text('Kapat'),
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
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        enabled: canEdit,
                        decoration: const InputDecoration(labelText: 'Dönem Adı'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Başlangıç'),
                        child: InkWell(
                          onTap: canEdit ? () => _pickDate(isStart: true) : null,
                          child: Text(_fmt(_start)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Bitiş'),
                        child: InkWell(
                          onTap: canEdit ? () => _pickDate(isStart: false) : null,
                          child: Text(_fmt(_end)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: FilledButton(
                        onPressed: !canEdit
                            ? null
                            : () async {
                                final name = _nameController.text.trim();
                                if (name.isEmpty) return;
                                await ref.read(accountPeriodsProvider.notifier).add(
                                      name: name,
                                      startDate: _start,
                                      endDate: _end,
                                    );
                                _nameController.clear();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Kaydedildi.')),
                                  );
                                }
                              },
                        child: const Text('Kaydet'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 120,
                      child: OutlinedButton(
                        onPressed: !canEdit
                            ? null
                            : () {
                                _nameController.clear();
                                setState(() {});
                              },
                        child: const Text('İptal'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Text('Kayıt yok.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Dönem')),
                        DataColumn(label: Text('Başlangıç')),
                        DataColumn(label: Text('Bitiş')),
                        DataColumn(label: Text('Aktif')),
                      ],
                      rows: [
                        for (var i = 0; i < items.length; i++)
                          DataRow(
                            color: WidgetStatePropertyAll(
                              i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
                            ),
                            cells: [
                              DataCell(Text(items[i].name)),
                              DataCell(Text(_fmt(items[i].startDate))),
                              DataCell(Text(_fmt(items[i].endDate))),
                              DataCell(
                                Switch(
                                  value: items[i].isActive,
                                  onChanged: !canEdit
                                      ? null
                                      : (v) => ref.read(accountPeriodsProvider.notifier).setActive(
                                            items[i].id,
                                            v,
                                          ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  String _fmt(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final mon = d.month.toString().padLeft(2, '0');
    final y = d.year.toString().padLeft(4, '0');
    return '$day.$mon.$y';
  }
}
