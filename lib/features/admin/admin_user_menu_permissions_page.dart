import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api_client.dart';
import '../../app/config.dart';
import '../../domain/stores.dart';
import '../../legacy/crm_menu.dart';

class AdminUserMenuPermissionsPage extends ConsumerStatefulWidget {
  const AdminUserMenuPermissionsPage({super.key});

  @override
  ConsumerState<AdminUserMenuPermissionsPage> createState() =>
      _AdminUserMenuPermissionsPageState();
}

class _AdminUserMenuPermissionsPageState
    extends ConsumerState<AdminUserMenuPermissionsPage> {
  String? _selectedUserId;
  String? _transferToUserId;
  var _busy = false;
  final Set<String> _selectedRefs = {};
  Set<String>? _clipboard;

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);
    final crmMenu = ref.watch(crmMenuProvider);
    final sections = [
      _prosmartSection(),
      ...?crmMenu.asData?.value,
    ];
    final canToggleAll = !_busy && _selectedUserId != null && crmMenu.asData != null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Kullanıcı Menü Yetkilendirme',
                style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            SizedBox(
              width: 160,
              child: OutlinedButton(
                onPressed: canToggleAll ? () => _selectAll(sections) : null,
                child: const Text('Tümünü Aç'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 160,
              child: OutlinedButton(
                onPressed: _busy || _selectedUserId == null ? null : _clearAll,
                child: const Text('Tümünü Kapat'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: FilledButton(
                onPressed: _busy || _selectedUserId == null ? null : _save,
                child: const Text('Kaydet'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: OutlinedButton(
                onPressed: _busy ? null : () => context.go('/'),
                child: const Text('Kapat'),
              ),
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
                DropdownButtonFormField<String?>(
                  initialValue: _selectedUserId,
                  decoration: const InputDecoration(labelText: 'Kullanıcı'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Seçiniz')),
                    for (final u in users)
                      DropdownMenuItem(
                        value: u.id,
                        child: Text('${u.username} • ${u.displayName}'),
                      ),
                  ],
                  onChanged: (v) async {
                    setState(() {
                      _selectedUserId = v;
                      _selectedRefs.clear();
                    });
                    if (v != null) {
                      await _loadForUser(v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: OutlinedButton(
                        onPressed: _busy || _selectedUserId == null ? null : _copyToClipboard,
                        child: const Text('Kopyala'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 140,
                      child: OutlinedButton(
                        onPressed: _busy || _selectedUserId == null || _clipboard == null ? null : _pasteFromClipboard,
                        child: const Text('Yapıştır'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: _transferToUserId,
                        decoration: const InputDecoration(labelText: 'Aktarılacak kullanıcı'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Seçiniz')),
                          for (final u in users)
                            if (u.id != _selectedUserId)
                              DropdownMenuItem(
                                value: u.id,
                                child: Text('${u.username} • ${u.displayName}'),
                              ),
                        ],
                        onChanged: _busy ? null : (v) => setState(() => _transferToUserId = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 140,
                      child: FilledButton.tonal(
                        onPressed: _busy || _selectedUserId == null || _transferToUserId == null ? null : _transferToUser,
                        child: const Text('Aktar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                crmMenu.when(
                  data: (crmSections) {
                    if (_selectedUserId == null) {
                      return const Text('Önce kullanıcı seçiniz.');
                    }

                    final allSections = [_prosmartSection(), ...crmSections];
                    return Column(
                      children: [
                        for (final s in allSections)
                          _PermissionSection(
                            title: s.title,
                            nodes: s.nodes,
                            selectedRefs: _selectedRefs,
                            onToggleRef: _toggleRef,
                            onToggleNode: _toggleNode,
                          ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, st) => const Text('Menü okunamadı.'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadForUser(String userId) async {
    setState(() => _busy = true);
    try {
      if (!AppConfig.hasApi) {
        _selectedRefs.addAll(const ['insert_firma', 'insert_depo', 'insert_recete']);
        return;
      }

      final dio = ref.read(dioProvider);
      final res = await dio.get<List<dynamic>>(
        '/user-menu-permissions',
        queryParameters: {'userId': userId},
      );
      final data = res.data ?? const [];
      _selectedRefs
        ..clear()
        ..addAll([for (final x in data) x.toString()]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yetkiler okunamadı.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final userId = _selectedUserId;
    if (userId == null) return;

    setState(() => _busy = true);
    try {
      if (AppConfig.hasApi) {
        final dio = ref.read(dioProvider);
        await dio.put<Map<String, dynamic>>(
          '/user-menu-permissions/$userId',
          data: {'legacyRefs': _selectedRefs.toList()..sort()},
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaydedildi.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaydetme başarısız.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleRef(String legacyRef, bool on) {
    setState(() {
      if (on) {
        _selectedRefs.add(legacyRef);
      } else {
        _selectedRefs.remove(legacyRef);
      }
    });
  }

  void _toggleNode(CrmMenuNode node, bool on) {
    final refs = _collectLeafRefs(node);
    setState(() {
      if (on) {
        _selectedRefs.addAll(refs);
      } else {
        _selectedRefs.removeAll(refs);
      }
    });
  }

  CrmMenuSection _prosmartSection() {
    return const CrmMenuSection(
      title: 'Prosmart Menü',
      nodes: [
        CrmMenuNode(title: 'Dashboard', icon: Icons.dashboard_outlined, legacyRef: 'ps_dashboard'),
        CrmMenuNode(title: 'Kasa İcmal', icon: Icons.receipt_long_outlined, legacyRef: 'ps_reconciliations'),
        CrmMenuNode(title: 'Evrak', icon: Icons.upload_file_outlined, legacyRef: 'ps_documents'),
        CrmMenuNode(title: 'Onay Bekleyenler', icon: Icons.verified_outlined, legacyRef: 'ps_pending_approvals'),
        CrmMenuNode(title: 'Firma Tanımlama', icon: Icons.business_outlined, legacyRef: 'find_firma'),
        CrmMenuNode(title: 'Şube Güncelleme', icon: Icons.storefront_outlined, legacyRef: 'insert_sube'),
        CrmMenuNode(title: 'Birim Seti', icon: Icons.straighten_outlined, legacyRef: 'insert_birim_seti'),
        CrmMenuNode(title: 'Hesap Dönemi', icon: Icons.date_range_outlined, legacyRef: 'insert_hesap_donem'),
        CrmMenuNode(title: 'Gelir Merkezi', icon: Icons.account_balance_outlined, legacyRef: 'insert_gelir_merkezi'),
        CrmMenuNode(title: 'Ödeme Türleri', icon: Icons.credit_card_outlined, legacyRef: 'insert_odeme_turu'),
        CrmMenuNode(title: 'Masraf Tipleri', icon: Icons.payments_outlined, legacyRef: 'insert_masraf_tipleri'),
        CrmMenuNode(title: 'Kasa', icon: Icons.receipt_long_outlined, legacyRef: 'insert_kasa_tanim'),
        CrmMenuNode(title: 'İş İstasyonları', icon: Icons.point_of_sale_outlined, legacyRef: 'insert_istasyon'),
        CrmMenuNode(title: 'Düşüm Deposu', icon: Icons.warehouse_outlined, legacyRef: 'insert_dusum_depo'),
        CrmMenuNode(title: 'Min/Max Tanımı', icon: Icons.tune_outlined, legacyRef: 'min_max_tanimi'),
        CrmMenuNode(title: 'Üretilmeyecek Ürünler', icon: Icons.block_outlined, legacyRef: 'insert_uretilmeyecek_urunler'),
        CrmMenuNode(title: 'Ürünler', icon: Icons.shopping_bag_outlined, legacyRef: 'urun_tree'),
        CrmMenuNode(title: 'Depolar', icon: Icons.warehouse_outlined, legacyRef: 'insert_depo'),
        CrmMenuNode(title: 'Stok Hareketleri', icon: Icons.inventory_2_outlined, legacyRef: 'stok_haraketleri'),
        CrmMenuNode(title: 'Eldeki Stok', icon: Icons.view_list_outlined, legacyRef: 'eldeki_stok'),
        CrmMenuNode(title: 'Fatura', icon: Icons.request_quote_outlined, legacyRef: 'ps_inv_invoices'),
        CrmMenuNode(title: 'Depo Sayım', icon: Icons.fact_check_outlined, legacyRef: 'insert_sayim_fisi'),
        CrmMenuNode(title: 'Reçete', icon: Icons.menu_book_outlined, legacyRef: 'insert_recete'),
        CrmMenuNode(title: 'Ana Grup Satış', icon: Icons.bar_chart_outlined, legacyRef: 'ps_report_ana_grup_satis'),
        CrmMenuNode(title: 'Şifre Değiştirme', icon: Icons.password_outlined, legacyRef: 'update_sifre'),
        CrmMenuNode(title: 'Kullanıcı Tanımlama', icon: Icons.people_outline, legacyRef: 'insert_kullanici'),
        CrmMenuNode(title: 'Kullanıcı Yetkileri', icon: Icons.admin_panel_settings_outlined, legacyRef: 'insert_kullanici_yetki'),
        CrmMenuNode(title: 'Ayarlar', icon: Icons.settings_outlined, legacyRef: 'ps_settings'),
      ],
    );
  }

  void _selectAll(List<CrmMenuSection> sections) {
    final refs = <String>{};
    for (final s in sections) {
      for (final n in s.nodes) {
        refs.addAll(_collectLeafRefs(n));
      }
    }
    setState(() {
      _selectedRefs
        ..clear()
        ..addAll(refs);
    });
  }

  void _clearAll() {
    setState(() {
      _selectedRefs.clear();
    });
  }

  void _copyToClipboard() {
    _clipboard = {..._selectedRefs};
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Kopyalandı (${_clipboard!.length})')),
    );
  }

  void _pasteFromClipboard() {
    final clip = _clipboard;
    if (clip == null) return;
    setState(() {
      _selectedRefs
        ..clear()
        ..addAll(clip);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Yapıştırıldı (${clip.length})')),
    );
  }

  Future<void> _transferToUser() async {
    final toUserId = _transferToUserId;
    if (toUserId == null) return;
    setState(() => _busy = true);
    try {
      if (AppConfig.hasApi) {
        final dio = ref.read(dioProvider);
        await dio.put<Map<String, dynamic>>(
          '/user-menu-permissions/$toUserId',
          data: {'legacyRefs': _selectedRefs.toList()..sort()},
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yetkiler aktarıldı.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktarma başarısız.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _collectLeafRefs(CrmMenuNode node) {
    if (node.children == null || node.children!.isEmpty) {
      final ref = node.legacyRef ?? node.subtitle ?? '';
      return ref.isEmpty ? const [] : [ref];
    }
    final out = <String>[];
    for (final c in node.children!) {
      out.addAll(_collectLeafRefs(c));
    }
    return out;
  }
}

class _PermissionSection extends StatelessWidget {
  const _PermissionSection({
    required this.title,
    required this.nodes,
    required this.selectedRefs,
    required this.onToggleRef,
    required this.onToggleNode,
  });

  final String title;
  final List<CrmMenuNode> nodes;
  final Set<String> selectedRefs;
  final void Function(String legacyRef, bool on) onToggleRef;
  final void Function(CrmMenuNode node, bool on) onToggleNode;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title),
      children: [
        for (final n in nodes)
          _PermissionNode(
            node: n,
            selectedRefs: selectedRefs,
            onToggleRef: onToggleRef,
            onToggleNode: onToggleNode,
          ),
      ],
    );
  }
}

class _PermissionNode extends StatelessWidget {
  const _PermissionNode({
    required this.node,
    required this.selectedRefs,
    required this.onToggleRef,
    required this.onToggleNode,
  });

  final CrmMenuNode node;
  final Set<String> selectedRefs;
  final void Function(String legacyRef, bool on) onToggleRef;
  final void Function(CrmMenuNode node, bool on) onToggleNode;

  @override
  Widget build(BuildContext context) {
    final children = node.children ?? const [];
    if (children.isEmpty) {
      final ref = node.legacyRef ?? node.subtitle ?? '';
      if (ref.isEmpty) return const SizedBox.shrink();
      final checked = selectedRefs.contains(ref);
      return CheckboxListTile(
        dense: true,
        value: checked,
        onChanged: (v) => onToggleRef(ref, v ?? false),
        title: Text(node.title),
        subtitle: node.subtitle == null ? null : Text(node.subtitle!),
      );
    }

    final leafRefs = _collectLeafRefs(node);
    final selectedCount = leafRefs.where(selectedRefs.contains).length;
    final allSelected = selectedCount == leafRefs.length && leafRefs.isNotEmpty;
    final noneSelected = selectedCount == 0;
    final tristateValue = noneSelected ? false : (allSelected ? true : null);

    return ExpansionTile(
      title: Row(
        children: [
          Checkbox(
            tristate: true,
            value: tristateValue,
            onChanged: (v) => onToggleNode(node, v == true),
          ),
          Expanded(child: Text(node.title)),
        ],
      ),
      children: [
        for (final c in children)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: _PermissionNode(
              node: c,
              selectedRefs: selectedRefs,
              onToggleRef: onToggleRef,
              onToggleNode: onToggleNode,
            ),
          ),
      ],
    );
  }

  List<String> _collectLeafRefs(CrmMenuNode node) {
    final children = node.children ?? const [];
    if (children.isEmpty) {
      final ref = node.legacyRef ?? node.subtitle ?? '';
      return ref.isEmpty ? const [] : [ref];
    }
    final out = <String>[];
    for (final c in children) {
      out.addAll(_collectLeafRefs(c));
    }
    return out;
  }
}
