import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/auth_models.dart';
import '../features/auth/login_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/documents/document_upload_page.dart';
import '../features/crm/crm_firms_page.dart';
import '../features/crm/crm_income_centers_page.dart';
import '../features/crm/crm_expense_types_page.dart';
import '../features/crm/crm_payment_types_page.dart';
import '../features/crm/crm_branches_page.dart';
import '../features/crm/crm_unit_sets_page.dart';
import '../features/crm/crm_account_periods_page.dart';
import '../features/crm/crm_workstations_page.dart';
import '../features/crm/crm_cash_registers_page.dart';
import '../features/crm/crm_waste_warehouse_page.dart';
import '../features/crm/crm_min_max_page.dart';
import '../features/crm/crm_unproduced_products_page.dart';
import '../features/admin/admin_users_page.dart';
import '../features/admin/admin_user_menu_permissions_page.dart';
import '../features/account/account_password_page.dart';
import '../features/reports/ana_grup_satis_raporu_page.dart';
import '../features/inventory/inventory_counts_page.dart';
import '../features/inventory/inventory_invoices_page.dart';
import '../features/inventory/inventory_onhand_page.dart';
import '../features/inventory/inventory_products_page.dart';
import '../features/inventory/inventory_recipes_page.dart';
import '../features/inventory/inventory_transactions_page.dart';
import '../features/inventory/inventory_warehouses_page.dart';
import '../features/reconciliation/reconciliation_detail_page.dart';
import '../features/reconciliation/reconciliation_list_page.dart';
import '../features/settings/settings_page.dart';
import '../features/shell/app_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final isLoggingIn = state.matchedLocation == '/login';

      final session = auth.asData?.value;
      final isAuthed = session != null;

      if (!isAuthed) {
        return isLoggingIn ? null : '/login';
      }

      if (isLoggingIn) {
        return '/';
      }

      if (state.matchedLocation == '/settings' &&
          session.role != UserRole.manager) {
        return '/';
      }

      if (state.matchedLocation.startsWith('/admin') &&
          session.role != UserRole.manager) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/reconciliations',
            builder: (context, state) => const ReconciliationListPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => ReconciliationDetailPage(
                  reconciliationId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/documents',
            builder: (context, state) => const DocumentUploadPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/inv/products',
            builder: (context, state) => const InventoryProductsPage(),
          ),
          GoRoute(
            path: '/inv/invoices',
            builder: (context, state) => const InventoryInvoicesPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => InventoryInvoiceDetailPage(
                  invoiceId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/inv/warehouses',
            builder: (context, state) => const InventoryWarehousesPage(),
          ),
          GoRoute(
            path: '/inv/transactions',
            builder: (context, state) => const InventoryTransactionsPage(),
          ),
          GoRoute(
            path: '/inv/onhand',
            builder: (context, state) => const InventoryOnHandPage(),
          ),
          GoRoute(
            path: '/inv/counts',
            builder: (context, state) => const InventoryCountsPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => InventoryCountDetailPage(
                  countId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/inv/recipes',
            builder: (context, state) => const InventoryRecipesPage(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) => InventoryRecipeDetailPage(
                  recipeId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/crm/firms',
            builder: (context, state) => const CrmFirmsPage(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const CrmFirmDetailPage(firmId: 'new'),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => CrmFirmDetailPage(
                  firmId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/crm/income-centers',
            builder: (context, state) => const CrmIncomeCentersPage(),
          ),
          GoRoute(
            path: '/crm/expense-types',
            builder: (context, state) => const CrmExpenseTypesPage(),
          ),
          GoRoute(
            path: '/crm/payment-types',
            builder: (context, state) => const CrmPaymentTypesPage(),
          ),
          GoRoute(
            path: '/crm/branches',
            builder: (context, state) => const CrmBranchesPage(),
          ),
          GoRoute(
            path: '/crm/unit-sets',
            builder: (context, state) => const CrmUnitSetsPage(),
          ),
          GoRoute(
            path: '/crm/account-periods',
            builder: (context, state) => const CrmAccountPeriodsPage(),
          ),
          GoRoute(
            path: '/crm/workstations',
            builder: (context, state) => const CrmWorkstationsPage(),
          ),
          GoRoute(
            path: '/crm/cash-registers',
            builder: (context, state) => const CrmCashRegistersPage(),
          ),
          GoRoute(
            path: '/crm/waste-warehouse',
            builder: (context, state) => const CrmWasteWarehousePage(),
          ),
          GoRoute(
            path: '/crm/min-max',
            builder: (context, state) => const CrmMinMaxPage(),
          ),
          GoRoute(
            path: '/crm/unproduced-products',
            builder: (context, state) => const CrmUnproducedProductsPage(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (context, state) => const AdminUsersPage(),
          ),
          GoRoute(
            path: '/admin/user-menu-permissions',
            builder: (context, state) => const AdminUserMenuPermissionsPage(),
          ),
          GoRoute(
            path: '/account/password',
            builder: (context, state) => const AccountPasswordPage(),
          ),
          GoRoute(
            path: '/reports/ana-grup-satis',
            builder: (context, state) => const AnaGrupSatisRaporuPage(),
          ),
          GoRoute(
            path: '/legacy/:ref',
            builder: (context, state) => _LegacyPage(
              legacyRef: state.pathParameters['ref']!,
            ),
          ),
        ],
      ),
    ],
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(this._ref) {
    _sub = _ref.listen(authControllerProvider, (previous, next) {
      notifyListeners();
    });
  }

  final Ref _ref;
  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

class _LegacyPage extends StatelessWidget {
  const _LegacyPage({required this.legacyRef});

  final String legacyRef;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    legacyRef,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Bu ekran NBOS (ASPX) sistemindeki menüden geldi. Flutter tarafında birebirini bu ref üzerinden modül modül taşıyacağız.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
