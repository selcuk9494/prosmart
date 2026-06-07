import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api_client.dart';
import '../../app/config.dart';
import '../../domain/stores.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches = ref.watch(branchesProvider);
    final cashRegisters = ref.watch(cashRegistersProvider);
    final paymentTypes = ref.watch(paymentTypesProvider);
    final expenseTypes = ref.watch(expenseTypesProvider);
    final dbCheck = ref.watch(dbCheckProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Ayarlar', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Sistem', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    FilledButton.tonal(
                      onPressed: () => ref.invalidate(dbCheckProvider),
                      child: const Text('Kontrol Et'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  AppConfig.hasApi
                      ? 'API: ${AppConfig.apiBaseUrl}'
                      : 'API: DEMO (API_BASE_URL tanımlı değil)',
                ),
                const SizedBox(height: 8),
                dbCheck.when(
                  data: (m) {
                    final ok = (m['ok'] as bool?) ?? false;
                    final missingTables = (m['missingTables'] as List?)?.length ?? 0;
                    final missingColumns = (m['missingColumns'] as List?)?.length ?? 0;
                    final serverTime = (m['serverTime'] ?? '').toString();
                    return Text(
                      'DB: ${ok ? 'OK' : 'Eksik Şema'} • tablo:$missingTables • kolon:$missingColumns'
                      '${serverTime.isEmpty ? '' : ' • $serverTime'}',
                    );
                  },
                  loading: () => const Text('DB kontrol ediliyor...'),
                  error: (e, _) => Text('DB kontrol hatası: $e'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('POS İçe Aktarım', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      const Text('React/POS çıktısını JSON olarak buradan içe aktarabilirsin.'),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: AppConfig.hasApi
                      ? () => _showPosImportDialog(context, ref)
                      : null,
                  child: const Text('Aç'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Şubeler',
          actionLabel: 'Şube Ekle',
          onAdd: () async {
            final payload = await _branchDialog(context);
            if (payload == null) return;
            await ref.read(branchesProvider.notifier).addBranch(
                  name: payload.$1,
                  code: payload.$2,
                );
          },
          child: Column(
            children: [
              for (final b in branches)
                SwitchListTile(
                  value: b.isActive,
                  onChanged: (v) {
                    ref.read(branchesProvider.notifier).toggleActive(b.id);
                  },
                  title: Text(b.name),
                  subtitle: Text('${b.code ?? '-'} • ${b.id}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Kasalar',
          actionLabel: 'Kasa Ekle',
          onAdd: () async {
            final payload = await _cashRegisterDialog(context);
            if (payload == null) return;
            await ref.read(cashRegistersProvider.notifier).addCashRegister(
                  name: payload.$1,
                  code: payload.$2,
                );
          },
          child: Column(
            children: [
              for (final c in cashRegisters)
                SwitchListTile(
                  value: c.isActive,
                  onChanged: (v) {
                    ref.read(cashRegistersProvider.notifier).toggleActive(c.id);
                  },
                  title: Text('${c.code} • ${c.name}'),
                  subtitle: Text(c.id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Ödeme Tipleri',
          actionLabel: 'Tip Ekle',
          onAdd: () async {
            final name = await _textDialog(context, title: 'Ödeme Tipi Ekle');
            if (name == null || name.trim().isEmpty) return;
            await ref.read(paymentTypesProvider.notifier).addPaymentType(name: name.trim());
          },
          child: Column(
            children: [
              for (final p in paymentTypes)
                SwitchListTile(
                  value: p.isActive,
                  onChanged: (v) {
                    ref.read(paymentTypesProvider.notifier).toggleActive(p.id);
                  },
                  title: Text(p.name),
                  subtitle: Text(p.id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Masraf Tipleri',
          actionLabel: 'Tip Ekle',
          onAdd: () async {
            final name = await _textDialog(context, title: 'Masraf Tipi Ekle');
            if (name == null || name.trim().isEmpty) return;
            await ref.read(expenseTypesProvider.notifier).addExpenseType(name.trim());
          },
          child: Column(
            children: [
              for (final e in expenseTypes)
                SwitchListTile(
                  value: e.isActive,
                  onChanged: (v) {
                    ref.read(expenseTypesProvider.notifier).toggleActive(e.id);
                  },
                  title: Text(e.name),
                  subtitle: Text(e.id),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SuggestedSettingsCard(
          suggestions: const [
            'Günlük fark limiti (₺) tanımı',
            'Farklılık olduğunda evrak zorunluluğu kuralı',
            'Onay akışında çift onay (isteğe bağlı)',
            'Dönem kapanışı (tarihe göre kilitleme)',
          ],
        ),
      ],
    );
  }

  Future<(String, String?)?> _branchDialog(BuildContext context) async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Şube Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Kod (POS/entegrasyon)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Ad'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final code = codeController.text.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop((name, code.isEmpty ? null : code));
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

  Future<(String, String?)?> _cashRegisterDialog(BuildContext context) async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kasa Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Kod'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Ad'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final code = codeController.text.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop((name, code.isEmpty ? null : code));
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

  Future<void> _showPosImportDialog(BuildContext context, WidgetRef ref) async {
    final branches = ref.read(branchesProvider).where((e) => e.isActive).toList();
    if (branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktif şube bulunamadı.')),
      );
      return;
    }

    final typeController = ValueNotifier<String>('auto');
    var selectedBranchId = branches.first.id;
    var selectedDate = DateTime.now();
    final jsonController = TextEditingController(text: '[]');

    Future<void> pickDate() async {
      final picked = await showDatePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        initialDate: selectedDate,
      );
      if (picked != null) {
        selectedDate = DateTime(picked.year, picked.month, picked.day);
      }
    }

    Future<void> runImport() async {
      final raw = jsonController.text.trim();
      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (e) {
        throw StateError('JSON parse hatası: $e');
      }
      final day = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
      final businessDate = day.toIso8601String().substring(0, 10);

      final dio = ref.read(dioProvider);
      if (typeController.value == 'auto') {
        await dio.post<Map<String, dynamic>>(
          '/pos/import/daily',
          data: {
            'payload': decoded,
            'branchId': selectedBranchId,
            'businessDate': businessDate,
            'source': 'pos',
          },
        );
      } else {
        if (decoded is! List) {
          throw StateError('Bu modda JSON bir liste olmalı: [{...}, {...}]');
        }
        final items = <Map<String, dynamic>>[];
        for (final row in decoded) {
          if (row is! Map) continue;
          final m = <String, dynamic>{};
          for (final entry in row.entries) {
            final k = entry.key?.toString();
            if (k == null) continue;
            m[k] = entry.value;
          }
          m.putIfAbsent('branchId', () => selectedBranchId);
          m.putIfAbsent('businessDate', () => businessDate);
          m.putIfAbsent('source', () => 'pos');
          items.add(m);
        }
        if (items.isEmpty) {
          throw StateError('İçe aktarılacak kayıt bulunamadı.');
        }
        final endpoint = switch (typeController.value) {
          'sales' => '/pos/import/register-daily-sales',
          'payments' => '/pos/import/register-daily-payments',
          _ => '/pos/import/register-daily-product-sales',
        };
        await dio.post<Map<String, dynamic>>(
          endpoint,
          data: {'items': items},
        );
      }

      await ref.read(reconciliationsProvider.notifier).refresh();
    }

    void fillSample() {
      final day = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
      final businessDate = day.toIso8601String().substring(0, 10);
      final sample = switch (typeController.value) {
        'auto' => {
            'branchId': selectedBranchId,
            'businessDate': businessDate,
            'registers': [
              {
                'registerCode': 'KASA-01',
                'grossTotal': 12345.67,
                'payments': {'CASH': 5000, 'CARD': 7345.67},
                'products': [
                  {
                    'productCode': 'URUN-001',
                    'productName': 'Hamburger',
                    'quantity': 12,
                    'grossTotal': 2400,
                  },
                ],
              },
            ],
          },
        'sales' => [
            {
              'branchId': selectedBranchId,
              'businessDate': businessDate,
              'registerCode': 'KASA-01',
              'grossTotal': 12345.67,
            },
          ],
        'payments' => [
            {
              'branchId': selectedBranchId,
              'businessDate': businessDate,
              'registerCode': 'KASA-01',
              'paymentCode': 'CASH',
              'amount': 5000,
            },
            {
              'branchId': selectedBranchId,
              'businessDate': businessDate,
              'registerCode': 'KASA-01',
              'paymentCode': 'CARD',
              'amount': 7345.67,
            },
          ],
        _ => [
            {
              'branchId': selectedBranchId,
              'businessDate': businessDate,
              'registerCode': 'KASA-01',
              'productCode': 'URUN-001',
              'productName': 'Hamburger',
              'quantity': 12,
              'grossTotal': 2400,
            },
          ],
      };
      jsonController.text = const JsonEncoder.withIndent('  ').convert(sample);
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('POS İçe Aktarım'),
          content: ValueListenableBuilder<String>(
            valueListenable: typeController,
            builder: (context, type, _) {
              final typeLabel = switch (type) {
                'auto' => 'Otomatik (tek JSON)',
                'sales' => 'Kasa Bazlı Ciro',
                'payments' => 'Kasa Bazlı Ödeme Dağılımı',
                _ => 'Kasa Bazlı Ürün Satışları',
              };
              return SizedBox(
                width: 720,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedBranchId,
                      items: [
                        for (final b in branches)
                          DropdownMenuItem(
                            value: b.id,
                            child: Text('${b.code ?? '-'} • ${b.name}'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        selectedBranchId = v;
                      },
                      decoration: const InputDecoration(labelText: 'Şube'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Tarih: ${DateTime(selectedDate.year, selectedDate.month, selectedDate.day).toIso8601String().substring(0, 10)}'),
                        ),
                        TextButton(
                          onPressed: pickDate,
                          child: const Text('Tarih Seç'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('Otomatik (tek JSON)')),
                        DropdownMenuItem(value: 'sales', child: Text('Kasa Bazlı Ciro')),
                        DropdownMenuItem(value: 'payments', child: Text('Kasa Bazlı Ödeme')),
                        DropdownMenuItem(value: 'products', child: Text('Kasa Bazlı Ürün')),
                      ],
                      onChanged: (v) => typeController.value = v ?? 'auto',
                      decoration: const InputDecoration(labelText: 'Veri Tipi'),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Seçili: $typeLabel'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: jsonController,
                      minLines: 8,
                      maxLines: 14,
                      decoration: const InputDecoration(
                        labelText: 'JSON Liste',
                        hintText: '{...} veya [{...}, {...}]',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
            TextButton(
              onPressed: fillSample,
              child: const Text('Örnek'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await runImport();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('POS verisi içe aktarıldı.')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hata: $e')),
                    );
                  }
                }
              },
              child: const Text('İçe Aktar'),
            ),
          ],
        );
      },
    );

    jsonController.dispose();
    typeController.dispose();
  }

  Future<String?> _textDialog(
    BuildContext context, {
    required String title,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Ad'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.actionLabel,
    required this.onAdd,
    required this.child,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAdd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: onAdd,
                  child: Text(actionLabel),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SuggestedSettingsCard extends StatelessWidget {
  const _SuggestedSettingsCard({required this.suggestions});

  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ek Öneriler',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final s in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
