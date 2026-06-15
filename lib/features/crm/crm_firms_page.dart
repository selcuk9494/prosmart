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
  final _taxController = TextEditingController();
  String _statusFilter = 'active';
  String _typeFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    _taxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).asData?.value;
    final role = session?.role ?? UserRole.branchUser;
    final canEdit = role == UserRole.manager || role == UserRole.accounting;

    final query = _searchController.text.trim().toLowerCase();
    ref.read(crmFirmsProvider.notifier).setQuery(_searchController.text);
    final allItems = ref.watch(crmFirmsProvider);
    final firmTypes = {
      for (final item in allItems)
        if ((item.firmType ?? '').trim().isNotEmpty) item.firmType!.trim(),
    }.toList()..sort();
    final items = [
      for (final item in allItems)
        if (_matchesFilters(item, query)) item,
    ];
    final activeCount = allItems.where((e) => e.isActive).length;
    final currentCount = allItems.where((e) => e.isCurrent).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _NbosToolbar(
          title: 'Kişi-Firma Girişi',
          subtitle: 'Adres defteri, firma arama ve cari kart yönetimi',
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(crmFirmsProvider.notifier).refresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Yenile'),
            ),
            FilledButton.icon(
              onPressed: canEdit ? () => context.go('/crm/firms/new') : null,
              icon: const Icon(Icons.add),
              label: const Text('Yeni Firma'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 280,
              child: _AddressTree(
                totalCount: allItems.length,
                activeCount: activeCount,
                currentCount: currentCount,
                selected: _statusFilter,
                onSelected: (value) => setState(() => _statusFilter = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  _SectionFrame(
                    title: 'Firma Ara',
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 320,
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              labelText: 'Firma / ticari ad / e-posta',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _taxController,
                            decoration: const InputDecoration(
                              labelText: 'Vergi no / VKN',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: DropdownButtonFormField<String>(
                            initialValue: _typeFilter,
                            decoration: const InputDecoration(
                              labelText: 'Firma türü',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text('Tümü'),
                              ),
                              for (final type in firmTypes)
                                DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _typeFilter = value ?? 'all'),
                          ),
                        ),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'active',
                              label: Text('Aktif'),
                              icon: Icon(Icons.check_circle_outline),
                            ),
                            ButtonSegment(
                              value: 'all',
                              label: Text('Tümü'),
                              icon: Icon(Icons.list_alt_outlined),
                            ),
                            ButtonSegment(
                              value: 'passive',
                              label: Text('Pasif'),
                              icon: Icon(Icons.block_outlined),
                            ),
                          ],
                          selected: {_statusFilter},
                          onSelectionChanged: (value) =>
                              setState(() => _statusFilter = value.first),
                        ),
                        OutlinedButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.clear),
                          label: const Text('Temizle'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FirmResultsTable(
                    items: items,
                    canEdit: canEdit,
                    onOpen: (id) => context.go('/crm/firms/$id'),
                    onToggle: (id) =>
                        ref.read(crmFirmsProvider.notifier).toggleActive(id),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _matchesFilters(CrmFirm item, String query) {
    final taxQuery = _taxController.text.trim().toLowerCase();
    final searchable = [
      item.firmName,
      item.tradeName,
      item.integrationCode,
      item.email,
      item.taxNo,
      item.paymentVkn,
      item.firmType,
      item.customerGroup,
    ].whereType<String>().join(' ').toLowerCase();

    final matchesQuery = query.isEmpty || searchable.contains(query);
    final matchesTax =
        taxQuery.isEmpty ||
        (item.taxNo ?? '').toLowerCase().contains(taxQuery) ||
        (item.paymentVkn ?? '').toLowerCase().contains(taxQuery);
    final matchesType =
        _typeFilter == 'all' || (item.firmType ?? '').trim() == _typeFilter;
    final matchesStatus = switch (_statusFilter) {
      'active' => item.isActive,
      'passive' => !item.isActive,
      'current' => item.isCurrent,
      _ => true,
    };
    return matchesQuery && matchesTax && matchesType && matchesStatus;
  }

  void _clearFilters() {
    _searchController.clear();
    _taxController.clear();
    setState(() {
      _statusFilter = 'active';
      _typeFilter = 'all';
    });
  }
}

class _NbosToolbar extends StatelessWidget {
  const _NbosToolbar({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: scheme.primary, width: 4)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.business_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(subtitle),
                ],
              ),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }
}

class _AddressTree extends StatelessWidget {
  const _AddressTree({
    required this.totalCount,
    required this.activeCount,
    required this.currentCount,
    required this.selected,
    required this.onSelected,
  });

