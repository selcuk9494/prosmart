import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class CrmPaymentTypesPage extends ConsumerStatefulWidget {
  const CrmPaymentTypesPage({super.key});

  @override
  ConsumerState<CrmPaymentTypesPage> createState() => _CrmPaymentTypesPageState();
}

class _CrmPaymentTypesPageState extends ConsumerState<CrmPaymentTypesPage> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final items = ref.watch(paymentTypesProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Ödeme Türleri', style: Theme.of(context).textTheme.titleLarge),
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
                        decoration: const InputDecoration(labelText: 'Kod (POS eşleşme)'),
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
                        onPressed: canEdit
                            ? () async {
                                      final code = _codeController.text.trim();
                                final name = _nameController.text.trim();
                                if (name.isEmpty) return;
                                      await ref.read(paymentTypesProvider.notifier).addPaymentType(
                                            name: name,
                                            code: code.isEmpty ? null : code,
                                          );
                                      _codeController.clear();
                                _nameController.clear();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Kaydedildi.')),
                                  );
                                }
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
                                      _codeController.clear();
                                _nameController.clear();
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
                        DataColumn(label: Text('Aktif')),
                        DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (var i = 0; i < items.length; i++)
                          DataRow(
                            color: WidgetStatePropertyAll(
                              i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
                            ),
                            cells: [
                              DataCell(Text(items[i].code ?? '')),
                              DataCell(Text(items[i].name)),
                              DataCell(
                                Switch(
                                  value: items[i].isActive,
                                  onChanged: canEdit
                                      ? (_) => ref
                                          .read(paymentTypesProvider.notifier)
                                          .toggleActive(items[i].id)
                                      : null,
                                ),
                              ),
                              DataCell(
                                IconButton(
                                  tooltip: 'Düzenle',
                                  onPressed: !canEdit
                                      ? null
                                      : () async {
                                          final updated = await _editDialog(
                                            context,
                                            initialCode: items[i].code ?? '',
                                            initialName: items[i].name,
                                          );
                                          if (updated == null) return;
                                          await ref.read(paymentTypesProvider.notifier).update(
                                                id: items[i].id,
                                                code: updated.code,
                                                name: updated.name,
                                              );
                                        },
                                  icon: const Icon(Icons.edit_outlined),
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

typedef _EditPaymentTypeResult = ({String code, String name});

Future<_EditPaymentTypeResult?> _editDialog(
  BuildContext context, {
  required String initialCode,
  required String initialName,
}) async {
  final codeController = TextEditingController(text: initialCode);
  final nameController = TextEditingController(text: initialName);

  final result = await showDialog<_EditPaymentTypeResult>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Ödeme Türü Düzenle'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Kod (POS eşleşme)'),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Ad'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop((
                code: codeController.text.trim(),
                name: name,
              ));
            },
            child: const Text('Kaydet'),
          ),
        ],
      );
    },
  );

  codeController.dispose();
  nameController.dispose();
  return result;
}
