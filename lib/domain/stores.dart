import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/api_client.dart';
import '../app/config.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/auth_models.dart';
import 'models.dart';

final branchesProvider =
    NotifierProvider<BranchesStore, List<Branch>>(BranchesStore.new);

final dbCheckProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  if (!AppConfig.hasApi) {
    return {
      'ok': true,
      'missingTables': const [],
      'missingColumns': const [],
      'serverTime': DateTime.now().toIso8601String(),
    };
  }
  final dio = ref.read(dioProvider);
  final res = await dio.get<Map<String, dynamic>>('/health/db-check');
  return res.data ?? const {};
});

final branchDataSourcesProvider =
    NotifierProvider<BranchDataSourcesStore, List<BranchDataSource>>(
  BranchDataSourcesStore.new,
);

Branch _branchFromJson(Map<String, dynamic> m) {
  final startHourRaw = m['businessDayStartHour'] ?? m['business_day_start_hour'] ?? 0;
  final startHour = (startHourRaw is num)
      ? startHourRaw.toInt()
      : int.tryParse(startHourRaw.toString()) ?? 0;
  return Branch(
    id: m['id'].toString(),
    code: m['code']?.toString(),
    name: (m['name'] ?? '').toString(),
    businessDayStartHour: startHour.clamp(0, 23),
    isActive: (m['isActive'] as bool?) ?? true,
  );
}

BranchDataSource _branchDataSourceFromJson(Map<String, dynamic> m) {
  final updatedAtRaw = m['updatedAt'];
  DateTime? updatedAt;
  if (updatedAtRaw is String) {
    updatedAt = DateTime.tryParse(updatedAtRaw);
  } else if (updatedAtRaw is DateTime) {
    updatedAt = updatedAtRaw;
  }
  return BranchDataSource(
    branchId: (m['branchId'] ?? '').toString(),
    host: (m['host'] ?? '').toString(),
    port: (m['port'] as num?)?.toInt() ?? 5432,
    database: (m['database'] ?? '').toString(),
    username: (m['username'] ?? '').toString(),
    ssl: (m['ssl'] as bool?) ?? false,
    isActive: (m['isActive'] as bool?) ?? true,
    updatedAt: updatedAt,
  );
}

CashRegister _cashRegisterFromJson(Map<String, dynamic> m) {
  return CashRegister(
    id: (m['id'] ?? '').toString(),
    code: (m['code'] ?? '').toString(),
    name: (m['name'] ?? '').toString(),
    isActive: (m['isActive'] as bool?) ?? true,
  );
}

final branchCashRegistersProvider =
    FutureProvider.family<List<CashRegister>, String>((ref, branchId) async {
  if (!AppConfig.hasApi) return const [];
  final dio = ref.read(dioProvider);
  final res = await dio.get<List<dynamic>>('/branches/$branchId/cash-registers');
  final data = res.data ?? const [];
  return [
    for (final raw in data)
      if (raw is Map<String, dynamic>) _cashRegisterFromJson(raw),
  ];
});

final branchCashRegistersActionsProvider =
    Provider<BranchCashRegistersActions>(BranchCashRegistersActions.new);

class BranchCashRegistersActions {
  BranchCashRegistersActions(this.ref);
  final Ref ref;

  Future<void> setForBranch({
    required String branchId,
    required List<String> cashRegisterIds,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.put<Map<String, dynamic>>(
      '/branches/$branchId/cash-registers',
      data: {'cashRegisterIds': cashRegisterIds},
    );
    ref.invalidate(branchCashRegistersProvider(branchId));
  }
}

class BranchDataSourcesStore extends Notifier<List<BranchDataSource>> {
  @override
  List<BranchDataSource> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      } else {
        state = const [];
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
    }
    return const [];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/branch-data-sources');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          if ((raw['host'] ?? '').toString().trim().isNotEmpty)
            _branchDataSourceFromJson(raw),
    ];
  }

  BranchDataSource? byBranchId(String branchId) {
    return state.where((e) => e.branchId == branchId).firstOrNull;
  }

  Future<void> upsert({
    required String branchId,
    required String host,
    required int port,
    required String database,
    required String username,
    String? password,
    required bool ssl,
    required bool isActive,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final data = <String, dynamic>{
      'host': host,
      'port': port,
      'database': database,
      'username': username,
      'ssl': ssl,
      'isActive': isActive,
      if (password != null) 'password': password,
    };
    await dio.put<Map<String, dynamic>>(
      '/branch-data-sources/$branchId',
      data: data,
    );
    await refresh();
  }

  Future<bool> test(String branchId) async {
    if (!AppConfig.hasApi) return false;
    final dio = ref.read(dioProvider);
    try {
      final res = await dio.post<Map<String, dynamic>>(
        '/branch-data-sources/$branchId/test',
      );
      final data = res.data ?? const {};
      final ok = (data['ok'] as bool?) ?? false;
      if (ok) return true;
      final message = (data['message'] ?? data['error'] ?? 'Bağlantı başarısız').toString();
      throw Exception(message);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        final message = (data['message'] ?? data['error'])?.toString();
        if (message != null && message.trim().isNotEmpty) {
          throw Exception(message);
        }
      }
      throw Exception('Bağlantı testi başarısız');
    }
  }
}

class BranchesStore extends Notifier<List<Branch>> {
  @override
  List<Branch> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [
      Branch(id: 'branch-1', name: 'Şube 1'),
      Branch(id: 'branch-2', name: 'Şube 2'),
    ];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/branches');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>) _branchFromJson(raw),
    ];
  }

  Future<void> addBranch({
    required String name,
    String? code,
    int businessDayStartHour = 0,
  }) async {
    if (!AppConfig.hasApi) {
      final id = 'branch-${DateTime.now().millisecondsSinceEpoch}';
      state = [
        ...state,
        Branch(
          id: id,
          name: name,
          code: code?.trim().isEmpty ?? true ? null : code!.trim(),
          businessDayStartHour: businessDayStartHour.clamp(0, 23),
        ),
      ];
      return;
    }

    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/branches',
      data: {
        'name': name,
        if (code?.trim().isNotEmpty ?? false) 'code': code!.trim(),
        'businessDayStartHour': businessDayStartHour.clamp(0, 23),
      },
    );
    await refresh();
  }

  Future<void> update({
    required String id,
    String? name,
    String? code,
    bool? isActive,
    int? businessDayStartHour,
  }) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final b in state)
          if (b.id == id)
            b.copyWith(
              name: name ?? b.name,
              code: code ?? b.code,
              businessDayStartHour: businessDayStartHour ?? b.businessDayStartHour,
              isActive: isActive ?? b.isActive,
            )
          else
            b,
      ];
      return;
    }
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/branches/$id',
      data: {
        if (name?.trim().isNotEmpty ?? false) 'name': name!.trim(),
        if (code != null) 'code': code.trim(),
        'isActive': ?isActive,
        'businessDayStartHour': ?businessDayStartHour,
      },
    );
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final b in state)
          if (b.id == id) b.copyWith(isActive: !b.isActive) else b,
      ];
      return;
    }

    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    await update(id: id, isActive: !item.isActive);
  }
}

final paymentTypesProvider =
    NotifierProvider<PaymentTypesStore, List<PaymentType>>(PaymentTypesStore.new);

PaymentType _paymentTypeFromJson(Map<String, dynamic> m) {
  return PaymentType(
    id: m['id'].toString(),
    code: m['code']?.toString(),
    name: (m['name'] ?? '').toString(),
    isActive: (m['isActive'] as bool?) ?? true,
  );
}

class PaymentTypesStore extends Notifier<List<PaymentType>> {
  @override
  List<PaymentType> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [
      PaymentType(id: 'cash', code: 'CASH', name: 'Nakit'),
      PaymentType(id: 'card', code: 'CARD', name: 'Kredi Kartı'),
      PaymentType(id: 'transfer', code: 'TRANSFER', name: 'Havale/EFT'),
    ];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/payment-types');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>) _paymentTypeFromJson(raw),
    ];
  }

  Future<void> addPaymentType({
    required String name,
    String? code,
  }) async {
    if (!AppConfig.hasApi) {
      final id = 'pay-${DateTime.now().millisecondsSinceEpoch}';
      state = [...state, PaymentType(id: id, code: code, name: name)];
      return;
    }

    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/payment-types',
      data: {
        'name': name,
        if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
      },
    );
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final p in state)
          if (p.id == id) p.copyWith(isActive: !p.isActive) else p,
      ];
      return;
    }

    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/payment-types/$id',
      data: {'isActive': !item.isActive},
    );
    await refresh();
  }

  Future<void> update({
    required String id,
    String? name,
    String? code,
    bool? isActive,
  }) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final p in state)
          if (p.id == id)
            p.copyWith(
              name: name ?? p.name,
              code: code ?? p.code,
              isActive: isActive ?? p.isActive,
            )
          else
            p,
      ];
      return;
    }

    await ref.read(dioProvider).patch<Map<String, dynamic>>(
          '/payment-types/$id',
          data: {
            if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
            if (code != null) 'code': code.trim(),
            'isActive': ?isActive,
          },
        );
    await refresh();
  }
}

final expenseTypesProvider =
    NotifierProvider<ExpenseTypesStore, List<ExpenseType>>(ExpenseTypesStore.new);

ExpenseType _expenseTypeFromJson(Map<String, dynamic> m) {
  return ExpenseType(
    id: m['id'].toString(),
    name: (m['name'] ?? '').toString(),
    isActive: (m['isActive'] as bool?) ?? true,
  );
}

class ExpenseTypesStore extends Notifier<List<ExpenseType>> {
  @override
  List<ExpenseType> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [
      ExpenseType(id: 'expense-other', name: 'Diğer'),
      ExpenseType(id: 'expense-cargo', name: 'Kargo'),
      ExpenseType(id: 'expense-food', name: 'Yemek'),
    ];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/expense-types');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>) _expenseTypeFromJson(raw),
    ];
  }

  Future<void> addExpenseType(String name) async {
    if (!AppConfig.hasApi) {
      final id = 'exp-${DateTime.now().millisecondsSinceEpoch}';
      state = [...state, ExpenseType(id: id, name: name)];
      return;
    }

    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>('/expense-types', data: {'name': name});
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final e in state)
          if (e.id == id) e.copyWith(isActive: !e.isActive) else e,
      ];
      return;
    }

    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/expense-types/$id',
      data: {'isActive': !item.isActive},
    );
    await refresh();
  }
}