  final int totalCount;
  final int activeCount;
  final int currentCount;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Adres Defteri',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            _treeTile(
              context,
              icon: Icons.folder_open_outlined,
              title: 'Tüm Firmalar',
              count: totalCount,
              value: 'all',
            ),
            _treeTile(
              context,
              icon: Icons.check_circle_outline,
              title: 'Aktif Firmalar',
              count: activeCount,
              value: 'active',
            ),
            _treeTile(
              context,
              icon: Icons.account_tree_outlined,
              title: 'Güncel Cari Kartlar',
              count: currentCount,
              value: 'current',
            ),
            _treeTile(
              context,
              icon: Icons.block_outlined,
              title: 'Pasif Firmalar',
              count: totalCount - activeCount,
              value: 'passive',
            ),
            const Divider(),
            const ListTile(
              dense: true,
              leading: Icon(Icons.person_outline),
              title: Text('Kişi kartları'),
              subtitle: Text('Bir sonraki fazda ayrı model'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _treeTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required int count,
    required String value,
  }) {
    final isSelected = selected == value;
    return ListTile(
      dense: true,
      selected: isSelected,
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(count.toString()),
      onTap: () => onSelected(value),
    );
  }
}

class _FirmResultsTable extends StatelessWidget {
  const _FirmResultsTable({
    required this.items,
    required this.canEdit,
    required this.onOpen,
    required this.onToggle,
  });

