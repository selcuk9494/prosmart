import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class CrmBranchesPage extends ConsumerStatefulWidget {
  const CrmBranchesPage({super.key});

  @override
  ConsumerState<CrmBranchesPage> createState() => _CrmBranchesPageState();
}

class _CrmBranchesPageState extends ConsumerState<CrmBranchesPage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _businessDayStartHourController = TextEditingController(text: '0');

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _businessDayStartHourController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager;

    final items = ref.watch(branchesProvider);
    final dataSources = ref.watch(branchDataSourcesProvider);
    final cashRegisters = ref.watch(cashRegistersProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Şube Güncelleme', style: Theme.of(context).textTheme.titleLarge),
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
                        controller: _codeController,
                        enabled: canEdit,
                        decoration: const InputDecoration(labelText: 'Kod (POS/entegrasyon)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        enabled: canEdit,
                        decoration: const InputDecoration(labelText: 'Ad'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _businessDayStartHourController,
                        enabled: canEdit,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Gün başlangıç saati',
                          hintText: '0-23',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: FilledButton(
                        onPressed: canEdit
                            ? () async {
                                final name = _nameController.text.trim();
                                final code = _codeController.text.trim();
                                final startHour = int.tryParse(_businessDayStartHourController.text.trim()) ?? 0;
                                if (name.isEmpty) return;
                                await ref.read(branchesProvider.notifier).addBranch(
                                      name: name,
                                      code: code.isEmpty ? null : code,
                                      businessDayStartHour: startHour.clamp(0, 23),
                                    );
                                _nameController.clear();
                                _codeController.clear();
                                _businessDayStartHourController.text = '0';
                                if (!mounted) return;
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(content: Text('Kaydedildi.')),
                                );
                              }
                            : null,
                        child: const Text('Kaydet'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 120,
                      child: OutlinedButton(
                        onPressed: canEdit
                            ? () {
                                _nameController.clear();
                                _codeController.clear();
                                _businessDayStartHourController.text = '0';
                                setState(() {});
                              }
                            : null,
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
                        DataColumn(label: Text('Kod')),
                        DataColumn(label: Text('Ad')),
                        DataColumn(label: Text('Gün Baş.')),
                        DataColumn(label: Text('DB')),
                        DataColumn(label: Text('Kasa')),
                        DataColumn(label: Text('Aktif')),
                      ],
                      rows: [
                        for (var i = 0; i < items.length; i++)
                          DataRow(
                            color: WidgetStatePropertyAll(
                              i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
                            ),
                            cells: [
                              DataCell(
                                Text(items[i].code ?? ''),
                                onTap: canEdit ? () => _showEditDialog(context, items[i]) : null,
                              ),
                              DataCell(Text(items[i].name)),
                              DataCell(
                                Text(items[i].businessDayStartHour.toString()),
                                onTap: canEdit ? () => _showEditDialog(context, items[i]) : null,
                              ),
                              DataCell(
                                IconButton(
                                  tooltip: () {
                                    final s = dataSources.where((e) => e.branchId == items[i].id).firstOrNull;
                                    if (s == null) return 'Bağlantı yok';
                                    if (!s.isActive) return 'Pasif';
                                    return '${s.host}:${s.port}/${s.database}';
                                  }(),
                                  icon: Icon(
                                    dataSources.any((e) => e.branchId == items[i].id && e.isActive)
                                        ? Icons.cloud_done_outlined
                                        : Icons.cloud_off_outlined,
                                  ),
                                  onPressed: canEdit
                                      ? () => _showDbDialog(context, items[i])
                                      : null,
                                ),
                              ),
                              DataCell(
                                IconButton(
                                  tooltip: 'Kasalar',
                                  icon: const Icon(Icons.point_of_sale_outlined),
                                  onPressed: canEdit
                                      ? () => _showCashRegistersDialog(
                                            context,
                                            branch: items[i],
                                            cashRegisters: cashRegisters,
                                          )
                                      : null,
                                ),
                              ),
                              DataCell(
                                Switch(
                                  value: items[i].isActive,
                                  onChanged: canEdit
                                      ? (_) => ref
                                          .read(branchesProvider.notifier)
                                          .toggleActive(items[i].id)
                                      : null,
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

  Future<void> _showEditDialog(BuildContext context, Branch item) async {
    final nameController = TextEditingController(text: item.name);
    final codeController = TextEditingController(text: item.code ?? '');
    final businessDayStartHourController =
        TextEditingController(text: item.businessDayStartHour.toString());
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Şube Düzenle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Kod (POS/entegrasyon)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Ad'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: businessDayStartHourController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Gün başlangıç saati',
                  hintText: '0-23',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      final name = nameController.text.trim();
      final code = codeController.text.trim();
      final startHour =
          int.tryParse(businessDayStartHourController.text.trim()) ?? 0;
      if (name.isNotEmpty) {
        await ref.read(branchesProvider.notifier).update(
              id: item.id,
              name: name,
              code: code,
              businessDayStartHour: startHour.clamp(0, 23),
            );
      }
    }
    nameController.dispose();
    codeController.dispose();
    businessDayStartHourController.dispose();
  }

  Future<void> _showDbDialog(BuildContext context, Branch branch) async {
    final existing =
        ref.read(branchDataSourcesProvider.notifier).byBranchId(branch.id);

    final hostController = TextEditingController(text: existing?.host ?? '');
    final portController =
        TextEditingController(text: (existing?.port ?? 5432).toString());
    final dbController = TextEditingController(text: existing?.database ?? '');
    final userController = TextEditingController(text: existing?.username ?? '');
    final passController = TextEditingController();
    var ssl = existing?.ssl ?? false;
    var isActive = existing?.isActive ?? true;

    Future<void> test() async {
      await ref.read(branchDataSourcesProvider.notifier).refresh();
      final now = ref.read(branchDataSourcesProvider.notifier).byBranchId(branch.id);
      if (now == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(content: Text('Önce kaydetmelisiniz.')),
        );
        return;
      }
      final ok = await ref.read(branchDataSourcesProvider.notifier).test(branch.id);
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text(ok ? 'Bağlantı OK' : 'Bağlantı başarısız')),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text('Şube DB • ${branch.name}'),
              content: SizedBox(
                width: 720,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: hostController,
                      decoration: const InputDecoration(labelText: 'Host'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: portController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Port'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: dbController,
                            decoration: const InputDecoration(labelText: 'Database'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: userController,
                            decoration: const InputDecoration(labelText: 'User'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: passController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password (boş: değiştirme)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: ssl,
                      onChanged: (v) => setLocal(() => ssl = v),
                      title: const Text('SSL'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: isActive,
                      onChanged: (v) => setLocal(() => isActive = v),
                      title: const Text('Aktif'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kapat'),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      final port = int.tryParse(portController.text.trim()) ?? 5432;
                      await ref.read(branchDataSourcesProvider.notifier).upsert(
                            branchId: branch.id,
                            host: hostController.text.trim(),
                            port: port,
                            database: dbController.text.trim(),
                            username: userController.text.trim(),
                            password: passController.text.isEmpty ? null : passController.text,
                            ssl: ssl,
                            isActive: isActive,
                          );
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Kaydedildi.')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text('Hata: $e')),
                      );
                    }
                  },
                  child: const Text('Kaydet'),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    try {
                      await test();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text('Test hatası: $e')),
                      );
                    }
                  },
                  child: const Text('Test'),
                ),
              ],
            );
          },
        );
      },
    );

    hostController.dispose();
    portController.dispose();
    dbController.dispose();
    userController.dispose();
    passController.dispose();
  }

  Future<void> _showCashRegistersDialog(
    BuildContext context, {
    required Branch branch,
    required List<CashRegister> cashRegisters,
  }) async {
    final assigned = await ref.read(branchCashRegistersProvider(branch.id).future);
    final selected = <String>{
      for (final r in assigned) r.id,
    };

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Şube Kasaları • ${branch.name}'),
              content: SizedBox(
                width: 520,
                child: cashRegisters.isEmpty
                    ? const Text('Önce Tanımlar → Kasa bölümünden kasa tanımı yapmalısınız.')
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final r in cashRegisters)
                            CheckboxListTile(
                              value: selected.contains(r.id),
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    selected.add(r.id);
                                  } else {
                                    selected.remove(r.id);
                                  }
                                });
                              },
                              title: Text('${r.code} • ${r.name}'),
                            ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kapat'),
                ),
                FilledButton(
                  onPressed: () async {
                    await ref.read(branchCashRegistersActionsProvider).setForBranch(
                          branchId: branch.id,
                          cashRegisterIds: selected.toList(),
                        );
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('Kaydedildi.')),
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