final incomeCentersProvider =
    NotifierProvider<IncomeCentersStore, List<IncomeCenter>>(IncomeCentersStore.new);

class IncomeCentersStore extends Notifier<List<IncomeCenter>> {
  @override
  List<IncomeCenter> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [
      IncomeCenter(id: 'inc-1', code: 'GM-01', name: 'Gelir Merkezi 1'),
      IncomeCenter(id: 'inc-2', code: 'GM-02', name: 'Gelir Merkezi 2', isActive: false),
    ];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/income-centers');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          IncomeCenter(
            id: raw['id'].toString(),
            code: raw['code']?.toString(),
            name: (raw['name'] ?? '').toString(),
            isActive: (raw['isActive'] as bool?) ?? true,
          ),
    ];
  }

  Future<void> addIncomeCenter({
    required String name,
    String? code,
  }) async {
    if (!AppConfig.hasApi) {
      final id = 'inc-${DateTime.now().millisecondsSinceEpoch}';
      state = [
        ...state,
        IncomeCenter(id: id, code: code?.trim().isEmpty ?? true ? null : code!.trim(), name: name),
      ];
      return;
    }
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/income-centers',
      data: {
        'name': name,
        if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
      },
    );
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final e in state)
          if (e.id == id) e.copyWith(isActive: !e.isActive) else e,
      ];
      return;
    }
    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/income-centers/$id',
      data: {'isActive': !item.isActive},
    );
    await refresh();
  }
}

final cashRegistersProvider =
    NotifierProvider<CashRegistersStore, List<CashRegister>>(CashRegistersStore.new);

class CashRegistersStore extends Notifier<List<CashRegister>> {
  @override
  List<CashRegister> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [
      CashRegister(id: 'cash-1', code: 'KASA-01', name: 'Kasa 1', isActive: true),
      CashRegister(id: 'cash-2', code: 'KASA-02', name: 'Kasa 2', isActive: true),
    ];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/cash-registers');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          CashRegister(
            id: raw['id'].toString(),
            code: (raw['code'] ?? '').toString(),
            name: (raw['name'] ?? '').toString(),
            isActive: (raw['isActive'] as bool?) ?? true,
          ),
    ];
  }

  Future<void> addCashRegister({
    required String name,
    String? code,
  }) async {
    if (!AppConfig.hasApi) {
      final id = 'cash-${DateTime.now().millisecondsSinceEpoch}';
      state = [
        CashRegister(id: id, code: code ?? 'KASA', name: name, isActive: true),
        ...state,
      ];
      return;
    }
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/cash-registers',
      data: {
        'name': name,
        if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
      },
    );
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final e in state)
          if (e.id == id) e.copyWith(isActive: !e.isActive) else e,
      ];
      return;
    }
    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/cash-registers/$id',
      data: {'isActive': !item.isActive},
    );
    await refresh();
  }
}

final wasteWarehouseSelectionProvider =
    NotifierProvider<WasteWarehouseSelectionStore, String?>(
  WasteWarehouseSelectionStore.new,
);

class WasteWarehouseSelectionStore extends Notifier<String?> {
  String? _branchId;

  @override
  String? build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        _branchId ??= session.branchId;
        refresh();
      } else {
        state = null;
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      _branchId ??= session.branchId;
      Future.microtask(refresh);
    }

    if (!AppConfig.hasApi) {
      _branchId ??= 'branch-1';
      return '${_branchId!}-wh-2';
    }

    return null;
  }

  void setBranch(String? branchId) {
    _branchId = branchId;
    if (AppConfig.hasApi) {
      refresh();
      return;
    }
    if (_branchId != null && _branchId!.isNotEmpty) {
      state = '${_branchId!}-wh-2';
    } else {
      state = null;
    }
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final branchId = _branchId;
    if (branchId == null || branchId.isEmpty) {
      state = null;
      return;
    }
    final dio = ref.read(dioProvider);
    final res = await dio.get<Map<String, dynamic>>(
      '/crm/waste-warehouse',
      queryParameters: {'branchId': branchId},
    );
    final data = res.data ?? const {};
    final raw = data['warehouseId'];
    state = raw?.toString();
  }

  Future<void> setSelected({
    required String branchId,
    required String warehouseId,
  }) async {
    if (!AppConfig.hasApi) {
      state = warehouseId;
      return;
    }
    final dio = ref.read(dioProvider);
    await dio.put<Map<String, dynamic>>(
      '/crm/waste-warehouse',
      data: {'branchId': branchId, 'warehouseId': warehouseId},
    );
    state = warehouseId;
  }
}

final minMaxDefinitionsProvider =
    NotifierProvider<MinMaxDefinitionsStore, List<MinMaxDefinition>>(
  MinMaxDefinitionsStore.new,
);

class MinMaxDefinitionsStore extends Notifier<List<MinMaxDefinition>> {
  String? _branchId;

  @override
  List<MinMaxDefinition> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        _branchId ??= session.branchId;
        refresh();
      } else {
        state = const [];
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      _branchId ??= session.branchId;
      Future.microtask(refresh);
      return const [];
    }

    _branchId ??= 'branch-1';
    return _demoForBranch(_branchId);
  }

  void setBranch(String? branchId) {
    _branchId = branchId;
    if (AppConfig.hasApi) {
      refresh();
      return;
    }
    state = _demoForBranch(_branchId);
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final branchId = _branchId;
    if (branchId == null || branchId.isEmpty) {
      state = const [];
      return;
    }
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>(
      '/min-max',
      queryParameters: {'branchId': branchId},
    );
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          MinMaxDefinition(
            id: raw['id'].toString(),
            branchId: raw['branchId'].toString(),
            productName: (raw['productName'] ?? '').toString(),
            minQty: _numToDouble(raw['minQty']),
            maxQty: _numToDouble(raw['maxQty']),
          ),
    ];
  }

  Future<void> add({
    required String branchId,
    required String productName,
    required double minQty,
    required double maxQty,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/min-max',
      data: {
        'branchId': branchId,
        'productName': productName,
        'minQty': minQty,
        'maxQty': maxQty,
      },
    );
    await refresh();
  }

  Future<void> delete(String id) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.delete<Map<String, dynamic>>('/min-max/$id');
    await refresh();
  }

  List<MinMaxDefinition> _demoForBranch(String? branchId) {
    final b = (branchId == null || branchId.isEmpty) ? 'branch-1' : branchId;
    if (b != 'branch-1') return const [];
    return const [
      MinMaxDefinition(
        id: 'mm-1',
        branchId: 'branch-1',
        productName: 'Domates',
        minQty: 10,
        maxQty: 40,
      ),
      MinMaxDefinition(
        id: 'mm-2',
        branchId: 'branch-1',
        productName: 'Kaşar',
        minQty: 5,
        maxQty: 20,
      ),
    ];
  }
}

final unproducedProductsProvider =
    NotifierProvider<UnproducedProductsStore, List<UnproducedProduct>>(
  UnproducedProductsStore.new,
);

class UnproducedProductsStore extends Notifier<List<UnproducedProduct>> {
  @override
  List<UnproducedProduct> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [
      UnproducedProduct(id: 'up-1', productName: 'Sos', isBlocked: true),
      UnproducedProduct(id: 'up-2', productName: 'Pizza', isBlocked: false),
      UnproducedProduct(id: 'up-3', productName: 'Hamburger', isBlocked: false),
    ];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/unproduced-products');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          UnproducedProduct(
            id: raw['id'].toString(),
            productName: (raw['productName'] ?? '').toString(),
            isBlocked: (raw['isBlocked'] as bool?) ?? true,
          ),
    ];
  }

  Future<void> add({
    required String productName,
    bool? isBlocked,
  }) async {
    if (!AppConfig.hasApi) {
      final id = 'up-${DateTime.now().millisecondsSinceEpoch}';
      state = [
        UnproducedProduct(id: id, productName: productName, isBlocked: isBlocked ?? true),
        ...state,
      ];
      return;
    }
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/unproduced-products',
      data: {
        'productName': productName,
        'isBlocked': ?isBlocked,
      },
    );
    await refresh();
  }

  Future<void> setBlocked(String id, bool isBlocked) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final e in state)
          if (e.id == id) e.copyWith(isBlocked: isBlocked) else e,
      ];
      return;
    }
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/unproduced-products/$id',
      data: {'isBlocked': isBlocked},
    );
    await refresh();
  }
}

final unitSetsProvider =
    NotifierProvider<UnitSetsStore, List<UnitSet>>(UnitSetsStore.new);

class UnitSetsStore extends Notifier<List<UnitSet>> {
  @override
  List<UnitSet> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [
      UnitSet(id: 'us-1', code: 'ADET', name: 'Adet', isActive: true),
      UnitSet(id: 'us-2', code: 'KG', name: 'Kilogram', isActive: true),
      UnitSet(id: 'us-3', code: 'LT', name: 'Litre', isActive: true),
    ];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/unit-sets');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          UnitSet(
            id: raw['id'].toString(),
            code: (raw['code'] ?? '').toString(),
            name: (raw['name'] ?? '').toString(),
            isActive: (raw['isActive'] as bool?) ?? true,
          ),
    ];
  }

  Future<void> add({
    required String code,
    required String name,
  }) async {
    if (!AppConfig.hasApi) {
      final id = 'us-${DateTime.now().millisecondsSinceEpoch}';
      state = [UnitSet(id: id, code: code, name: name, isActive: true), ...state];
      return;
    }
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/unit-sets',
      data: {'code': code, 'name': name},
    );
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final e in state)
          if (e.id == id) e.copyWith(isActive: !e.isActive) else e,
      ];
      return;
    }
    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/unit-sets/$id',
      data: {'isActive': !item.isActive},
    );
    await refresh();
  }
}

final accountPeriodsProvider =
    NotifierProvider<AccountPeriodsStore, List<AccountPeriod>>(AccountPeriodsStore.new);

