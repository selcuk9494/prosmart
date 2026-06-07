import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/stores.dart';
import '../../legacy/crm_menu.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final session = auth.asData?.value;

    final role = session?.role ?? UserRole.branchUser;
    final location = GoRouterState.of(context).matchedLocation;

    final pendingApprovals = ref.watch(pendingApprovalsCountProvider);
    final mismatches = ref.watch(mismatchesCountProvider);
    final crmMenu = ref.watch(crmMenuProvider);

    final isWide = MediaQuery.sizeOf(context).width >= 1000;
    final menuWidth = isWide ? 360.0 : 320.0;

    final allSections = [
      ..._buildMenu(
      role: role,
      pendingApprovals: pendingApprovals,
      mismatches: mismatches,
      ),
      ..._buildCrmMenuSections(crmMenu),
    ];
    final query = _searchController.text.trim().toLowerCase();
    final sections = query.isEmpty
        ? allSections
        : [
            for (final s in allSections)
              s.copyWith(items: _filterItems(s.items, query)),
          ].where((s) => s.items.isNotEmpty).toList();

    final headerSubtitle = session == null
        ? null
        : '${session.displayName} • ${_roleLabel(session.role)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prosmart'),
        leading: isWide
            ? null
            : Builder(
                builder: (context) {
                  return IconButton(
                    tooltip: 'Menü',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu),
                  );
                },
              ),
        actions: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  headerSubtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).appBarTheme.foregroundColor,
                      ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Çıkış',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(
                child: _SideMenu(
                  headerTitle: 'Prosmart',
                  headerSubtitle: headerSubtitle,
                  searchController: _searchController,
                  sections: sections,
                  selectedLocation: location,
                  onNavigate: (route) {
                    Navigator.of(context).pop();
                    context.go(route);
                  },
                ),
              ),
            ),
      body: Row(
        children: [
          if (isWide)
            SizedBox(
              width: menuWidth,
              child: SafeArea(
                child: _SideMenu(
                  headerTitle: 'Prosmart',
                  headerSubtitle: headerSubtitle,
                  searchController: _searchController,
                  sections: sections,
                  selectedLocation: location,
                  onNavigate: context.go,
                ),
              ),
            ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  List<_MenuItem> _filterItems(List<_MenuItem> items, String query) {
    final filtered = <_MenuItem>[];
    for (final item in items) {
      final children = item.children == null
          ? null
          : _filterItems(item.children!, query);
      final matches = item.title.toLowerCase().contains(query) ||
          (item.subtitle?.toLowerCase().contains(query) ?? false);
      if (matches || (children != null && children.isNotEmpty)) {
        filtered.add(item.copyWith(children: children));
      }
    }
    return filtered;
  }

  List<_MenuSection> _buildCrmMenuSections(
    AsyncValue<List<CrmMenuSection>> crmMenu,
  ) {
    return crmMenu.when(
      data: (sections) {
        return [
          for (final s in sections)
            _MenuSection(
              title: s.title,
              items: [
                for (final n in s.nodes) _fromCrmNode(n),
              ],
            ),
        ];
      },
      loading: () {
        return const [
          _MenuSection(
            title: 'NBOS Menü',
            items: [
              _MenuItem(
                title: 'Yükleniyor…',
                icon: Icons.hourglass_empty,
                enabled: false,
              ),
            ],
          ),
        ];
      },
      error: (e, st) {
        return const [
          _MenuSection(
            title: 'NBOS Menü',
            items: [
              _MenuItem(
                title: 'Menü yüklenemedi',
                subtitle: 'CrmMenu.xml okunamadı',
                icon: Icons.error_outline,
                enabled: false,
              ),
            ],
          ),
        ];
      },
    );
  }

  _MenuItem _fromCrmNode(CrmMenuNode node) {
    return _MenuItem(
      title: node.title,
      subtitle: node.subtitle,
      icon: node.icon,
      route: node.route,
      enabled: true,
      children: node.children == null
          ? null
          : [for (final c in node.children!) _fromCrmNode(c)],
    );
  }

  List<_MenuSection> _buildMenu({
    required UserRole role,
    required int pendingApprovals,
    required int mismatches,
  }) {
    final canManage = role == UserRole.manager;
    final canEditDefinitions = role == UserRole.manager || role == UserRole.accounting;
    return [
      _MenuSection(
        title: 'Kasa Yönetimi',
        items: [
          const _MenuItem(
            title: 'Dashboard',
            subtitle: 'Genel durum',
            icon: Icons.dashboard_outlined,
            route: '/',
          ),
          _MenuItem(
            title: 'Kasa İcmal',
            subtitle: 'Günlük kontroller',
            icon: Icons.receipt_long_outlined,
            route: '/reconciliations',
            badgeCount: mismatches > 0 ? mismatches : null,
            badgeTone: _BadgeTone.warning,
          ),
          const _MenuItem(
            title: 'Evrak',
            subtitle: 'Eksik evrak takibi',
            icon: Icons.upload_file_outlined,
            route: '/documents',
          ),
          _MenuItem(
            title: 'Onay Bekleyenler',
            subtitle: 'Yönetici onayı',
            icon: Icons.verified_outlined,
            route: '/reconciliations?status=submitted',
            enabled: canManage,
            badgeCount: canManage && pendingApprovals > 0 ? pendingApprovals : null,
            badgeTone: _BadgeTone.danger,
          ),
        ],
      ),
      _MenuSection(
        title: 'Tanımlar',
        items: [
          _MenuItem(
            title: 'Firma Tanımlama',
            subtitle: 'Firma kartları',
            icon: Icons.business_outlined,
            route: '/crm/firms',
            enabled: canEditDefinitions,
          ),
          _MenuItem(
            title: 'Şube Güncelleme',
            subtitle: 'Şube tanımları',
            icon: Icons.storefront_outlined,
            route: '/crm/branches',
            enabled: canManage,
          ),
          const _MenuItem(
            title: 'Birim Seti',
            subtitle: 'Birim tanımları',
            icon: Icons.straighten_outlined,
            route: '/crm/unit-sets',
          ),
          const _MenuItem(
            title: 'Hesap Dönemi',
            subtitle: 'Dönem tanımları',
            icon: Icons.date_range_outlined,
            route: '/crm/account-periods',
          ),
          _MenuItem(
            title: 'Gelir Merkezi',
            subtitle: 'Gelir tanımları',
            icon: Icons.account_balance_outlined,
            route: '/crm/income-centers',
            enabled: canEditDefinitions,
          ),
          _MenuItem(
            title: 'Ödeme Türleri',
            subtitle: 'Ödeme tanımları',
            icon: Icons.credit_card_outlined,
            route: '/crm/payment-types',
            enabled: canEditDefinitions,
          ),
          _MenuItem(
            title: 'Masraf Tipleri',
            subtitle: 'Masraf tanımları',
            icon: Icons.payments_outlined,
            route: '/crm/expense-types',
            enabled: canEditDefinitions,
          ),
          _MenuItem(
            title: 'Kasa',
            subtitle: 'Kasa tanımları',
            icon: Icons.receipt_long_outlined,
            route: '/crm/cash-registers',
            enabled: canEditDefinitions,
          ),
          const _MenuItem(
            title: 'İş İstasyonları',
            subtitle: 'POS/terminal',
            icon: Icons.point_of_sale_outlined,
            route: '/crm/workstations',
          ),
          _MenuItem(
            title: 'Düşüm Deposu',
            subtitle: 'Şube düşüm deposu',
            icon: Icons.warehouse_outlined,
            route: '/crm/waste-warehouse',
            enabled: canEditDefinitions,
          ),
          _MenuItem(
            title: 'Min/Max Tanımı',
            subtitle: 'Şube ürün min/max',
            icon: Icons.tune_outlined,
            route: '/crm/min-max',
            enabled: canEditDefinitions,
          ),
          _MenuItem(
            title: 'Üretilmeyecek Ürünler',
            subtitle: 'Ürün bloklama',
            icon: Icons.block_outlined,
            route: '/crm/unproduced-products',
            enabled: canEditDefinitions,
          ),
        ],
      ),
      _MenuSection(
        title: 'Restoran Yönetimi',
        items: const [
          _MenuItem(
            title: 'Ürünler',
            subtitle: 'Ürün kartları',
            icon: Icons.shopping_bag_outlined,
            route: '/inv/products',
          ),
          _MenuItem(
            title: 'Depolar',
            subtitle: 'Depo tanımları',
            icon: Icons.warehouse_outlined,
            route: '/inv/warehouses',
          ),
          _MenuItem(
            title: 'Stok Hareketleri',
            subtitle: 'Giriş/çıkış fişleri',
            icon: Icons.inventory_2_outlined,
            route: '/inv/transactions',
          ),
          _MenuItem(
            title: 'Eldeki Stok',
            subtitle: 'Anlık stok',
            icon: Icons.view_list_outlined,
            route: '/inv/onhand',
          ),
          _MenuItem(
            title: 'Fatura',
            subtitle: 'Gelen/çıkan fatura',
            icon: Icons.request_quote_outlined,
            route: '/inv/invoices',
          ),
          _MenuItem(
            title: 'Depo Sayım',
            subtitle: 'Sayım ve farklar',
            icon: Icons.fact_check_outlined,
            route: '/inv/counts',
          ),
          _MenuItem(
            title: 'Reçete',
            subtitle: 'Ürün reçeteleri',
            icon: Icons.menu_book_outlined,
            route: '/inv/recipes',
          ),
          _MenuItem(
            title: 'Maliyet Analizi',
            subtitle: 'Food cost / rapor',
            icon: Icons.analytics_outlined,
            enabled: false,
          ),
        ],
      ),
      _MenuSection(
        title: 'Raporlar',
        items: const [
          _MenuItem(
            title: 'Ana Grup Satış',
            subtitle: 'OmniRapor',
            icon: Icons.bar_chart_outlined,
            route: '/reports/ana-grup-satis',
          ),
          _MenuItem(
            title: 'Kasa Raporları',
            subtitle: 'PDF/Excel çıktılar',
            icon: Icons.summarize_outlined,
            enabled: false,
          ),
          _MenuItem(
            title: 'Stok Raporları',
            subtitle: 'Giriş/çıkış',
            icon: Icons.query_stats_outlined,
            enabled: false,
          ),
        ],
      ),
      _MenuSection(
        title: 'Hesabım',
        items: const [
          _MenuItem(
            title: 'Şifre Değiştirme',
            subtitle: 'Kullanıcı şifresi',
            icon: Icons.password_outlined,
            route: '/account/password',
          ),
        ],
      ),
      if (canManage)
        _MenuSection(
          title: 'Yönetim',
          items: const [
            _MenuItem(
              title: 'Kullanıcı Tanımlama',
              subtitle: 'Kullanıcı/rol',
              icon: Icons.people_outline,
              route: '/admin/users',
            ),
            _MenuItem(
              title: 'Kullanıcı Yetkileri',
              subtitle: 'Menü yetkisi',
              icon: Icons.admin_panel_settings_outlined,
              route: '/admin/user-menu-permissions',
            ),
            _MenuItem(
              title: 'Ayarlar',
              subtitle: 'Şube/ödeme/masraf',
              icon: Icons.settings_outlined,
              route: '/settings',
            ),
          ],
        ),
    ];
  }

  String _roleLabel(UserRole role) {
    return switch (role) {
      UserRole.manager => 'Yönetici',
      UserRole.accounting => 'Muhasebe',
      UserRole.branchUser => 'Şube',
    };
  }
}

class _SideMenu extends StatefulWidget {
  const _SideMenu({
    required this.headerTitle,
    required this.headerSubtitle,
    required this.searchController,
    required this.sections,
    required this.selectedLocation,
    required this.onNavigate,
  });

  final String headerTitle;
  final String? headerSubtitle;
  final TextEditingController searchController;
  final List<_MenuSection> sections;
  final String selectedLocation;
  final ValueChanged<String> onNavigate;

  @override
  State<_SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<_SideMenu> {
  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant _SideMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController.removeListener(_onSearchChanged);
      widget.searchController.addListener(_onSearchChanged);
    }
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Column(
        children: [
          _MenuHeader(
            title: widget.headerTitle,
            subtitle: widget.headerSubtitle,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: widget.searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Menüde ara…',
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final section in widget.sections)
                  _MenuSectionView(
                    section: section,
                    selectedLocation: widget.selectedLocation,
                    onNavigate: widget.onNavigate,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.title, required this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _MenuSectionView extends StatefulWidget {
  const _MenuSectionView({
    required this.section,
    required this.selectedLocation,
    required this.onNavigate,
  });

  final _MenuSection section;
  final String selectedLocation;
  final ValueChanged<String> onNavigate;

  @override
  State<_MenuSectionView> createState() => _MenuSectionViewState();
}

class _MenuSectionViewState extends State<_MenuSectionView> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: _expanded,
      onExpansionChanged: (v) => setState(() => _expanded = v),
      title: Text(widget.section.title),
      children: [
        for (final item in widget.section.items)
          _MenuNodeTile(
            item: item,
            selectedLocation: widget.selectedLocation,
            onNavigate: widget.onNavigate,
            depth: 0,
          ),
      ],
    );
  }
}

class _MenuNodeTile extends StatelessWidget {
  const _MenuNodeTile({
    required this.item,
    required this.selectedLocation,
    required this.onNavigate,
    required this.depth,
  });

  final _MenuItem item;
  final String selectedLocation;
  final ValueChanged<String> onNavigate;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasChildren = (item.children?.isNotEmpty ?? false);
    final isSelected =
        item.route != null && _matches(selectedLocation, item.route!);
    final canTap = item.enabled && item.route != null;

    final badgeCount = item.badgeCount ?? 0;
    final badge = badgeCount <= 0
        ? null
        : _Badge(
            count: badgeCount,
            tone: item.badgeTone ?? _BadgeTone.neutral,
          );

    final contentPadding = EdgeInsets.only(
      left: 16 + (depth * 12),
      right: 16,
    );

    if (hasChildren) {
      return ExpansionTile(
        tilePadding: contentPadding,
        leading: Icon(item.icon),
        title: Row(
          children: [
            Expanded(child: Text(item.title)),
            badge ?? const SizedBox.shrink(),
          ],
        ),
        subtitle: item.subtitle == null ? null : Text(item.subtitle!),
        children: [
          for (final child in item.children!)
            _MenuNodeTile(
              item: child,
              selectedLocation: selectedLocation,
              onNavigate: onNavigate,
              depth: depth + 1,
            ),
        ],
      );
    }

    return ListTile(
      contentPadding: contentPadding,
      selected: isSelected,
      leading: Icon(item.icon),
      title: Row(
        children: [
          Expanded(child: Text(item.title)),
          badge ?? const SizedBox.shrink(),
        ],
      ),
      subtitle: item.subtitle == null ? null : Text(item.subtitle!),
      enabled: canTap,
      trailing: item.enabled
          ? null
          : Tooltip(
              message: 'Yakında',
              child: Icon(Icons.lock_outline, color: scheme.outline),
            ),
      onTap: canTap ? () => onNavigate(item.route!) : null,
    );
  }

  bool _matches(String location, String route) {
    if (location == route) return true;
    if (route == '/reconciliations' && location.startsWith('/reconciliations')) {
      return true;
    }
    if (route.startsWith('/legacy/') && location == route) {
      return true;
    }
    return false;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.tone});

  final int count;
  final _BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      _BadgeTone.neutral => (scheme.surfaceContainerHighest, scheme.onSurface),
      _BadgeTone.warning => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _BadgeTone.danger => (scheme.error, scheme.onError),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: tone == _BadgeTone.neutral
            ? Border.all(color: scheme.outlineVariant)
            : null,
      ),
      child: Text(
        count.toString(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}

enum _BadgeTone { neutral, warning, danger }

class _MenuSection {
  const _MenuSection({required this.title, required this.items});

  final String title;
  final List<_MenuItem> items;

  _MenuSection copyWith({String? title, List<_MenuItem>? items}) {
    return _MenuSection(title: title ?? this.title, items: items ?? this.items);
  }
}

class _MenuItem {
  const _MenuItem({
    required this.title,
    required this.icon,
    this.subtitle,
    this.route,
    this.enabled = true,
    this.badgeCount,
    this.badgeTone,
    this.children,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? route;
  final bool enabled;
  final int? badgeCount;
  final _BadgeTone? badgeTone;
  final List<_MenuItem>? children;

  _MenuItem copyWith({
    String? title,
    String? subtitle,
    IconData? icon,
    String? route,
    bool? enabled,
    int? badgeCount,
    _BadgeTone? badgeTone,
    List<_MenuItem>? children,
  }) {
    return _MenuItem(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon ?? this.icon,
      route: route ?? this.route,
      enabled: enabled ?? this.enabled,
      badgeCount: badgeCount ?? this.badgeCount,
      badgeTone: badgeTone ?? this.badgeTone,
      children: children ?? this.children,
    );
  }
}
