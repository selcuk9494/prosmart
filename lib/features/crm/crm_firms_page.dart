import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models.dart';
import '../../domain/stores.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class CrmFirmsPage extends ConsumerStatefulWidget {
  const CrmFirmsPage({super.key});

  @override
  ConsumerState<CrmFirmsPage> createState() => _CrmFirmsPageState();
}

class _CrmFirmsPageState extends ConsumerState<CrmFirmsPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    ref.read(crmFirmsProvider.notifier).setQuery(_searchController.text);
    final items = ref.watch(crmFirmsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Firma Tanımlama', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(
              onPressed: canEdit ? () => context.go('/crm/firms/new') : null,
              icon: const Icon(Icons.add),
              label: const Text('Yeni'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Ara (firma/ticari/tax no)',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () async {
                await ref.read(crmFirmsProvider.notifier).refresh();
              },
              child: const Text('Ara'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Kayıt yok.'),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Firma Adı')),
                    DataColumn(label: Text('Ticari Adı')),
                    DataColumn(label: Text('Vergi No')),
                    DataColumn(label: Text('E-Posta')),
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
                            Text(items[i].firmName),
                            onTap: () => context.go('/crm/firms/${items[i].id}'),
                          ),
                          DataCell(Text(items[i].tradeName ?? '')),
                          DataCell(Text(items[i].taxNo ?? '')),
                          DataCell(Text(items[i].email ?? '')),
                          DataCell(
                            Switch(
                              value: items[i].isActive,
                              onChanged: canEdit
                                  ? (_) => ref.read(crmFirmsProvider.notifier).toggleActive(
                                        items[i].id,
                                      )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CrmFirmDetailPage extends ConsumerStatefulWidget {
  const CrmFirmDetailPage({super.key, required this.firmId});

  final String firmId;

  @override
  ConsumerState<CrmFirmDetailPage> createState() => _CrmFirmDetailPageState();
}

class _CrmFirmDetailPageState extends ConsumerState<CrmFirmDetailPage> {
  final _firmNameController = TextEditingController();
  final _tradeNameController = TextEditingController();
  final _integrationCodeController = TextEditingController();
  final _firmTypeController = TextEditingController();
  bool _isCurrent = true;
  final _customerGroupController = TextEditingController();
  final _emailController = TextEditingController();
  final _priceNoController = TextEditingController();
  final _wholesalePriceNoController = TextEditingController();
  final _invoiceCompanyController = TextEditingController();

  final _generalDiscountController = TextEditingController();
  final _paymentMethodController = TextEditingController();
  final _taxOfficeController = TextEditingController();
  final _taxNoController = TextEditingController();
  bool _isEInvoice = false;
  final _cargoCodeController = TextEditingController();
  final _purchasePriceNoController = TextEditingController();
  final _paymentVknController = TextEditingController();
  final _ibanController = TextEditingController();

  bool _initialized = false;

  @override
  void dispose() {
    _firmNameController.dispose();
    _tradeNameController.dispose();
    _integrationCodeController.dispose();
    _firmTypeController.dispose();
    _customerGroupController.dispose();
    _emailController.dispose();
    _priceNoController.dispose();
    _wholesalePriceNoController.dispose();
    _invoiceCompanyController.dispose();
    _generalDiscountController.dispose();
    _paymentMethodController.dispose();
    _taxOfficeController.dispose();
    _taxNoController.dispose();
    _cargoCodeController.dispose();
    _purchasePriceNoController.dispose();
    _paymentVknController.dispose();
    _ibanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;
    final isNew = widget.firmId == 'new';

    final firmAsync = isNew ? const AsyncValue<CrmFirm?>.data(null) : ref.watch(crmFirmDetailProvider(widget.firmId)).whenData((v) => v);

    return firmAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Hata: $e'),
            ),
          ),
        ],
      ),
      data: (firm) {
        if (firm != null && !_initialized) {
          _firmNameController.text = firm.firmName;
          _tradeNameController.text = firm.tradeName ?? '';
          _integrationCodeController.text = firm.integrationCode ?? '';
          _firmTypeController.text = firm.firmType ?? '';
          _isCurrent = firm.isCurrent;
          _customerGroupController.text = firm.customerGroup ?? '';
          _emailController.text = firm.email ?? '';
          _priceNoController.text = firm.priceNo ?? '';
          _wholesalePriceNoController.text = firm.wholesalePriceNo ?? '';
          _invoiceCompanyController.text = firm.invoiceCompany ?? '';

          _generalDiscountController.text = firm.generalDiscount?.toString() ?? '';
          _paymentMethodController.text = firm.paymentMethod ?? '';
          _taxOfficeController.text = firm.taxOffice ?? '';
          _taxNoController.text = firm.taxNo ?? '';
          _isEInvoice = firm.isEInvoice;
          _cargoCodeController.text = firm.cargoCode ?? '';
          _purchasePriceNoController.text = firm.purchasePriceNo ?? '';
          _paymentVknController.text = firm.paymentVkn ?? '';
          _ibanController.text = firm.iban ?? '';
          _initialized = true;
        }

        final updatedAt = firm?.updatedAt;
        final updatedText = updatedAt == null
            ? ''
            : DateFormat('yyyy-MM-dd HH:mm', 'tr_TR').format(updatedAt.toLocal());

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text('Firma Tanımlama', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                if (!isNew && firm != null)
                  Text(
                    updatedText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionFrame(
              title: 'Genel Bilgiler',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _leftForm(canEdit: canEdit)),
                  const SizedBox(width: 12),
                  Expanded(child: _rightForm(canEdit: canEdit)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                SizedBox(
                  width: 120,
                  child: OutlinedButton(
                    onPressed: () => context.go('/crm/firms'),
                    child: const Text('Ara'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: FilledButton(
                    onPressed: canEdit
                        ? () async {
                            final draft = _draftFromForm();
                            if ((draft.firmName ?? '').trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Firma Adı gerekli')),
                              );
                              return;
                            }

                            if (isNew) {
                              final id = await ref.read(crmFirmsProvider.notifier).create(draft);
                              if (!context.mounted) return;
                              if (id != null) context.go('/crm/firms/$id');
                            } else {
                              await ref.read(crmFirmsProvider.notifier).update(widget.firmId, draft);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Kaydedildi.')),
                                );
                              }
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
                    onPressed: () {
                      _clearForm();
                      setState(() {});
                    },
                    child: const Text('İptal'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _leftForm({required bool canEdit}) {
    return _FormTable(
      rows: [
        _FormRow(label: 'Firma Adı', child: TextField(controller: _firmNameController, enabled: canEdit)),
        _FormRow(label: 'Firma Ticari Adı', child: TextField(controller: _tradeNameController, enabled: canEdit)),
        _FormRow(label: 'Firma Entegre Kodu', child: TextField(controller: _integrationCodeController, enabled: canEdit)),
        _FormRow(label: 'Firma Türü', child: TextField(controller: _firmTypeController, enabled: canEdit)),
        _FormRow(
          label: 'Güncel Statü',
          child: CheckboxListTile(
            value: _isCurrent,
            onChanged: canEdit ? (v) => setState(() => _isCurrent = v ?? true) : null,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(''),
          ),
        ),
        _FormRow(label: 'Müşteri Ticari Grubu', child: TextField(controller: _customerGroupController, enabled: canEdit)),
        _FormRow(label: 'Firma E-Mail', child: TextField(controller: _emailController, enabled: canEdit)),
        _FormRow(label: 'Fiyat No', child: TextField(controller: _priceNoController, enabled: canEdit)),
        _FormRow(label: 'Toptan Satış Fiyat No', child: TextField(controller: _wholesalePriceNoController, enabled: canEdit)),
        _FormRow(label: 'Fatura Firması', child: TextField(controller: _invoiceCompanyController, enabled: canEdit)),
      ],
    );
  }

  Widget _rightForm({required bool canEdit}) {
    return _FormTable(
      rows: [
        _FormRow(label: 'Genel İskonto', child: TextField(controller: _generalDiscountController, enabled: canEdit)),
        _FormRow(label: 'Ödeme Şekli', child: TextField(controller: _paymentMethodController, enabled: canEdit)),
        _FormRow(label: 'Vergi Dairesi', child: TextField(controller: _taxOfficeController, enabled: canEdit)),
        _FormRow(label: 'Vergi Numarası', child: TextField(controller: _taxNoController, enabled: canEdit)),
        _FormRow(
          label: 'E-Fatura Kontrol',
          child: CheckboxListTile(
            value: _isEInvoice,
            onChanged: canEdit ? (v) => setState(() => _isEInvoice = v ?? false) : null,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(''),
          ),
        ),
        _FormRow(label: 'Karkas Kodu', child: TextField(controller: _cargoCodeController, enabled: canEdit)),
        _FormRow(label: 'Alım Fiyat No', child: TextField(controller: _purchasePriceNoController, enabled: canEdit)),
        _FormRow(label: 'Ödeme VKN', child: TextField(controller: _paymentVknController, enabled: canEdit)),
        _FormRow(label: 'IBAN', child: TextField(controller: _ibanController, enabled: canEdit)),
      ],
    );
  }

  CrmFirmDraft _draftFromForm() {
    double? parseMoney(String v) {
      final raw = v.trim().replaceAll(',', '.');
      return double.tryParse(raw);
    }

    return CrmFirmDraft(
      firmName: _firmNameController.text.trim(),
      tradeName: _tradeNameController.text.trim(),
      integrationCode: _integrationCodeController.text.trim(),
      firmType: _firmTypeController.text.trim(),
      isCurrent: _isCurrent,
      customerGroup: _customerGroupController.text.trim(),
      email: _emailController.text.trim(),
      priceNo: _priceNoController.text.trim(),
      wholesalePriceNo: _wholesalePriceNoController.text.trim(),
      invoiceCompany: _invoiceCompanyController.text.trim(),
      generalDiscount: parseMoney(_generalDiscountController.text),
      paymentMethod: _paymentMethodController.text.trim(),
      taxOffice: _taxOfficeController.text.trim(),
      taxNo: _taxNoController.text.trim(),
      isEInvoice: _isEInvoice,
      cargoCode: _cargoCodeController.text.trim(),
      purchasePriceNo: _purchasePriceNoController.text.trim(),
      paymentVkn: _paymentVknController.text.trim(),
      iban: _ibanController.text.trim(),
    );
  }

  void _clearForm() {
    _firmNameController.clear();
    _tradeNameController.clear();
    _integrationCodeController.clear();
    _firmTypeController.clear();
    _isCurrent = true;
    _customerGroupController.clear();
    _emailController.clear();
    _priceNoController.clear();
    _wholesalePriceNoController.clear();
    _invoiceCompanyController.clear();
    _generalDiscountController.clear();
    _paymentMethodController.clear();
    _taxOfficeController.clear();
    _taxNoController.clear();
    _isEInvoice = false;
    _cargoCodeController.clear();
    _purchasePriceNoController.clear();
    _paymentVknController.clear();
    _ibanController.clear();
  }
}

class _SectionFrame extends StatelessWidget {
  const _SectionFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: const Color(0xFFE6E6E6),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _FormTable extends StatelessWidget {
  const _FormTable({required this.rows});

  final List<_FormRow> rows;

  @override
  Widget build(BuildContext context) {
    const labelBg = Color(0xFF9BB6D4);
    const border = Color(0xFF999999);

    Widget labelCell(String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: labelBg,
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
    }

    Widget valueCell(Widget child) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: child,
      );
    }

    return Table(
      columnWidths: const {
        0: FixedColumnWidth(180),
        1: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: const TableBorder(
        top: BorderSide(color: border),
        left: BorderSide(color: border),
        right: BorderSide(color: border),
      ),
      children: [
        for (final r in rows)
          TableRow(
            children: [
              labelCell(r.label),
              valueCell(r.child),
            ],
          ),
      ],
    );
  }
}

class _FormRow {
  const _FormRow({required this.label, required this.child});

  final String label;
  final Widget child;
}