class AccountPeriodsStore extends Notifier<List<AccountPeriod>> {
  @override
  List<AccountPeriod> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return [
      AccountPeriod(
        id: 'ap-2026',
        name: '2026',
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        isActive: true,
      ),
      AccountPeriod(
        id: 'ap-2025',
        name: '2025',
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 12, 31),
        isActive: false,
      ),
    ];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/account-periods');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          AccountPeriod(
            id: raw['id'].toString(),
            name: (raw['name'] ?? '').toString(),
            startDate: _parseDate(raw['startDate']),
            endDate: _parseDate(raw['endDate']),
            isActive: (raw['isActive'] as bool?) ?? true,
          ),
    ];
  }

  Future<void> add({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    if (!AppConfig.hasApi) {
      final id = 'ap-${DateTime.now().millisecondsSinceEpoch}';
      state = [
        AccountPeriod(id: id, name: name, startDate: startDate, endDate: endDate, isActive: true),
        ...state.map((e) => e.copyWith(isActive: false)),
      ];
      return;
    }
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/account-periods',
      data: {
        'name': name,
        'startDate': startDate.toIso8601String().substring(0, 10),
        'endDate': endDate.toIso8601String().substring(0, 10),
      },
    );
    await refresh();
  }

  Future<void> setActive(String id, bool isActive) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final e in state)
          if (e.id == id) e.copyWith(isActive: isActive) else e.copyWith(isActive: isActive ? false : e.isActive),
      ];
      return;
    }
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/account-periods/$id',
      data: {'isActive': isActive},
    );
    await refresh();
  }
}

final workstationsProvider =
    NotifierProvider<WorkstationsStore, List<Workstation>>(WorkstationsStore.new);

class WorkstationsStore extends Notifier<List<Workstation>> {
  @override
  List<Workstation> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [
      Workstation(id: 'ws-1', code: 'POS-01', name: 'Kasa 1', isActive: true),
      Workstation(id: 'ws-2', code: 'POS-02', name: 'Kasa 2', isActive: true),
    ];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/workstations');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          Workstation(
            id: raw['id'].toString(),
            code: (raw['code'] ?? '').toString(),
            name: (raw['name'] ?? '').toString(),
            isActive: (raw['isActive'] as bool?) ?? true,
          ),
    ];
  }

  Future<void> add({
    required String code,
    required String name,
  }) async {
    if (!AppConfig.hasApi) {
      final id = 'ws-${DateTime.now().millisecondsSinceEpoch}';
      state = [Workstation(id: id, code: code, name: name, isActive: true), ...state];
      return;
    }
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/workstations',
      data: {'code': code, 'name': name},
    );
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final e in state)
          if (e.id == id) e.copyWith(isActive: !e.isActive) else e,
      ];
      return;
    }
    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/workstations/$id',
      data: {'isActive': !item.isActive},
    );
    await refresh();
  }
}

final inventoryInvoicesProvider =
    NotifierProvider<InventoryInvoicesStore, List<InventoryInvoice>>(
  InventoryInvoicesStore.new,
);

class InventoryInvoicesStore extends Notifier<List<InventoryInvoice>> {
  String? _branchId;
  DateTime? _from;
  DateTime? _to;

  @override
  List<InventoryInvoice> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        _branchId ??= session.branchId;
        refresh();
      } else {
        state = const [];
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      _branchId ??= session.branchId;
      Future.microtask(refresh);
      return const [];
    }

    return const [];
  }

  void setFilters({
    required String? branchId,
    DateTime? from,
    DateTime? to,
  }) {
    _branchId = branchId;
    _from = from;
    _to = to;
    if (AppConfig.hasApi) {
      refresh();
    }
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final branchId = _branchId;
    if (branchId == null || branchId.isEmpty) {
      state = const [];
      return;
    }

    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>(
      '/inv/invoices',
      queryParameters: {
        'branchId': branchId,
        if (_from != null) 'from': _from!.toIso8601String().substring(0, 10),
        if (_to != null) 'to': _to!.toIso8601String().substring(0, 10),
      },
    );
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          InventoryInvoice(
            id: raw['id'].toString(),
            branchId: raw['branchId'].toString(),
            invoiceNo: (raw['invoiceNo'] ?? '').toString(),
            invoiceDate: _parseDate(raw['invoiceDate']),
            vendorName: raw['vendorName']?.toString(),
            notes: raw['notes']?.toString(),
            total: _numToDouble(raw['total']),
            paymentTypeId: raw['paymentTypeId']?.toString(),
            incomeCenterId: raw['incomeCenterId']?.toString(),
            discountRate: raw['discountRate'] == null ? null : _numToDouble(raw['discountRate']),
            discountAmount: raw['discountAmount'] == null ? null : _numToDouble(raw['discountAmount']),
            mealVoucherDiscount: raw['mealVoucherDiscount'] == null ? null : _numToDouble(raw['mealVoucherDiscount']),
            paymentDate: raw['paymentDate'] == null ? null : _parseDate(raw['paymentDate']),
          ),
    ];
  }

  Future<String?> create({
    required String branchId,
    required String invoiceNo,
    required DateTime invoiceDate,
    String? vendorName,
    String? notes,
  }) async {
    if (!AppConfig.hasApi) return null;
    final dio = ref.read(dioProvider);
    final res = await dio.post<Map<String, dynamic>>(
      '/inv/invoices',
      data: {
        'branchId': branchId,
        'invoiceNo': invoiceNo,
        'invoiceDate': invoiceDate.toIso8601String().substring(0, 10),
        if (vendorName?.trim().isNotEmpty ?? false) 'vendorName': vendorName!.trim(),
        if (notes?.trim().isNotEmpty ?? false) 'notes': notes!.trim(),
      },
    );
    await refresh();
    return res.data?['id']?.toString();
  }
}

final inventoryInvoiceDetailProvider =
    FutureProvider.family<({InventoryInvoice header, List<InventoryInvoiceLine> lines}), String>(
  (ref, id) async {
    if (!AppConfig.hasApi) throw StateError('API modu gerekli');
    final dio = ref.read(dioProvider);
    final res = await dio.get<Map<String, dynamic>>('/inv/invoices/$id');
    final data = res.data ?? const {};
    final headerRaw = data['header'];
    final linesRaw = data['lines'];
    if (headerRaw is! Map<String, dynamic>) throw StateError('Boş yanıt');

    final header = InventoryInvoice(
      id: headerRaw['id'].toString(),
      branchId: headerRaw['branchId'].toString(),
      invoiceNo: (headerRaw['invoiceNo'] ?? '').toString(),
      invoiceDate: _parseDate(headerRaw['invoiceDate']),
      vendorName: headerRaw['vendorName']?.toString(),
      notes: headerRaw['notes']?.toString(),
      total: null,
      paymentTypeId: headerRaw['paymentTypeId']?.toString(),
      incomeCenterId: headerRaw['incomeCenterId']?.toString(),
      discountRate: headerRaw['discountRate'] == null ? null : _numToDouble(headerRaw['discountRate']),
      discountAmount: headerRaw['discountAmount'] == null ? null : _numToDouble(headerRaw['discountAmount']),
      mealVoucherDiscount: headerRaw['mealVoucherDiscount'] == null ? null : _numToDouble(headerRaw['mealVoucherDiscount']),
      paymentDate: headerRaw['paymentDate'] == null ? null : _parseDate(headerRaw['paymentDate']),
    );

    final lines = <InventoryInvoiceLine>[
      if (linesRaw is List)
        for (final raw in linesRaw)
          if (raw is Map<String, dynamic>)
            InventoryInvoiceLine(
              id: raw['id'].toString(),
              invoiceId: raw['invoiceId'].toString(),
              productId: raw['productId']?.toString(),
              productCode: raw['productCode']?.toString(),
              productName: raw['productName']?.toString(),
              description: (raw['description'] ?? '').toString(),
              unit: raw['unit']?.toString(),
              quantity: _numToDouble(raw['quantity']),
              unitPrice: _numToDouble(raw['unitPrice']),
              lineTotal: _numToDouble(raw['lineTotal']),
            ),
    ];

    return (header: header, lines: lines);
  },
);

final inventoryInvoiceActionsProvider = Provider<InventoryInvoiceActions>((ref) {
  return InventoryInvoiceActions(ref);
});

final inventoryOpenDeliveryNotesProvider =
    FutureProvider.family<List<InventoryOpenDocument>, String>((ref, branchId) async {
  if (!AppConfig.hasApi) return const [];
  final dio = ref.read(dioProvider);
  final res = await dio.get<List<dynamic>>(
    '/inv/open-delivery-notes',
    queryParameters: {'branchId': branchId},
  );
  final data = res.data ?? const [];
  return [
    for (final raw in data)
      if (raw is Map<String, dynamic>)
        InventoryOpenDocument(
          id: raw['id'].toString(),
          branchId: raw['branchId'].toString(),
          docNo: (raw['docNo'] ?? '').toString(),
          docDate: _parseDate(raw['docDate']),
          vendorName: raw['vendorName']?.toString(),
          total: _numToDouble(raw['total']),
          linesCount: (raw['linesCount'] as num?)?.toInt() ??
              int.tryParse(raw['linesCount']?.toString() ?? ''),
          kind: raw['kind']?.toString(),
        ),
  ];
});

final inventoryOpenPurchaseOrdersProvider =
    FutureProvider.family<List<InventoryOpenDocument>, String>((ref, branchId) async {
  if (!AppConfig.hasApi) return const [];
  final dio = ref.read(dioProvider);
  final res = await dio.get<List<dynamic>>(
    '/inv/open-purchase-orders',
    queryParameters: {'branchId': branchId},
  );
  final data = res.data ?? const [];
  return [
    for (final raw in data)
      if (raw is Map<String, dynamic>)
        InventoryOpenDocument(
          id: raw['id'].toString(),
          branchId: raw['branchId'].toString(),
          docNo: (raw['docNo'] ?? '').toString(),
          docDate: _parseDate(raw['docDate']),
          vendorName: raw['vendorName']?.toString(),
          total: _numToDouble(raw['total']),
          linesCount: (raw['linesCount'] as num?)?.toInt() ??
              int.tryParse(raw['linesCount']?.toString() ?? ''),
          kind: raw['kind']?.toString(),
        ),
  ];
});

class InventoryInvoiceActions {
  InventoryInvoiceActions(this._ref);

  final Ref _ref;

  Future<void> addLine({
    required String invoiceId,
    required String description,
    required double quantity,
    required double unitPrice,
    String? productId,
    String? unit,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = _ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/inv/invoices/$invoiceId/lines',
      data: {
        'description': description,
        'productId': ?productId,
        'unit': ?unit,
        'quantity': quantity,
        'unitPrice': unitPrice,
      },
    );
    _ref.invalidate(inventoryInvoiceDetailProvider(invoiceId));
    _ref.invalidate(inventoryInvoicesProvider);
  }

