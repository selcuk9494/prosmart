import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xml/xml.dart';

import '../app/api_client.dart';
import '../app/config.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_models.dart';

final crmMenuProvider =
    FutureProvider<List<CrmMenuSection>>((ref) async {
  final session = ref.watch(authControllerProvider).asData?.value;
  final base = await loadCrmMenu();

  if (!AppConfig.hasApi || session == null) return base;
  if (session.role == UserRole.manager) return base;

  final allowed = await ref.watch(myMenuPermissionsProvider.future);
  if (allowed.isEmpty) return const [];
  final allowedSet = allowed.map((e) => e.toLowerCase()).toSet();

  return [
    for (final s in base)
      s.copyWith(nodes: _filterNodesByPermission(s.nodes, allowedSet)),
  ].where((s) => s.nodes.isNotEmpty).toList();
});

final myMenuPermissionsProvider = FutureProvider<List<String>>((ref) async {
  final session = ref.watch(authControllerProvider).asData?.value;
  if (!AppConfig.hasApi || session == null) return const [];
  if (session.role == UserRole.manager) return const [];
  final dio = ref.read(dioProvider);
  final res = await dio.get<List<dynamic>>('/me/menu-permissions');
  final data = res.data ?? const [];
  return [for (final x in data) x.toString()];
});

Future<List<CrmMenuSection>> loadCrmMenu() async {
  final xmlString = await rootBundle.loadString('NBOS/yetki/CrmMenu.xml');
  final doc = XmlDocument.parse(xmlString);
  final itemsRoot = doc.rootElement;

  final sections = <CrmMenuSection>[];
  for (final item in itemsRoot.findElements('item')) {
    final name = item.getAttribute('name')?.trim();
    if (name == null || name.isEmpty) continue;

    final nodes = <CrmMenuNode>[];

    for (final subitem in item.findElements('subitem')) {
      final subName = subitem.getAttribute('name')?.trim();
      if (subName == null || subName.isEmpty) continue;
      final children = _parseMenus(subitem);
      if (children.isEmpty) continue;
      nodes.add(
        CrmMenuNode(
          title: subName,
          icon: _guessIcon(subName),
          children: children,
        ),
      );
    }

    nodes.addAll(_parseMenus(item));

    if (nodes.isNotEmpty) {
      sections.add(CrmMenuSection(title: name, nodes: nodes));
    }
  }

  return sections;
}

List<CrmMenuNode> _parseMenus(XmlElement element) {
  final result = <CrmMenuNode>[];
  for (final menu in element.findElements('menu')) {
    final title = menu.getAttribute('name')?.trim();
    if (title == null || title.isEmpty) continue;

    var ref = menu.getAttribute('ref')?.trim();
    if (ref == null || ref.isEmpty) continue;
    if (ref.toLowerCase().endsWith('.aspx')) {
      ref = ref.substring(0, ref.length - 5);
    }

    final options = <int>[];
    for (final opt in menu.findElements('options')) {
      final idRaw = opt.getAttribute('id')?.trim();
      final id = int.tryParse(idRaw ?? '');
      if (id != null) options.add(id);
    }

    result.add(
      CrmMenuNode(
        title: title,
        subtitle: ref,
        icon: _guessIcon(title),
        route: _mapRefToRoute(ref),
        legacyRef: ref,
        optionIds: options,
      ),
    );
  }
  return result;
}

List<CrmMenuNode> _filterNodesByPermission(
  List<CrmMenuNode> nodes,
  Set<String> allowedRefsLower,
) {
  final out = <CrmMenuNode>[];
  for (final n in nodes) {
    final children = n.children;
    if (children != null && children.isNotEmpty) {
      final filteredChildren = _filterNodesByPermission(children, allowedRefsLower);
      if (filteredChildren.isNotEmpty) {
        out.add(n.copyWith(children: filteredChildren));
        continue;
      }
    }

    final ref = (n.legacyRef ?? n.subtitle ?? '').trim().toLowerCase();
    if (ref.isNotEmpty && allowedRefsLower.contains(ref)) {
      out.add(n);
    }
  }
  return out;
}