  final List<CrmFirm> items;
  final bool canEdit;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Arama kriterlerine uygun firma bulunamadı.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Firma Listesi',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text('${items.length} kayıt'),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.primaryContainer,
                ),
                columns: const [
                  DataColumn(label: Text('İşlem')),
                  DataColumn(label: Text('Firma Adı')),
                  DataColumn(label: Text('Ticari Adı')),
                  DataColumn(label: Text('Tür')),
                  DataColumn(label: Text('Vergi No')),
                  DataColumn(label: Text('E-Posta')),
                  DataColumn(label: Text('Cari')),
                  DataColumn(label: Text('Aktif')),
                ],
                rows: [
                  for (var i = 0; i < items.length; i++)
                    DataRow(
                      color: WidgetStatePropertyAll(
                        i.isEven
                            ? const Color(0xFFFFFFFF)
                            : const Color(0xFFF4F4F4),
                      ),
                      cells: [
                        DataCell(
                          IconButton(
                            tooltip: 'Kartı aç',
                            onPressed: () => onOpen(items[i].id),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        ),
                        DataCell(
                          Text(items[i].firmName),
                          onTap: () => onOpen(items[i].id),
                        ),
                        DataCell(Text(items[i].tradeName ?? '')),
                        DataCell(Text(items[i].firmType ?? '')),
                        DataCell(Text(items[i].taxNo ?? '')),
                        DataCell(Text(items[i].email ?? '')),
                        DataCell(
                          Chip(
                            label: Text(items[i].isCurrent ? 'Güncel' : 'Eski'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        DataCell(
                          Switch(
                            value: items[i].isActive,
                            onChanged: canEdit
                                ? (_) => onToggle(items[i].id)
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

    final firmAsync = isNew
        ? const AsyncValue<CrmFirm?>.data(null)
        : ref.watch(crmFirmDetailProvider(widget.firmId)).whenData((v) => v);

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

          _generalDiscountController.text =
              firm.generalDiscount?.toString() ?? '';
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
            : DateFormat(
                'yyyy-MM-dd HH:mm',
                'tr_TR',
              ).format(updatedAt.toLocal());

        return DefaultTabController(
          length: 3,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _NbosToolbar(
                title: isNew ? 'Yeni Firma' : 'Firma Kartı',
                subtitle: isNew
                    ? 'NBOS kişi-firma giriş yapısına uygun yeni cari kart'
                    : '${firm?.firmName ?? ''} ${updatedText.isEmpty ? '' : '• Son güncelleme $updatedText'}',
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => context.go('/crm/firms'),
                    icon: const Icon(Icons.search),
                    label: const Text('Firma Ara'),
                  ),
                  FilledButton.icon(
                    onPressed: canEdit ? () => _saveFirm(isNew: isNew) : null,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Kaydet'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _clearForm();
                      setState(() {});
                    },
                    icon: const Icon(Icons.undo_outlined),
                    label: const Text('Temizle'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(
                          icon: Icon(Icons.business_outlined),
                          text: 'Genel Bilgiler',
                        ),
                        Tab(
                          icon: Icon(Icons.receipt_long_outlined),
                          text: 'Muhasebe',
                        ),
                        Tab(
                          icon: Icon(Icons.hub_outlined),
                          text: 'Entegrasyon',
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 560,
                      child: TabBarView(
                        children: [
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: _leftForm(canEdit: canEdit),
                          ),
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: _rightForm(canEdit: canEdit),
                          ),
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(12),
                            child: _integrationForm(canEdit: canEdit),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveFirm({required bool isNew}) async {
    final draft = _draftFromForm();
    if ((draft.firmName ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Firma Adı gerekli')));
      return;
    }

    if (isNew) {
      final id = await ref.read(crmFirmsProvider.notifier).create(draft);
      if (!mounted) return;
      if (id != null) context.go('/crm/firms/$id');
    } else {
      await ref.read(crmFirmsProvider.notifier).update(widget.firmId, draft);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Kaydedildi.')));
      }
    }
  }

  Widget _leftForm({required bool canEdit}) {
    return _FormTable(
      rows: [
        _FormRow(
          label: 'Firma Adı',
          child: TextField(controller: _firmNameController, enabled: canEdit),
        ),
        _FormRow(
          label: 'Firma Ticari Adı',
          child: TextField(controller: _tradeNameController, enabled: canEdit),
        ),
        _FormRow(
          label: 'Firma Türü',
          child: TextField(controller: _firmTypeController, enabled: canEdit),
        ),
        _FormRow(
          label: 'Güncel Statü',
          child: CheckboxListTile(
            value: _isCurrent,
            onChanged: canEdit
                ? (v) => setState(() => _isCurrent = v ?? true)
                : null,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(''),
          ),
        ),
        _FormRow(
          label: 'Müşteri Ticari Grubu',
          child: TextField(
            controller: _customerGroupController,
            enabled: canEdit,
          ),
        ),
        _FormRow(
          label: 'Firma E-Mail',
          child: TextField(controller: _emailController, enabled: canEdit),
        ),
        _FormRow(
          label: 'Fiyat No',
          child: TextField(controller: _priceNoController, enabled: canEdit),
        ),
        _FormRow(
          label: 'Toptan Satış Fiyat No',
          child: TextField(
            controller: _wholesalePriceNoController,
            enabled: canEdit,
          ),
        ),
      ],
    );
  }

  Widget _rightForm({required bool canEdit}) {
    return _FormTable(
      rows: [
        _FormRow(
          label: 'Genel İskonto',
          child: TextField(
            controller: _generalDiscountController,
            enabled: canEdit,
          ),
        ),
        _FormRow(
          label: 'Ödeme Şekli',
          child: TextField(
            controller: _paymentMethodController,
            enabled: canEdit,
          ),
        ),
        _FormRow(
          label: 'Vergi Dairesi',
          child: TextField(controller: _taxOfficeController, enabled: canEdit),
        ),
        _FormRow(
          label: 'Vergi Numarası',
          child: TextField(controller: _taxNoController, enabled: canEdit),
        ),
        _FormRow(
          label: 'E-Fatura Kontrol',
          child: CheckboxListTile(
            value: _isEInvoice,
            onChanged: canEdit
                ? (v) => setState(() => _isEInvoice = v ?? false)
                : null,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(''),
          ),
        ),
        _FormRow(
          label: 'Karkas Kodu',
          child: TextField(controller: _cargoCodeController, enabled: canEdit),
        ),
        _FormRow(
          label: 'Alım Fiyat No',
          child: TextField(
            controller: _purchasePriceNoController,
            enabled: canEdit,
          ),
        ),
      ],
    );
  }

  Widget _integrationForm({required bool canEdit}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormTable(
          rows: [
            _FormRow(
              label: 'NBOS Ref',
              child: const SelectableText('insert_firma / find_firma'),
            ),
            _FormRow(
              label: 'Firma Entegre Kodu',
              child: TextField(
                controller: _integrationCodeController,
                enabled: canEdit,
              ),
            ),
            _FormRow(
              label: 'Fatura Firması',
              child: TextField(
                controller: _invoiceCompanyController,
                enabled: canEdit,
              ),
            ),
            _FormRow(
              label: 'Ödeme VKN',
              child: TextField(
                controller: _paymentVknController,
                enabled: canEdit,
              ),
            ),
            _FormRow(
              label: 'IBAN',
              child: TextField(controller: _ibanController, enabled: canEdit),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionFrame(
          title: 'Bağlı Kayıtlar',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              Chip(avatar: Icon(Icons.person_outline), label: Text('Kişiler')),
              Chip(
                avatar: Icon(Icons.receipt_long_outlined),
                label: Text('Faturalar'),
              ),
              Chip(
                avatar: Icon(Icons.shopping_cart_outlined),
                label: Text('Siparişler'),
              ),
              Chip(
                avatar: Icon(Icons.account_balance_outlined),
                label: Text('Cari Hareketler'),
              ),
            ],
          ),
        ),
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
          Padding(padding: const EdgeInsets.all(12), child: child),
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
      columnWidths: const {0: FixedColumnWidth(180), 1: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: const TableBorder(
        top: BorderSide(color: border),
        left: BorderSide(color: border),
        right: BorderSide(color: border),
      ),
      children: [
        for (final r in rows)
          TableRow(children: [labelCell(r.label), valueCell(r.child)]),
      ],
    );
  }
}

class _FormRow {
  const _FormRow({required this.label, required this.child});

  final String label;
  final Widget child;
}