  Future<void> updateHeader(
    String invoiceId, {
    String? invoiceNo,
    DateTime? invoiceDate,
    String? vendorName,
    String? notes,
    String? paymentTypeId,
    String? incomeCenterId,
    double? discountRate,
    double? discountAmount,
    double? mealVoucherDiscount,
    DateTime? paymentDate,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = _ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/inv/invoices/$invoiceId',
      data: {
        'invoiceNo': ?invoiceNo,
        if (invoiceDate != null) 'invoiceDate': invoiceDate.toIso8601String().substring(0, 10),
        'vendorName': ?vendorName,
        'notes': ?notes,
        'paymentTypeId': ?paymentTypeId,
        'incomeCenterId': ?incomeCenterId,
        'discountRate': ?discountRate,
        'discountAmount': ?discountAmount,
        'mealVoucherDiscount': ?mealVoucherDiscount,
        if (paymentDate != null) 'paymentDate': paymentDate.toIso8601String().substring(0, 10),
      },
    );
    _ref.invalidate(inventoryInvoiceDetailProvider(invoiceId));
    _ref.invalidate(inventoryInvoicesProvider);
  }

  Future<void> deleteLine({
    required String invoiceId,
    required String lineId,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = _ref.read(dioProvider);
    await dio.delete<Map<String, dynamic>>('/inv/invoice-lines/$lineId');
    _ref.invalidate(inventoryInvoiceDetailProvider(invoiceId));
    _ref.invalidate(inventoryInvoicesProvider);
  }
}

final usersProvider = NotifierProvider<UsersStore, List<AppUser>>(UsersStore.new);

class UsersStore extends Notifier<List<AppUser>> {
  @override
  List<AppUser> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [
      AppUser(
        id: 'user-1',
        username: 'admin',
        displayName: 'Yönetici',
        role: 'manager',
        isActive: true,
      ),
      AppUser(
        id: 'user-2',
        username: 'muhasebe',
        displayName: 'Muhasebe',
        role: 'accounting',
        isActive: true,
      ),
      AppUser(
        id: 'user-3',
        username: 'sube',
        displayName: 'Şube Kullanıcısı',
        role: 'branchUser',
        isActive: false,
      ),
    ];
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/users');
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          AppUser(
            id: raw['id'].toString(),
            username: (raw['username'] ?? '').toString(),
            displayName: (raw['displayName'] ?? '').toString(),
            role: (raw['role'] ?? '').toString(),
            isActive: (raw['isActive'] as bool?) ?? true,
          ),
    ];
  }

  Future<void> addUser({
    required String username,
    required String displayName,
    required String role,
    String? password,
  }) async {
    if (!AppConfig.hasApi) {
      final id = 'user-${DateTime.now().millisecondsSinceEpoch}';
      state = [
        AppUser(
          id: id,
          username: username,
          displayName: displayName,
          role: role,
          isActive: true,
        ),
        ...state,
      ];
      return;
    }

    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/users',
      data: {
        'username': username,
        'displayName': displayName,
        'role': role,
        'password': ?password,
      },
    );
    await refresh();
  }

  Future<void> updateUser(
    String id, {
    String? displayName,
    String? role,
    bool? isActive,
    String? password,
  }) async {
    if (!AppConfig.hasApi) {
      state = [
        for (final u in state)
          if (u.id == id)
            u.copyWith(
              displayName: displayName ?? u.displayName,
              role: role ?? u.role,
              isActive: isActive ?? u.isActive,
            )
          else
            u,
      ];
      return;
    }

    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/users/$id',
      data: {
        'displayName': ?displayName,
        'role': ?role,
        'isActive': ?isActive,
        'password': ?password,
      },
    );
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    final u = state.where((e) => e.id == id).firstOrNull;
    if (u == null) return;
    await updateUser(id, isActive: !u.isActive);
  }
}

final reconciliationsProvider = NotifierProvider<ReconciliationStore,
    List<CashReconciliation>>(ReconciliationStore.new);

ReconciliationStatus _statusFromString(String? raw) {
  final v = raw?.trim().toLowerCase();
  return switch (v) {
    'draft' => ReconciliationStatus.draft,
    'submitted' => ReconciliationStatus.submitted,
    'approved' => ReconciliationStatus.approved,
    'rejected' => ReconciliationStatus.rejected,
    _ => ReconciliationStatus.draft,
  };
}

AttachmentKind _attachmentKindFromString(String? raw) {
  final v = raw?.trim().toLowerCase();
  return switch (v) {
    'countslip' => AttachmentKind.countSlip,
    'signedstatement' => AttachmentKind.signedStatement,
    _ => AttachmentKind.other,
  };
}

double _numToDouble(dynamic raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? 0;
  return 0;
}

DateTime _parseDate(dynamic raw) {
  if (raw is String) {
    final s = raw.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (m != null) {
      final y = int.tryParse(m.group(1)!) ?? 0;
      final mo = int.tryParse(m.group(2)!) ?? 0;
      final d = int.tryParse(m.group(3)!) ?? 0;
      if (y > 0 && mo >= 1 && mo <= 12 && d >= 1 && d <= 31) {
        if (s.length == 10) {
          return DateTime(y, mo, d);
        }
      }
    }

    final dt = DateTime.tryParse(s);
    if (dt != null) {
      final tr = dt.toUtc().add(const Duration(hours: 3));
      return DateTime(tr.year, tr.month, tr.day);
    }
  }
  if (raw is DateTime) {
    final tr = raw.toUtc().add(const Duration(hours: 3));
    return DateTime(tr.year, tr.month, tr.day);
  }
  return DateTime.now();
}

class ReconciliationStore extends Notifier<List<CashReconciliation>> {
  @override
  List<CashReconciliation> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      } else {
        state = const [];
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
    }
    return const [];
  }

  List<CashReconciliation> _sorted(List<CashReconciliation> items) {
    final next = [...items];
    next.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      final byBranch = a.branchId.compareTo(b.branchId);
      if (byBranch != 0) return byBranch;
      return a.id.compareTo(b.id);
    });
    return next;
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>('/cash-reconciliations');
    final data = res.data ?? const [];
    state = _sorted([
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          _fromListJson(raw),
    ]);
  }

  CashReconciliation _fromListJson(Map<String, dynamic> m) {
    final hasCountSlip = (m['hasCountSlip'] as bool?) ?? false;
    final hasSignedStatement = (m['hasSignedStatement'] as bool?) ?? false;
    final attachments = <Attachment>[
      if (hasCountSlip)
        const Attachment(
          id: 'cached-countSlip',
          kind: AttachmentKind.countSlip,
          fileName: '',
          mimeType: 'application/octet-stream',
          sizeBytes: 0,
        ),
      if (hasSignedStatement)
        const Attachment(
          id: 'cached-signedStatement',
          kind: AttachmentKind.signedStatement,
          fileName: '',
          mimeType: 'application/octet-stream',
          sizeBytes: 0,
        ),
    ];

    return CashReconciliation(
      id: m['id'].toString(),
      branchId: m['branchId'].toString(),
      date: _parseDate(m['businessDate']),
      expectedSalesTotal: _numToDouble(m['expectedSalesTotal']),
      paymentLines: const [],
      expenseLines: const [],
      attachments: attachments,
      status: _statusFromString(m['status']?.toString()),
      createdByUserId: m['createdByUserId'].toString(),
      approvedByUserId: m['approvedByUserId']?.toString(),
      rejectionReason: m['rejectionReason']?.toString(),
      paymentTotalCached: _numToDouble(m['paymentTotal']),
      attachmentsCountCached: (m['attachmentsCount'] as num?)?.toInt(),
      ocrCardTotalCached: _numToDouble(m['ocrCardTotal']),
      ocrFastTotalCached: _numToDouble(m['ocrFastTotal']),
      hasEndOfDayReportCached: (m['hasEndOfDayReport'] as bool?) ?? false,
      manualCardTotalCached: _numToDouble(m['manualCardTotal']),
    );
  }

  CashReconciliation _fromDetailJson(Map<String, dynamic> m) {
    final paymentsRaw = (m['paymentLines'] as List<dynamic>?) ?? const [];
    final expensesRaw = (m['expenseLines'] as List<dynamic>?) ?? const [];
    final attachmentsRaw = (m['attachments'] as List<dynamic>?) ?? const [];

    final payments = <MoneyLine>[
      for (final raw in paymentsRaw)
        if (raw is Map<String, dynamic>)
          MoneyLine(
            typeId: raw['typeId'].toString(),
            amount: _numToDouble(raw['amount']),
          ),
    ];

    final expenses = <MoneyLine>[
      for (final raw in expensesRaw)
        if (raw is Map<String, dynamic>)
          MoneyLine(
            typeId: raw['typeId'].toString(),
            amount: _numToDouble(raw['amount']),
          ),
    ];

    final attachments = <Attachment>[
      for (final raw in attachmentsRaw)
        if (raw is Map<String, dynamic>)
          Attachment(
            id: raw['id'].toString(),
            kind: _attachmentKindFromString(raw['kind']?.toString()),
            fileName: (raw['fileName'] ?? '').toString(),
            mimeType: (raw['mimeType'] ?? 'application/octet-stream').toString(),
            sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
          ),
    ];

    return CashReconciliation(
      id: m['id'].toString(),
      branchId: m['branchId'].toString(),
      date: _parseDate(m['businessDate']),
      expectedSalesTotal: _numToDouble(m['expectedSalesTotal']),
      paymentLines: payments,
      expenseLines: expenses,
      attachments: attachments,
      status: _statusFromString(m['status']?.toString()),
      createdByUserId: m['createdByUserId'].toString(),
      approvedByUserId: m['approvedByUserId']?.toString(),
      rejectionReason: m['rejectionReason']?.toString(),
      paymentTotalCached: null,
      attachmentsCountCached: attachments.length,
    );
  }

  Future<CashReconciliation> createDraft({
    required String branchId,
    required DateTime date,
    required String userId,
  }) async {
    if (!AppConfig.hasApi) {
      final id = 'rec-${DateTime.now().millisecondsSinceEpoch}';
      final draft = CashReconciliation(
        id: id,
        branchId: branchId,
        date: DateTime(date.year, date.month, date.day),
        expectedSalesTotal: 0,
        paymentLines: const [],
        expenseLines: const [],
        attachments: const [],
        status: ReconciliationStatus.draft,
        createdByUserId: userId,
      );
      state = [draft, ...state];
      return draft;
    }

    final dio = ref.read(dioProvider);
    final day = DateTime(date.year, date.month, date.day);
    final created = await dio.post<Map<String, dynamic>>(
      '/cash-reconciliations',
      data: {'branchId': branchId, 'businessDate': day.toIso8601String().substring(0, 10)},
    );
    final id = created.data?['id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Kayıt oluşturulamadı');
    }
    try {
      final item = await fetchById(id);
      upsertLocal(item);
      return item;
    } catch (_) {
      await refresh();
      final existing = state.where((e) => e.branchId == branchId && _sameDay(e.date, day)).firstOrNull;
      if (existing != null) return existing;
      rethrow;
    }
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void upsertLocal(CashReconciliation value) {
    var replaced = false;
    final next = <CashReconciliation>[];
    for (final r in state) {
      if (r.id == value.id) {
        next.add(value);
        replaced = true;
      } else {
        next.add(r);
      }
    }
    if (!replaced) {
      state = _sorted([value, ...next]);
    } else {
      state = _sorted(next);
    }
  }

  Future<CashReconciliation> fetchById(String id) async {
    if (!AppConfig.hasApi) {
      final item = state.where((e) => e.id == id).firstOrNull;
      if (item == null) throw StateError('Kayıt bulunamadı');
      return item;
    }

    final dio = ref.read(dioProvider);
    final res = await dio.get<Map<String, dynamic>>('/cash-reconciliations/$id');
    final data = res.data;
    if (data == null) throw StateError('Boş yanıt');
    return _fromDetailJson(data);
  }

  Future<void> save(CashReconciliation value) async {
    if (!AppConfig.hasApi) {
      upsertLocal(value);
      return;
    }

    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/cash-reconciliations/${value.id}',
      data: {
        'expectedSalesTotal': value.expectedSalesTotal,
        'paymentLines': [
          for (final l in value.paymentLines)
            {'typeId': l.typeId, 'amount': l.amount},
        ],
        'expenseLines': [
          for (final l in value.expenseLines)
            {'typeId': l.typeId, 'amount': l.amount},
        ],
      },
    );
    final fresh = await fetchById(value.id);
    upsertLocal(fresh);
  }

  Future<void> updateExpectedSalesTotal({
    required String id,
    required double expectedSalesTotal,
  }) async {
    if (!AppConfig.hasApi) {
      final existing = state.where((e) => e.id == id).firstOrNull;
      if (existing == null) return;
      upsertLocal(existing.copyWith(expectedSalesTotal: expectedSalesTotal));
      return;
    }

    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/cash-reconciliations/$id',
      data: {'expectedSalesTotal': expectedSalesTotal},
    );

    final existing = state.where((e) => e.id == id).firstOrNull;
    if (existing != null) {
      upsertLocal(existing.copyWith(expectedSalesTotal: expectedSalesTotal));
    } else {
      final fresh = await fetchById(id);
      upsertLocal(fresh);
    }
  }

  Future<void> submit(String id) async {
    if (!AppConfig.hasApi) {
      final item = state.where((e) => e.id == id).firstOrNull;
      if (item == null) return;
      upsertLocal(item.copyWith(status: ReconciliationStatus.submitted));
      return;
    }

    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>('/cash-reconciliations/$id/submit');
    final fresh = await fetchById(id);
    upsertLocal(fresh);
  }

  Future<void> approve(String id) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>('/cash-reconciliations/$id/approve');
    final fresh = await fetchById(id);
    upsertLocal(fresh);
  }

  Future<void> reject(String id, String reason) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/cash-reconciliations/$id/reject',
      data: {'reason': reason},
    );
    final fresh = await fetchById(id);
    upsertLocal(fresh);
  }

  Future<void> addAttachment({
    required String reconciliationId,
    required AttachmentKind kind,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final kindString = switch (kind) {
      AttachmentKind.countSlip => 'countSlip',
      AttachmentKind.signedStatement => 'signedStatement',
      AttachmentKind.other => 'other',
    };
    await dio.post<Map<String, dynamic>>(
      '/cash-reconciliations/$reconciliationId/attachments',
      data: {
        'kind': kindString,
        'fileName': fileName,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
      },
    );
    final fresh = await fetchById(reconciliationId);
    upsertLocal(fresh);
  }
}

