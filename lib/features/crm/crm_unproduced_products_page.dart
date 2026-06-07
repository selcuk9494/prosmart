import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class CrmUnproducedProductsPage extends ConsumerStatefulWidget {
  const CrmUnproducedProductsPage({super.key});

  @override
  ConsumerState<CrmUnproducedProductsPage> createState() => _CrmUnproducedProductsPageState();
}

class _CrmUnproducedProductsPageState extends ConsumerState<CrmUnproducedProductsPage> {
  final _queryController = TextEditingController();
  final _newProductController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    _newProductController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final items = ref.watch(unproducedProductsProvider);
    final q = _queryController.text.trim().toLowerCase();
    final rows = q.isEmpty
        ? items
        : items.where((e) => e.productName.toLowerCase().contains(q)).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Üretilmeyecek Ürünler', style: Theme.of(context).textTheme.titleLarge),
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
                        controller: _queryController,
                        decoration: const InputDecoration(labelText: 'Ürün Ara'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newProductController,
                        enabled: canEdit,
                        decoration: const InputDecoration(labelText: 'Yeni Ürün'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: FilledButton(
                        onPressed: !canEdit
                            ? null
                            : () async {
                                final name = _newProductController.text.trim();
                                if (name.isEmpty) return;
                                await ref.read(unproducedProductsProvider.notifier).add(
                                      productName: name,
                                      isBlocked: true,
                                    );
                                _newProductController.clear();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Kaydedildi.')),
                                  );
                                }
                              },
                        child: const Text('Ekle'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Text('Kayıt yok.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Ürün')),
                        DataColumn(label: Text('Üretim')),
                      ],
                      rows: [
                        for (var i = 0; i < rows.length; i++)
                          DataRow(
                            color: WidgetStatePropertyAll(
                              i.isEven ? const Color(0xFFFFFFFF) : const Color(0xFFF4F4F4),
                            ),
                            cells: [
                              DataCell(Text(rows[i].productName)),
                              DataCell(
                                Switch(
                                  value: !rows[i].isBlocked,
                                  onChanged: !canEdit
                                      ? null
                                      : (v) => ref.read(unproducedProductsProvider.notifier).setBlocked(
                                            rows[i].id,
                                            !v,
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
