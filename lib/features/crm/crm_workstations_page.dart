import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class CrmWorkstationsPage extends ConsumerStatefulWidget {
  const CrmWorkstationsPage({super.key});

  @override
  ConsumerState<CrmWorkstationsPage> createState() => _CrmWorkstationsPageState();
}

class _CrmWorkstationsPageState extends ConsumerState<CrmWorkstationsPage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final items = ref.watch(workstationsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('İş İstasyonları', style: Theme.of(context).textTheme.titleLarge),
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
                        decoration: const InputDecoration(labelText: 'Kod'),
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
                      width: 120,
                      child: FilledButton(
                        onPressed: !canEdit
                            ? null
                            : () async {
                                final code = _codeController.text.trim();
                                final name = _nameController.text.trim();
                                if (code.isEmpty || name.isEmpty) return;
                                await ref.read(workstationsProvider.notifier).add(
                                      code: code,
                                      name: name,
                                    );
                                _codeController.clear();
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
                                _codeController.clear();
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
                        DataColumn(label: Text('Kod')),
                        DataColumn(label: Text('Ad')),
                        DataColumn(label: Text('Aktif')),
                      ],
                      rows: [
                        for (var i = 0; i < items.length; i++)
                          DataRow(
                            color: WidgetStatePropertyAll(
                              i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
                            ),
                            cells: [
                              DataCell(Text(items[i].code)),
                              DataCell(Text(items[i].name)),
                              DataCell(
                                Switch(
                                  value: items[i].isActive,
                                  onChanged: !canEdit
                                      ? null
                                      : (_) => ref.read(workstationsProvider.notifier).toggleActive(
                                            items[i].id,
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
}