final posRegisterDailySalesProvider =
    FutureProvider.family<List<PosRegisterDailySale>, ({String branchId, DateTime date})>(
  (ref, args) async {
    if (!AppConfig.hasApi) return const [];
    final dio = ref.read(dioProvider);
    final date = DateTime(args.date.year, args.date.month, args.date.day);
    final res = await dio.get<List<dynamic>>(
      '/sales/daily/registers',
      queryParameters: {
        'branchId': args.branchId,
        'date': date.toIso8601String().substring(0, 10),
      },
    );
    final data = res.data ?? const [];
    return [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          PosRegisterDailySale(
            registerCode: (raw['registerCode'] ?? '').toString(),
            grossTotal: _numToDouble(raw['grossTotal']),
          ),
    ];
  },
);

final posRegisterDailyPaymentsProvider =
    FutureProvider.family<List<PosRegisterDailyPayment>, ({String branchId, DateTime date})>(
  (ref, args) async {
    if (!AppConfig.hasApi) return const [];
    final dio = ref.read(dioProvider);
    final date = DateTime(args.date.year, args.date.month, args.date.day);
    final res = await dio.get<List<dynamic>>(
      '/sales/daily/payments',
      queryParameters: {
        'branchId': args.branchId,
        'date': date.toIso8601String().substring(0, 10),
      },
    );
    final data = res.data ?? const [];
    return [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          PosRegisterDailyPayment(
            registerCode: (raw['registerCode'] ?? '').toString(),
            paymentCode: (raw['paymentCode'] ?? '').toString(),
            amount: _numToDouble(raw['amount']),
          ),
    ];
  },
);

final posDailyProductSalesProvider =
    FutureProvider.family<List<PosDailyProductSale>, ({String branchId, DateTime date, String? registerCode})>(
  (ref, args) async {
    if (!AppConfig.hasApi) return const [];
    final dio = ref.read(dioProvider);
    final date = DateTime(args.date.year, args.date.month, args.date.day);
    final queryParameters = <String, dynamic>{
      'branchId': args.branchId,
      'date': date.toIso8601String().substring(0, 10),
    };
    final registerCode = args.registerCode?.trim();
    if (registerCode != null && registerCode.isNotEmpty) {
      queryParameters['registerCode'] = registerCode;
    }
    final res = await dio.get<List<dynamic>>(
      '/sales/daily/products',
      queryParameters: queryParameters,
    );
    final data = res.data ?? const [];
    return [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          PosDailyProductSale(
            productCode: (raw['productCode'] ?? '').toString(),
            productName: (raw['productName'] ?? '').toString(),
            quantity: _numToDouble(raw['quantity']),
            grossTotal: _numToDouble(raw['grossTotal']),
          ),
    ];
  },
);

final posDailyAdjustmentsProvider =
    FutureProvider.family<List<PosDailyAdjustment>, ({String branchId, DateTime date, String? registerCode})>(
  (ref, args) async {
    if (!AppConfig.hasApi) return const [];
    final dio = ref.read(dioProvider);
    final date = DateTime(args.date.year, args.date.month, args.date.day);
    final queryParameters = <String, dynamic>{
      'branchId': args.branchId,
      'date': date.toIso8601String().substring(0, 10),
    };
    final registerCode = args.registerCode?.trim();
    if (registerCode != null && registerCode.isNotEmpty) {
      queryParameters['registerCode'] = registerCode;
    }
    final res = await dio.get<List<dynamic>>(
      '/sales/daily/adjustments',
      queryParameters: queryParameters,
    );
    final data = res.data ?? const [];
    return [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          PosDailyAdjustment(
            kind: (raw['kind'] ?? '').toString(),
            amount: _numToDouble(raw['amount']),
            count: (raw['count'] is num)
                ? (raw['count'] as num).toInt()
                : int.tryParse((raw['count'] ?? 0).toString()) ?? 0,
          ),
    ];
  },
);

final posCancelledItemsProvider = FutureProvider.family<
    List<PosCancelledItem>,
    ({String branchId, DateTime date, int businessDayStartHour, String? registerCode})>(
  (ref, args) async {
    if (!AppConfig.hasApi) return const [];
    final dio = ref.read(dioProvider);
    final date = DateTime(args.date.year, args.date.month, args.date.day);
    final queryParameters = <String, dynamic>{
      'branchId': args.branchId,
      'date': date.toIso8601String().substring(0, 10),
      'businessDayStartHour': args.businessDayStartHour,
    };
    final registerCode = args.registerCode?.trim();
    if (registerCode != null && registerCode.isNotEmpty) {
      queryParameters['registerCode'] = registerCode;
    }
    final res = await dio.get<List<dynamic>>(
      '/pos/cancellations',
      queryParameters: queryParameters,
    );
    final data = res.data ?? const [];
    return [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          PosCancelledItem(
            registerCode: (raw['registerCode'] ?? '').toString(),
            type: (raw['type'] ?? '').toString(),
            productName: (raw['productName'] ?? '').toString(),
            quantity: _numToDouble(raw['quantity']),
            total: _numToDouble(raw['total']),
            reason: raw['reason']?.toString(),
            cancelledByName: raw['cancelledByName']?.toString(),
            occurredAt: DateTime.tryParse((raw['occurredAt'] ?? '').toString()) ?? date,
            orderId: raw['orderId']?.toString(),
          ),
    ];
  },
);