String _mapRefToRoute(String ref) {
  final r = ref.trim().toLowerCase();
  return switch (r) {
    'insert_firma' => '/crm/firms/new',
    'find_firma' => '/crm/firms',
    'insert_gelir_merkezi' => '/crm/income-centers',
    'insert_masraf_tipleri' => '/crm/expense-types',
    'insert_kullanici' => '/admin/users',
    'insert_kullanici_yetki' => '/admin/user-menu-permissions',
    'insert_grup' => '/legacy/$ref',
    'insert_kullanici_grup' => '/legacy/$ref',
    'update_sifre' => '/account/password',
    'insert_odeme_turu' => '/crm/payment-types',
    'insert_sube' => '/crm/branches',
    'insert_birim_seti' => '/crm/unit-sets',
    'insert_hesap_donem' => '/crm/account-periods',
    'insert_istasyon' => '/crm/workstations',
    'insert_kasa_tanim' => '/crm/cash-registers',
    'insert_dusum_depo' => '/crm/waste-warehouse',
    'min_max_tanimi' => '/crm/min-max',
    'insert_uretilmeyecek_urunler' => '/crm/unproduced-products',
    'insert_depo' => '/inv/warehouses',
    'eldeki_stok' => '/inv/onhand',
    'stok_haraketleri' => '/inv/transactions',
    'urun_tree' => '/inv/products',
    'insert_sayim_fisi' => '/inv/counts',
    'insert_recete' => '/inv/recipes',
    'kullanilan_receteler.aspx' => '/inv/recipes',
    _ => '/legacy/$ref',
  };
}

IconData _guessIcon(String text) {
  final t = text.toLowerCase();
  if (t.contains('fatura') || t.contains('irsaliye')) return Icons.request_quote_outlined;
  if (t.contains('depo')) return Icons.warehouse_outlined;
  if (t.contains('sayım') || t.contains('sayim')) return Icons.fact_check_outlined;
  if (t.contains('reçete') || t.contains('recete')) return Icons.menu_book_outlined;
  if (t.contains('maliyet')) return Icons.analytics_outlined;
  if (t.contains('stok')) return Icons.inventory_2_outlined;
  if (t.contains('rapor')) return Icons.summarize_outlined;
  if (t.contains('yetki')) return Icons.admin_panel_settings_outlined;
  if (t.contains('kasa')) return Icons.receipt_long_outlined;
  if (t.contains('sipariş') || t.contains('siparis')) return Icons.shopping_cart_outlined;
  return Icons.circle_outlined;
}

class CrmMenuSection {
  const CrmMenuSection({required this.title, required this.nodes});

  final String title;
  final List<CrmMenuNode> nodes;

  CrmMenuSection copyWith({String? title, List<CrmMenuNode>? nodes}) {
    return CrmMenuSection(
      title: title ?? this.title,
      nodes: nodes ?? this.nodes,
    );
  }
}

class CrmMenuNode {
  const CrmMenuNode({
    required this.title,
    required this.icon,
    this.subtitle,
    this.route,
    this.children,
    this.legacyRef,
    this.optionIds,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? route;
  final List<CrmMenuNode>? children;
  final String? legacyRef;
  final List<int>? optionIds;

  CrmMenuNode copyWith({
    String? title,
    String? subtitle,
    IconData? icon,
    String? route,
    List<CrmMenuNode>? children,
    String? legacyRef,
    List<int>? optionIds,
  }) {
    return CrmMenuNode(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      route: route ?? this.route,
      children: children ?? this.children,
      legacyRef: legacyRef ?? this.legacyRef,
      optionIds: optionIds ?? this.optionIds,
    );
  }
}