final posDailySalesGroupsProvider =
    FutureProvider.family<List<PosDailySalesGroup>, ({String branchId, DateTime date, String? registerCode})>(
  (ref, args) async {
    if (!AppConfig.hasApi) return const [];
    final dio = ref.read(dioProvider);
    final date = DateTime(args.date.year, args.date.month, args.date.day);
    final queryParameters = <String, dynamic>{
      'branchId': args.branchId,
      'date': date.toIso8601String().substring(0, 10),
    };
    final registerCode = args.registerCode?.trim();
    if (registerCode != null && registerCode.isNotEmpty) {
      queryParameters['registerCode'] = registerCode;
    }
    final res = await dio.get<List<dynamic>>(
      '/sales/daily/groups',
      queryParameters: queryParameters,
    );
    final data = res.data ?? const [];
    return [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          PosDailySalesGroup(
            groupCode: (raw['groupCode'] ?? '').toString(),
            orderCount: (raw['orderCount'] is num)
                ? (raw['orderCount'] as num).toInt()
                : int.tryParse((raw['orderCount'] ?? 0).toString()) ?? 0,
            grossTotal: _numToDouble(raw['grossTotal']),
          ),
    ];
  },
);

final posLiveDailyTotalProvider =
    FutureProvider.family<double, ({String branchId, DateTime date, int businessDayStartHour, String? registerCode})>(
  (ref, args) async {
    if (!AppConfig.hasApi) return 0;
    final dio = ref.read(dioProvider);
    final date = DateTime(args.date.year, args.date.month, args.date.day);
    final queryParameters = <String, dynamic>{
      'branchId': args.branchId,
      'businessDate': date.toIso8601String().substring(0, 10),
      'businessDayStartHour': args.businessDayStartHour,
    };
    final registerCode = args.registerCode?.trim();
    if (registerCode != null && registerCode.isNotEmpty) {
      queryParameters['registerCode'] = registerCode;
    }
    final res = await dio.get<Map<String, dynamic>>(
      '/pos/live/daily-total',
      queryParameters: queryParameters,
    );
    final data = res.data ?? const {};
    return _numToDouble(data['grossTotal']);
  },
);

final posPullStatusesProvider = FutureProvider<List<PosPullStatus>>((ref) async {
  if (!AppConfig.hasApi) return const [];
  final dio = ref.read(dioProvider);
  List<dynamic> data = const [];
  try {
    final res = await dio.get<List<dynamic>>('/pos/pull/status');
    data = res.data ?? const [];
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      final res = await dio.get<List<dynamic>>('/api/pos/pull/status');
      data = res.data ?? const [];
    } else {
      rethrow;
    }
  }
  return [
    for (final raw in data)
      if (raw is Map<String, dynamic>)
        PosPullStatus(
          branchId: (raw['branchId'] ?? '').toString(),
          branchName: (raw['branchName'] ?? '').toString(),
          isActive: (raw['isActive'] as bool?) ?? true,
          lastPulledAt: DateTime.tryParse((raw['lastPulledAt'] ?? '').toString()),
          lastBusinessDate: DateTime.tryParse((raw['lastBusinessDate'] ?? '').toString()),
        ),
  ];
});

final endOfDayReportsProvider =
    FutureProvider.family<List<EndOfDayReport>, String>((ref, reconciliationId) async {
  if (!AppConfig.hasApi) return const [];
  final dio = ref.read(dioProvider);
  final res = await dio.get<List<dynamic>>(
    '/cash-reconciliations/$reconciliationId/end-of-day-reports',
  );
  final data = res.data ?? const [];
  return [
    for (final raw in data)
      if (raw is Map<String, dynamic>)
        EndOfDayReport(
          id: raw['id'].toString(),
          businessDate: _parseDate(raw['businessDate']),
          reportDate: _parseDate(raw['reportDate']),
          merchantTitle: raw['merchantTitle']?.toString(),
          workplaceNo: raw['workplaceNo']?.toString(),
          terminalNo: raw['terminalNo']?.toString(),
          cardTotal: _numToDouble(raw['cardTotal']),
          fastTotal: _numToDouble(raw['fastTotal']),
          createdAt: DateTime.tryParse((raw['createdAt'] ?? '').toString()) ?? DateTime.now(),
        ),
  ];
});

final salesRepositoryProvider =
    Provider<SalesRepository>((ref) {
      if (!AppConfig.hasApi) {
        return const FakeSalesRepository();
      }
      return ApiSalesRepository(ref.watch(dioProvider));
    });

abstract class SalesRepository {
  Future<double> getDailySales({
    required String branchId,
    required DateTime date,
  });
}

class FakeSalesRepository implements SalesRepository {
  const FakeSalesRepository();

  @override
  Future<double> getDailySales({
    required String branchId,
    required DateTime date,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final seed = '${branchId}_${date.toIso8601String().substring(0, 10)}';
    final rand = Random(seed.hashCode);
    return (rand.nextInt(450000) + 50000) / 100;
  }
}

class ApiSalesRepository implements SalesRepository {
  ApiSalesRepository(this._dio);

  final Dio _dio;

  @override
  Future<double> getDailySales({
    required String branchId,
    required DateTime date,
  }) async {
    final day = DateTime(date.year, date.month, date.day);
    final response = await _dio.get<Map<String, dynamic>>(
      '/sales/daily',
      queryParameters: {
        'branchId': branchId,
        'date': day.toIso8601String().substring(0, 10),
      },
    );

    final data = response.data;
    if (data == null) {
      throw StateError('Boş yanıt');
    }

    final raw = data['total'];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.parse(raw);
    throw StateError('Geçersiz total alanı');
  }
}

final pendingApprovalsCountProvider = Provider<int>((ref) {
  final session = ref.watch(authControllerProvider).asData?.value;
  if (session?.role != UserRole.manager) return 0;
  final items = ref.watch(reconciliationsProvider);
  return items.where((e) => e.status == ReconciliationStatus.submitted).length;
});

final mismatchesCountProvider = Provider<int>((ref) {
  final items = ref.watch(reconciliationsProvider);
  return items
      .where((e) =>
          e.status != ReconciliationStatus.draft && e.difference.abs() > 0.01)
      .length;
});

final inventoryProductsProvider =
    NotifierProvider<InventoryProductsStore, List<InventoryProduct>>(
  InventoryProductsStore.new,
);

class InventoryProductsStore extends Notifier<List<InventoryProduct>> {
  String _query = '';

  @override
  List<InventoryProduct> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      } else {
        state = const [];
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [];
  }

  void setQuery(String value) {
    _query = value.trim();
    if (AppConfig.hasApi) {
      refresh();
    }
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>(
      '/inv/products',
      queryParameters: {
        if (_query.isNotEmpty) 'q': _query,
      },
    );
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          InventoryProduct(
            id: raw['id'].toString(),
            code: raw['code']?.toString(),
            name: (raw['name'] ?? '').toString(),
            unit: (raw['unit'] ?? 'adet').toString(),
            isActive: (raw['isActive'] as bool?) ?? true,
          ),
    ];
  }

  Future<void> add({
    required String name,
    required String unit,
    String? code,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/inv/products',
      data: {
        'name': name,
        'unit': unit,
        if (code?.trim().isNotEmpty ?? false) 'code': code!.trim(),
      },
    );
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) return;
    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/inv/products/$id',
      data: {'isActive': !item.isActive},
    );
    await refresh();
  }
}

final inventoryWarehousesProvider =
    NotifierProvider<InventoryWarehousesStore, List<InventoryWarehouse>>(
  InventoryWarehousesStore.new,
);

class InventoryWarehousesStore extends Notifier<List<InventoryWarehouse>> {
  String? _branchId;

  @override
  List<InventoryWarehouse> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        _branchId ??= session.branchId;
        refresh();
      } else {
        state = const [];
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      _branchId ??= session.branchId;
      Future.microtask(refresh);
      return const [];
    }

    _branchId ??= 'branch-1';
    return _demoForBranch(_branchId);
  }

  void setBranch(String? branchId) {
    _branchId = branchId;
    if (AppConfig.hasApi) {
      refresh();
      return;
    }
    state = _demoForBranch(_branchId);
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>(
      '/inv/warehouses',
      queryParameters: {
        if (_branchId != null && _branchId!.isNotEmpty) 'branchId': _branchId,
      },
    );
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          InventoryWarehouse(
            id: raw['id'].toString(),
            branchId: raw['branchId'].toString(),
            code: (raw['code'] ?? '').toString(),
            name: (raw['name'] ?? '').toString(),
            isActive: (raw['isActive'] as bool?) ?? true,
          ),
    ];
  }

  Future<void> add({
    required String branchId,
    required String name,
    String? code,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/inv/warehouses',
      data: {
        'branchId': branchId,
        'name': name,
        if (code?.trim().isNotEmpty ?? false) 'code': code!.trim(),
      },
    );
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) return;
    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/inv/warehouses/$id',
      data: {'isActive': !item.isActive},
    );
    await refresh();
  }

  List<InventoryWarehouse> _demoForBranch(String? branchId) {
    final b = (branchId == null || branchId.isEmpty) ? 'branch-1' : branchId;
    return [
      InventoryWarehouse(
        id: '$b-wh-1',
        branchId: b,
        code: 'DEP-01',
        name: 'Ana Depo',
        isActive: true,
      ),
      InventoryWarehouse(
        id: '$b-wh-2',
        branchId: b,
        code: 'DEP-02',
        name: 'Düşüm Deposu',
        isActive: true,
      ),
    ];
  }
}

final inventoryTransactionsProvider =
    NotifierProvider<InventoryTransactionsStore, List<InventoryStockTransaction>>(
  InventoryTransactionsStore.new,
);

class InventoryTransactionsStore extends Notifier<List<InventoryStockTransaction>> {
  String? _branchId;
  String? _warehouseId;

  @override
  List<InventoryStockTransaction> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        _branchId ??= session.branchId;
        refresh();
      } else {
        state = const [];
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      _branchId ??= session.branchId;
      Future.microtask(refresh);
      return const [];
    }

    return const [];
  }

  void setBranch(String? branchId) {
    _branchId = branchId;
    if (AppConfig.hasApi) {
      refresh();
    }
  }

  void setWarehouse(String? warehouseId) {
    _warehouseId = warehouseId;
    if (AppConfig.hasApi) {
      refresh();
    }
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>(
      '/inv/stock-transactions',
      queryParameters: {
        if (_branchId != null && _branchId!.isNotEmpty) 'branchId': _branchId,
        if (_warehouseId != null && _warehouseId!.isNotEmpty) 'warehouseId': _warehouseId,
      },
    );
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          InventoryStockTransaction(
            id: raw['id'].toString(),
            branchId: raw['branchId'].toString(),
            warehouseId: raw['warehouseId'].toString(),
            businessDate: DateTime.parse(raw['businessDate'].toString()),
            kind: (raw['kind'] ?? '').toString(),
            referenceNo: raw['referenceNo']?.toString(),
            notes: raw['notes']?.toString(),
            createdByUserId: raw['createdByUserId'].toString(),
            lines: const [],
          ),
    ];
  }

  Future<void> create({
    required String branchId,
    required String warehouseId,
    required DateTime businessDate,
    required String kind,
    String? referenceNo,
    String? notes,
    required List<InventoryStockLine> lines,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/inv/stock-transactions',
      data: {
        'branchId': branchId,
        'warehouseId': warehouseId,
        'businessDate': DateTime(businessDate.year, businessDate.month, businessDate.day)
            .toIso8601String()
            .substring(0, 10),
        'kind': kind,
        if (referenceNo != null && referenceNo.trim().isNotEmpty) 'referenceNo': referenceNo.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'lines': [
          for (final l in lines)
            {'productId': l.productId, 'quantity': l.quantity, 'unitCost': l.unitCost},
        ],
      },
    );
    await refresh();
  }
}

final inventoryCountsProvider =
    NotifierProvider<InventoryCountsStore, List<InventoryStockCount>>(
  InventoryCountsStore.new,
);

class InventoryCountsStore extends Notifier<List<InventoryStockCount>> {
  String? _branchId;
  String? _warehouseId;
  String? _status;

  @override
  List<InventoryStockCount> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        _branchId ??= session.branchId;
        refresh();
      } else {
        state = const [];
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      _branchId ??= session.branchId;
      Future.microtask(refresh);
      return const [];
    }

    return const [];
  }

  void setBranch(String? branchId) {
    _branchId = branchId;
    if (AppConfig.hasApi) refresh();
  }

  void setWarehouse(String? warehouseId) {
    _warehouseId = warehouseId;
    if (AppConfig.hasApi) refresh();
  }

  void setStatus(String? status) {
    _status = status;
    if (AppConfig.hasApi) refresh();
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>(
      '/inv/stock-counts',
      queryParameters: {
        if (_branchId != null && _branchId!.isNotEmpty) 'branchId': _branchId,
        if (_warehouseId != null && _warehouseId!.isNotEmpty)
          'warehouseId': _warehouseId,
        if (_status != null && _status!.isNotEmpty) 'status': _status,
      },
    );
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          InventoryStockCount(
            id: raw['id'].toString(),
            branchId: raw['branchId'].toString(),
            branchName: raw['branchName']?.toString(),
            warehouseId: raw['warehouseId'].toString(),
            warehouseName: raw['warehouseName']?.toString(),
            businessDate: DateTime.parse(raw['businessDate'].toString()),
            status: (raw['status'] ?? '').toString(),
            createdByUserId: raw['createdByUserId'].toString(),
            approvedByUserId: raw['approvedByUserId']?.toString(),
            rejectionReason: raw['rejectionReason']?.toString(),
            linesCount: (raw['linesCount'] as num?)?.toInt() ??
                int.tryParse(raw['linesCount']?.toString() ?? '') ??
                0,
            diffAbsTotal: (raw['diffAbsTotal'] as num?)?.toDouble() ??
                double.tryParse(raw['diffAbsTotal']?.toString() ?? '') ??
                0,
          ),
    ];
  }

  Future<String?> createDraft({
    required String branchId,
    required String warehouseId,
    required DateTime businessDate,
  }) async {
    if (!AppConfig.hasApi) return null;
    final day = DateTime(businessDate.year, businessDate.month, businessDate.day)
        .toIso8601String()
        .substring(0, 10);
    final dio = ref.read(dioProvider);
    final res = await dio.post<Map<String, dynamic>>(
      '/inv/stock-counts',
      data: {
        'branchId': branchId,
        'warehouseId': warehouseId,
        'businessDate': day,
      },
    );
    await refresh();
    return res.data?['id']?.toString();
  }

  Future<void> saveLines({
    required String countId,
    required List<({String productId, double countedQty})> lines,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/inv/stock-counts/$countId/lines',
      data: {
        'lines': [
          for (final l in lines)
            {'productId': l.productId, 'countedQty': l.countedQty},
        ],
      },
    );
    ref.invalidate(inventoryStockCountDetailProvider(countId));
    await refresh();
  }

  Future<void> submit(String countId) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>('/inv/stock-counts/$countId/submit');
    ref.invalidate(inventoryStockCountDetailProvider(countId));
    await refresh();
  }

  Future<void> approve(String countId) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>('/inv/stock-counts/$countId/approve');
    ref.invalidate(inventoryStockCountDetailProvider(countId));
    await refresh();
  }

  Future<void> reject({
    required String countId,
    required String reason,
  }) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.post<Map<String, dynamic>>(
      '/inv/stock-counts/$countId/reject',
      data: {'reason': reason},
    );
    ref.invalidate(inventoryStockCountDetailProvider(countId));
    await refresh();
  }
}

final inventoryStockCountDetailProvider =
    FutureProvider.family<InventoryStockCountDetail, String>((ref, countId) async {
  if (!AppConfig.hasApi) {
    throw StateError('API modu gerekli');
  }
  final dio = ref.read(dioProvider);
  final res = await dio.get<Map<String, dynamic>>('/inv/stock-counts/$countId');
  final data = res.data;
  if (data == null) throw StateError('Boş yanıt');

  double asDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  final header = InventoryStockCount(
    id: data['id'].toString(),
    branchId: data['branchId'].toString(),
    branchName: data['branchName']?.toString(),
    warehouseId: data['warehouseId'].toString(),
    warehouseName: data['warehouseName']?.toString(),
    businessDate: DateTime.parse(data['businessDate'].toString()),
    status: (data['status'] ?? '').toString(),
    createdByUserId: data['createdByUserId'].toString(),
    approvedByUserId: data['approvedByUserId']?.toString(),
    rejectionReason: data['rejectionReason']?.toString(),
    linesCount: (data['lines'] is List) ? (data['lines'] as List).length : 0,
    diffAbsTotal: asDouble(data['totals']?['diffAbsTotal']),
  );

  final rawLines = data['lines'];
  final lines = <InventoryStockCountLine>[
    if (rawLines is List)
      for (final raw in rawLines)
        if (raw is Map<String, dynamic>)
          InventoryStockCountLine(
            productId: raw['productId'].toString(),
            productName: (raw['productName'] ?? '').toString(),
            unit: (raw['unit'] ?? 'adet').toString(),
            countedQty: asDouble(raw['countedQty']),
            onhandQty: asDouble(raw['onhandQty']),
            diffQty: asDouble(raw['diffQty']),
          ),
  ];

  final rawTotals = data['totals'];
  final totals = InventoryStockCountTotals(
    countedTotal: asDouble(rawTotals?['countedTotal']),
    onhandTotal: asDouble(rawTotals?['onhandTotal']),
    diffTotal: asDouble(rawTotals?['diffTotal']),
    diffAbsTotal: asDouble(rawTotals?['diffAbsTotal']),
  );

  return InventoryStockCountDetail(header: header, lines: lines, totals: totals);
});

final inventoryRecipesProvider =
    NotifierProvider<InventoryRecipesStore, List<InventoryRecipe>>(
  InventoryRecipesStore.new,
);

class InventoryRecipesStore extends Notifier<List<InventoryRecipe>> {
  String _query = '';

  @override
  List<InventoryRecipe> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      } else {
        state = const [];
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [];
  }

  void setQuery(String value) {
    _query = value.trim();
    if (AppConfig.hasApi) refresh();
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>(
      '/inv/recipes',
      queryParameters: {
        if (_query.isNotEmpty) 'q': _query,
      },
    );
    final data = res.data ?? const [];
    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          InventoryRecipe(
            id: raw['id'].toString(),
            productId: raw['productId'].toString(),
            productName: (raw['productName'] ?? '').toString(),
            code: raw['code']?.toString(),
            name: (raw['name'] ?? '').toString(),
            description: raw['description']?.toString(),
            yieldQty: (raw['yieldQty'] as num?)?.toDouble() ??
                double.tryParse(raw['yieldQty']?.toString() ?? '') ??
                1,
            yieldUnit: (raw['yieldUnit'] ?? 'adet').toString(),
            gimOran: (raw['gimOran'] as num?)?.toDouble() ??
                double.tryParse(raw['gimOran']?.toString() ?? ''),
            isActive: (raw['isActive'] as bool?) ?? true,
            linesCount: (raw['linesCount'] as num?)?.toInt() ??
                int.tryParse(raw['linesCount']?.toString() ?? '') ??
                0,
          ),
    ];
  }

  Future<String?> upsert({
    required String productId,
    String? code,
    String? name,
    String? description,
    required double yieldQty,
    required String yieldUnit,
    double? gimOran,
    required List<({String ingredientProductId, double quantity, String? unit, double? wasteRate})>
        lines,
  }) async {
    if (!AppConfig.hasApi) return null;
    final dio = ref.read(dioProvider);
    final res = await dio.post<Map<String, dynamic>>(
      '/inv/recipes',
      data: {
        'productId': productId,
        if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'yieldQty': yieldQty,
        'yieldUnit': yieldUnit,
        'gimOran': ?gimOran,
        'lines': [
          for (final l in lines)
            {
              'ingredientProductId': l.ingredientProductId,
              'quantity': l.quantity,
              if (l.unit != null && l.unit!.trim().isNotEmpty) 'unit': l.unit,
              if (l.wasteRate != null) 'wasteRate': l.wasteRate,
            },
        ],
      },
    );
    final id = res.data?['id']?.toString();
    if (id != null) {
      ref.invalidate(inventoryRecipeDetailProvider(id));
    }
    await refresh();
    return id;
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) return;
    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/inv/recipes/$id',
      data: {'isActive': !item.isActive},
    );
    ref.invalidate(inventoryRecipeDetailProvider(id));
    await refresh();
  }
}

final inventoryRecipeDetailProvider =
    FutureProvider.family<InventoryRecipeDetail, String>((ref, recipeId) async {
  if (!AppConfig.hasApi) {
    throw StateError('API modu gerekli');
  }
  final dio = ref.read(dioProvider);
  final res = await dio.get<Map<String, dynamic>>('/inv/recipes/$recipeId');
  final data = res.data;
  if (data == null) throw StateError('Boş yanıt');

  double asDouble(dynamic raw, [double fallback = 0]) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  final header = InventoryRecipe(
    id: data['id'].toString(),
    productId: data['productId'].toString(),
    productName: (data['productName'] ?? '').toString(),
    code: data['code']?.toString(),
    name: (data['name'] ?? '').toString(),
    description: data['description']?.toString(),
    yieldQty: asDouble(data['yieldQty'], 1),
    yieldUnit: (data['yieldUnit'] ?? 'adet').toString(),
    gimOran: data['gimOran'] == null ? null : asDouble(data['gimOran']),
    isActive: (data['isActive'] as bool?) ?? true,
    linesCount: (data['lines'] is List) ? (data['lines'] as List).length : 0,
  );

  final rawLines = data['lines'];
  final lines = <InventoryRecipeLine>[
    if (rawLines is List)
      for (final raw in rawLines)
        if (raw is Map<String, dynamic>)
          InventoryRecipeLine(
            ingredientProductId: raw['ingredientProductId'].toString(),
            ingredientProductName: (raw['ingredientProductName'] ?? '').toString(),
            unit: (raw['unit'] ?? 'adet').toString(),
            quantity: asDouble(raw['quantity']),
            wasteRate: asDouble(raw['wasteRate']),
            avgUnitCost: asDouble(raw['avgUnitCost']),
            lineCost: asDouble(raw['lineCost']),
          ),
  ];

  final rawTotals = data['totals'];
  final totals = InventoryRecipeTotals(
    recipeCost: asDouble(rawTotals?['recipeCost']),
  );

  return InventoryRecipeDetail(header: header, lines: lines, totals: totals);
});

final crmFirmsProvider =
    NotifierProvider<CrmFirmsStore, List<CrmFirm>>(CrmFirmsStore.new);

class CrmFirmsStore extends Notifier<List<CrmFirm>> {
  String _query = '';

  @override
  List<CrmFirm> build() {
    ref.listen(authControllerProvider, (prev, next) {
      final session = next.asData?.value;
      if (AppConfig.hasApi && session != null) {
        refresh();
      } else {
        state = const [];
      }
    });

    final session = ref.watch(authControllerProvider).asData?.value;
    if (AppConfig.hasApi && session != null) {
      Future.microtask(refresh);
      return const [];
    }

    return const [];
  }

  void setQuery(String value) {
    _query = value.trim();
    if (AppConfig.hasApi) refresh();
  }

  Future<void> refresh() async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>(
      '/crm/firms',
      queryParameters: {
        if (_query.isNotEmpty) 'q': _query,
      },
    );
    final data = res.data ?? const [];
    double? asDouble(dynamic raw) {
      if (raw == null) return null;
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw.toString());
    }

    DateTime? asDate(dynamic raw) {
      if (raw == null) return null;
      try {
        return DateTime.parse(raw.toString());
      } catch (_) {
        return null;
      }
    }

    state = [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          CrmFirm(
            id: raw['id'].toString(),
            firmName: (raw['firmName'] ?? '').toString(),
            tradeName: raw['tradeName']?.toString(),
            integrationCode: raw['integrationCode']?.toString(),
            firmType: raw['firmType']?.toString(),
            isCurrent: (raw['isCurrent'] as bool?) ?? true,
            customerGroup: raw['customerGroup']?.toString(),
            email: raw['email']?.toString(),
            priceNo: raw['priceNo']?.toString(),
            wholesalePriceNo: raw['wholesalePriceNo']?.toString(),
            invoiceCompany: raw['invoiceCompany']?.toString(),
            generalDiscount: asDouble(raw['generalDiscount']),
            paymentMethod: raw['paymentMethod']?.toString(),
            taxOffice: raw['taxOffice']?.toString(),
            taxNo: raw['taxNo']?.toString(),
            isEInvoice: (raw['isEInvoice'] as bool?) ?? false,
            cargoCode: raw['cargoCode']?.toString(),
            purchasePriceNo: raw['purchasePriceNo']?.toString(),
            paymentVkn: raw['paymentVkn']?.toString(),
            iban: raw['iban']?.toString(),
            notes: raw['notes']?.toString(),
            isActive: (raw['isActive'] as bool?) ?? true,
            updatedAt: asDate(raw['updatedAt']),
          ),
    ];
  }

  Future<String?> create(CrmFirmDraft draft) async {
    if (!AppConfig.hasApi) return null;
    final dio = ref.read(dioProvider);
    final res = await dio.post<Map<String, dynamic>>(
      '/crm/firms',
      data: draft.toJson(),
    );
    await refresh();
    return res.data?['id']?.toString();
  }

  Future<void> update(String id, CrmFirmDraft draft) async {
    if (!AppConfig.hasApi) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/crm/firms/$id',
      data: draft.toJson(),
    );
    ref.invalidate(crmFirmDetailProvider(id));
    await refresh();
  }

  Future<void> toggleActive(String id) async {
    if (!AppConfig.hasApi) return;
    final item = state.where((e) => e.id == id).firstOrNull;
    if (item == null) return;
    final dio = ref.read(dioProvider);
    await dio.patch<Map<String, dynamic>>(
      '/crm/firms/$id',
      data: {'isActive': !item.isActive},
    );
    ref.invalidate(crmFirmDetailProvider(id));
    await refresh();
  }
}

final crmFirmDetailProvider =
    FutureProvider.family<CrmFirm, String>((ref, id) async {
  if (!AppConfig.hasApi) throw StateError('API modu gerekli');
  final dio = ref.read(dioProvider);
  final res = await dio.get<Map<String, dynamic>>('/crm/firms/$id');
  final raw = res.data;
  if (raw == null) throw StateError('Boş yanıt');

  double? asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  DateTime? asDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }

  return CrmFirm(
    id: raw['id'].toString(),
    firmName: (raw['firmName'] ?? '').toString(),
    tradeName: raw['tradeName']?.toString(),
    integrationCode: raw['integrationCode']?.toString(),
    firmType: raw['firmType']?.toString(),
    isCurrent: (raw['isCurrent'] as bool?) ?? true,
    customerGroup: raw['customerGroup']?.toString(),
    email: raw['email']?.toString(),
    priceNo: raw['priceNo']?.toString(),
    wholesalePriceNo: raw['wholesalePriceNo']?.toString(),
    invoiceCompany: raw['invoiceCompany']?.toString(),
    generalDiscount: asDouble(raw['generalDiscount']),
    paymentMethod: raw['paymentMethod']?.toString(),
    taxOffice: raw['taxOffice']?.toString(),
    taxNo: raw['taxNo']?.toString(),
    isEInvoice: (raw['isEInvoice'] as bool?) ?? false,
    cargoCode: raw['cargoCode']?.toString(),
    purchasePriceNo: raw['purchasePriceNo']?.toString(),
    paymentVkn: raw['paymentVkn']?.toString(),
    iban: raw['iban']?.toString(),
    notes: raw['notes']?.toString(),
    isActive: (raw['isActive'] as bool?) ?? true,
    updatedAt: asDate(raw['updatedAt']),
  );
});

final inventoryOnHandProvider =
    FutureProvider.family<List<InventoryOnHand>, ({String branchId, String? warehouseId})>(
  (ref, arg) async {
    if (!AppConfig.hasApi) return const [];
    final dio = ref.read(dioProvider);
    final res = await dio.get<List<dynamic>>(
      '/inv/stock-on-hand',
      queryParameters: {
        'branchId': arg.branchId,
        if (arg.warehouseId != null && arg.warehouseId!.isNotEmpty) 'warehouseId': arg.warehouseId,
      },
    );
    final data = res.data ?? const [];
    return [
      for (final raw in data)
        if (raw is Map<String, dynamic>)
          InventoryOnHand(
            productId: raw['productId'].toString(),
            productName: (raw['productName'] ?? '').toString(),
            unit: (raw['unit'] ?? 'adet').toString(),
            quantity: (raw['quantity'] as num?)?.toDouble() ??
                double.tryParse(raw['quantity']?.toString() ?? '') ??
                0,
          ),
    ];
  },
);

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class CrmFirmDraft {
  const CrmFirmDraft({
    this.firmName,
    this.tradeName,
    this.integrationCode,
    this.firmType,
    this.isCurrent,
    this.customerGroup,
    this.email,
    this.priceNo,
    this.wholesalePriceNo,
    this.invoiceCompany,
    this.generalDiscount,
    this.paymentMethod,
    this.taxOffice,
    this.taxNo,
    this.isEInvoice,
    this.cargoCode,
    this.purchasePriceNo,
    this.paymentVkn,
    this.iban,
    this.notes,
    this.isActive,
  });

  final String? firmName;
  final String? tradeName;
  final String? integrationCode;
  final String? firmType;
  final bool? isCurrent;
  final String? customerGroup;
  final String? email;
  final String? priceNo;
  final String? wholesalePriceNo;
  final String? invoiceCompany;
  final double? generalDiscount;
  final String? paymentMethod;
  final String? taxOffice;
  final String? taxNo;
  final bool? isEInvoice;
  final String? cargoCode;
  final String? purchasePriceNo;
  final String? paymentVkn;
  final String? iban;
  final String? notes;
  final bool? isActive;

  Map<String, dynamic> toJson() {
    return {
      if (firmName != null) 'firmName': firmName,
      if (tradeName != null) 'tradeName': tradeName,
      if (integrationCode != null) 'integrationCode': integrationCode,
      if (firmType != null) 'firmType': firmType,
      if (isCurrent != null) 'isCurrent': isCurrent,
      if (customerGroup != null) 'customerGroup': customerGroup,
      if (email != null) 'email': email,
      if (priceNo != null) 'priceNo': priceNo,
      if (wholesalePriceNo != null) 'wholesalePriceNo': wholesalePriceNo,
      if (invoiceCompany != null) 'invoiceCompany': invoiceCompany,
      if (generalDiscount != null) 'generalDiscount': generalDiscount,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (taxOffice != null) 'taxOffice': taxOffice,
      if (taxNo != null) 'taxNo': taxNo,
      if (isEInvoice != null) 'isEInvoice': isEInvoice,
      if (cargoCode != null) 'cargoCode': cargoCode,
      if (purchasePriceNo != null) 'purchasePriceNo': purchasePriceNo,
      if (paymentVkn != null) 'paymentVkn': paymentVkn,
      if (iban != null) 'iban': iban,
      if (notes != null) 'notes': notes,
      if (isActive != null) 'isActive': isActive,
    };
  }
}
