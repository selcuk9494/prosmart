import 'package:flutter/foundation.dart';

enum ReconciliationStatus {
  draft,
  submitted,
  approved,
  rejected,
}

enum AttachmentKind {
  countSlip,
  signedStatement,
  other,
}

@immutable
class Branch {
  const Branch({
    required this.id,
    required this.name,
    this.code,
    this.businessDayStartHour = 0,
    this.isActive = true,
  });

  final String id;
  final String? code;
  final String name;
  final int businessDayStartHour;
  final bool isActive;

  Branch copyWith({
    String? id,
    String? code,
    String? name,
    int? businessDayStartHour,
    bool? isActive,
  }) {
    return Branch(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      businessDayStartHour: businessDayStartHour ?? this.businessDayStartHour,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class BranchDataSource {
  const BranchDataSource({
    required this.branchId,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.ssl,
    required this.isActive,
    this.updatedAt,
  });

  final String branchId;
  final String host;
  final int port;
  final String database;
  final String username;
  final bool ssl;
  final bool isActive;
  final DateTime? updatedAt;

  BranchDataSource copyWith({
    String? branchId,
    String? host,
    int? port,
    String? database,
    String? username,
    bool? ssl,
    bool? isActive,
    DateTime? updatedAt,
  }) {
    return BranchDataSource(
      branchId: branchId ?? this.branchId,
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      ssl: ssl ?? this.ssl,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@immutable
class PaymentType {
  const PaymentType({
    required this.id,
    required this.name,
    this.code,
    this.isActive = true,
  });

  final String id;
  final String? code;
  final String name;
  final bool isActive;

  PaymentType copyWith({String? id, String? code, String? name, bool? isActive}) {
    return PaymentType(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class ExpenseType {
  const ExpenseType({required this.id, required this.name, this.isActive = true});

  final String id;
  final String name;
  final bool isActive;

  ExpenseType copyWith({String? id, String? name, bool? isActive}) {
    return ExpenseType(
      id: id ?? this.id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class IncomeCenter {
  const IncomeCenter({
    required this.id,
    required this.name,
    this.code,
    this.isActive = true,
  });

  final String id;
  final String? code;
  final String name;
  final bool isActive;

  IncomeCenter copyWith({
    String? id,
    String? code,
    String? name,
    bool? isActive,
  }) {
    return IncomeCenter(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class CashRegister {
  const CashRegister({
    required this.id,
    required this.code,
    required this.name,
    this.isActive = true,
  });

  final String id;
  final String code;
  final String name;
  final bool isActive;

  CashRegister copyWith({
    String? id,
    String? code,
    String? name,
    bool? isActive,
  }) {
    return CashRegister(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class MinMaxDefinition {
  const MinMaxDefinition({
    required this.id,
    required this.branchId,
    required this.productName,
    required this.minQty,
    required this.maxQty,
  });

  final String id;
  final String branchId;
  final String productName;
  final double minQty;
  final double maxQty;

  MinMaxDefinition copyWith({
    String? id,
    String? branchId,
    String? productName,
    double? minQty,
    double? maxQty,
  }) {
    return MinMaxDefinition(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      productName: productName ?? this.productName,
      minQty: minQty ?? this.minQty,
      maxQty: maxQty ?? this.maxQty,
    );
  }
}

@immutable
class UnproducedProduct {
  const UnproducedProduct({
    required this.id,
    required this.productName,
    required this.isBlocked,
  });

  final String id;
  final String productName;
  final bool isBlocked;

  UnproducedProduct copyWith({
    String? id,
    String? productName,
    bool? isBlocked,
  }) {
    return UnproducedProduct(
      id: id ?? this.id,
      productName: productName ?? this.productName,
      isBlocked: isBlocked ?? this.isBlocked,
    );
  }
}

@immutable
class UnitSet {
  const UnitSet({
    required this.id,
    required this.code,
    required this.name,
    this.isActive = true,
  });

  final String id;
  final String code;
  final String name;
  final bool isActive;

  UnitSet copyWith({
    String? id,
    String? code,
    String? name,
    bool? isActive,
  }) {
    return UnitSet(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class AccountPeriod {
  const AccountPeriod({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.isActive = true,
  });

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;

  AccountPeriod copyWith({
    String? id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    bool? isActive,
  }) {
    return AccountPeriod(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class Workstation {
  const Workstation({
    required this.id,
    required this.code,
    required this.name,
    this.isActive = true,
  });

  final String id;
  final String code;
  final String name;
  final bool isActive;

  Workstation copyWith({
    String? id,
    String? code,
    String? name,
    bool? isActive,
  }) {
    return Workstation(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    this.isActive = true,
  });

  final String id;
  final String username;
  final String displayName;
  final String role;
  final bool isActive;

  AppUser copyWith({
    String? id,
    String? username,
    String? displayName,
    String? role,
    bool? isActive,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class MoneyLine {
  const MoneyLine({required this.typeId, required this.amount});

  final String typeId;
  final double amount;

  MoneyLine copyWith({String? typeId, double? amount}) {
    return MoneyLine(
      typeId: typeId ?? this.typeId,
      amount: amount ?? this.amount,
    );
  }
}

@immutable
class Attachment {
  const Attachment({
    required this.id,
    required this.kind,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String id;
  final AttachmentKind kind;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
}

@immutable
class PosRegisterDailySale {
  const PosRegisterDailySale({
    required this.registerCode,
    required this.grossTotal,
  });

  final String registerCode;
  final double grossTotal;
}

@immutable
class PosRegisterDailyPayment {
  const PosRegisterDailyPayment({
    required this.registerCode,
    required this.paymentCode,
    required this.amount,
  });

  final String registerCode;
  final String paymentCode;
  final double amount;
}

@immutable
class PosDailyProductSale {
  const PosDailyProductSale({
    required this.productCode,
    required this.productName,
    required this.quantity,
    required this.grossTotal,
  });

  final String productCode;
  final String productName;
  final double quantity;
  final double grossTotal;
}

@immutable
class PosDailyAdjustment {
  const PosDailyAdjustment({
    required this.kind,
    required this.amount,
    required this.count,
  });

  final String kind;
  final double amount;
  final int count;
}

@immutable
class PosCancelledItem {
  const PosCancelledItem({
    required this.registerCode,
    required this.type,
    required this.productName,
    required this.quantity,
    required this.total,
    required this.reason,
    required this.cancelledByName,
    required this.occurredAt,
    required this.orderId,
  });

  final String registerCode;
  final String type;
  final String productName;
  final double quantity;
  final double total;
  final String? reason;
  final String? cancelledByName;
  final DateTime occurredAt;
  final String? orderId;
}

@immutable
class PosDailySalesGroup {
  const PosDailySalesGroup({
    required this.groupCode,
    required this.orderCount,
    required this.grossTotal,
  });

  final String groupCode;
  final int orderCount;
  final double grossTotal;
}

@immutable
class PosPullStatus {
  const PosPullStatus({
    required this.branchId,
    required this.branchName,
    required this.isActive,
    required this.lastPulledAt,
    required this.lastBusinessDate,
  });

  final String branchId;
  final String branchName;
  final bool isActive;
  final DateTime? lastPulledAt;
  final DateTime? lastBusinessDate;
}

@immutable
class EndOfDayReport {
  const EndOfDayReport({
    required this.id,
    required this.businessDate,
    required this.reportDate,
    required this.merchantTitle,
    required this.workplaceNo,
    required this.terminalNo,
    required this.cardTotal,
    required this.fastTotal,
    required this.createdAt,
  });

  final String id;
  final DateTime businessDate;
  final DateTime reportDate;
  final String? merchantTitle;
  final String? workplaceNo;
  final String? terminalNo;
  final double cardTotal;
  final double fastTotal;
  final DateTime createdAt;
}

@immutable
class CashReconciliation {
  const CashReconciliation({
    required this.id,
    required this.branchId,
    required this.date,
    required this.expectedSalesTotal,
    required this.paymentLines,
    required this.expenseLines,
    required this.attachments,
    required this.status,
    required this.createdByUserId,
    this.approvedByUserId,
    this.rejectionReason,
    this.paymentTotalCached,
    this.attachmentsCountCached,
    this.ocrCardTotalCached,
    this.ocrFastTotalCached,
    this.hasEndOfDayReportCached,
    this.manualCardTotalCached,
  });

  final String id;
  final String branchId;
  final DateTime date;
  final double expectedSalesTotal;
  final List<MoneyLine> paymentLines;
  final List<MoneyLine> expenseLines;
  final List<Attachment> attachments;
  final ReconciliationStatus status;
  final String createdByUserId;
  final String? approvedByUserId;
  final String? rejectionReason;
  final double? paymentTotalCached;
  final int? attachmentsCountCached;
  final double? ocrCardTotalCached;
  final double? ocrFastTotalCached;
  final bool? hasEndOfDayReportCached;
  final double? manualCardTotalCached;

  double get paymentTotal {
    if (paymentLines.isNotEmpty) {
      return paymentLines.fold(0, (prev, e) => prev + e.amount);
    }
    return paymentTotalCached ?? 0;
  }

  double get expenseTotal =>
      expenseLines.fold(0, (prev, e) => prev + e.amount);

  double get difference => paymentTotal - expectedSalesTotal;

  int get attachmentsCount => attachmentsCountCached ?? attachments.length;

  double get ocrCardTotal => ocrCardTotalCached ?? 0;
  double get ocrFastTotal => ocrFastTotalCached ?? 0;
  double get manualCardTotal => manualCardTotalCached ?? 0;
  bool get hasEndOfDayReport => hasEndOfDayReportCached ?? false;

  CashReconciliation copyWith({
    String? id,
    String? branchId,
    DateTime? date,
    double? expectedSalesTotal,
    List<MoneyLine>? paymentLines,
    List<MoneyLine>? expenseLines,
    List<Attachment>? attachments,
    ReconciliationStatus? status,
    String? createdByUserId,
    String? approvedByUserId,
    String? rejectionReason,
    double? paymentTotalCached,
    int? attachmentsCountCached,
    double? ocrCardTotalCached,
    double? ocrFastTotalCached,
    bool? hasEndOfDayReportCached,
    double? manualCardTotalCached,
  }) {
    return CashReconciliation(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      date: date ?? this.date,
      expectedSalesTotal: expectedSalesTotal ?? this.expectedSalesTotal,
      paymentLines: paymentLines ?? this.paymentLines,
      expenseLines: expenseLines ?? this.expenseLines,
      attachments: attachments ?? this.attachments,
      status: status ?? this.status,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      approvedByUserId: approvedByUserId ?? this.approvedByUserId,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      paymentTotalCached: paymentTotalCached ?? this.paymentTotalCached,
      attachmentsCountCached: attachmentsCountCached ?? this.attachmentsCountCached,
      ocrCardTotalCached: ocrCardTotalCached ?? this.ocrCardTotalCached,
      ocrFastTotalCached: ocrFastTotalCached ?? this.ocrFastTotalCached,
      hasEndOfDayReportCached: hasEndOfDayReportCached ?? this.hasEndOfDayReportCached,
      manualCardTotalCached: manualCardTotalCached ?? this.manualCardTotalCached,
    );
  }
}

String attachmentKindLabel(AttachmentKind kind) {
  return switch (kind) {
    AttachmentKind.countSlip => 'Para sayım fişi',
    AttachmentKind.signedStatement => 'İmzalı tutanak',
    AttachmentKind.other => 'Diğer',
  };
}

List<AttachmentKind> missingRequiredAttachmentKinds(CashReconciliation item) {
  final hasDiff = item.difference.abs() > 0.01;
  if (!hasDiff) return const [];

  const requiredKinds = <AttachmentKind>[
    AttachmentKind.countSlip,
    AttachmentKind.signedStatement,
  ];

  final existingKinds = item.attachments.map((e) => e.kind).toSet();
  return [
    for (final k in requiredKinds)
      if (!existingKinds.contains(k)) k,
  ];
}

@immutable
class InventoryProduct {
  const InventoryProduct({
    required this.id,
    required this.name,
    required this.unit,
    this.code,
    this.isActive = true,
  });

  final String id;
  final String? code;
  final String name;
  final String unit;
  final bool isActive;

  InventoryProduct copyWith({
    String? id,
    String? code,
    String? name,
    String? unit,
    bool? isActive,
  }) {
    return InventoryProduct(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class InventoryWarehouse {
  const InventoryWarehouse({
    required this.id,
    required this.branchId,
    required this.code,
    required this.name,
    this.isActive = true,
  });

  final String id;
  final String branchId;
  final String code;
  final String name;
  final bool isActive;

  InventoryWarehouse copyWith({
    String? id,
    String? branchId,
    String? code,
    String? name,
    bool? isActive,
  }) {
    return InventoryWarehouse(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      code: code ?? this.code,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }
}

@immutable
class InventoryInvoice {
  const InventoryInvoice({
    required this.id,
    required this.branchId,
    required this.invoiceNo,
    required this.invoiceDate,
    this.vendorName,
    this.notes,
    this.total,
    this.paymentTypeId,
    this.incomeCenterId,
    this.discountRate,
    this.discountAmount,
    this.mealVoucherDiscount,
    this.paymentDate,
  });

  final String id;
  final String branchId;
  final String invoiceNo;
  final DateTime invoiceDate;
  final String? vendorName;
  final String? notes;
  final double? total;
  final String? paymentTypeId;
  final String? incomeCenterId;
  final double? discountRate;
  final double? discountAmount;
  final double? mealVoucherDiscount;
  final DateTime? paymentDate;
}

@immutable
class InventoryInvoiceLine {
  const InventoryInvoiceLine({
    required this.id,
    required this.invoiceId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.productId,
    this.productCode,
    this.productName,
    this.unit,
  });

  final String id;
  final String invoiceId;
  final String description;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final String? productId;
  final String? productCode;
  final String? productName;
  final String? unit;
}

@immutable
class InventoryOpenDocument {
  const InventoryOpenDocument({
    required this.id,
    required this.branchId,
    required this.docNo,
    required this.docDate,
    this.vendorName,
    this.total,
    this.linesCount,
    this.kind,
  });

  final String id;
  final String branchId;
  final String docNo;
  final DateTime docDate;
  final String? vendorName;
  final double? total;
  final int? linesCount;
  final String? kind;
}

@immutable
class InventoryStockLine {
  const InventoryStockLine({
    required this.productId,
    required this.quantity,
    required this.unitCost,
  });

  final String productId;
  final double quantity;
  final double unitCost;
}

@immutable
class InventoryStockTransaction {
  const InventoryStockTransaction({
    required this.id,
    required this.branchId,
    required this.warehouseId,
    required this.businessDate,
    required this.kind,
    required this.createdByUserId,
    required this.lines,
    this.referenceNo,
    this.notes,
  });

  final String id;
  final String branchId;
  final String warehouseId;
  final DateTime businessDate;
  final String kind;
  final String? referenceNo;
  final String? notes;
  final String createdByUserId;
  final List<InventoryStockLine> lines;
}

@immutable
class InventoryOnHand {
  const InventoryOnHand({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.quantity,
  });

  final String productId;
  final String productName;
  final String unit;
  final double quantity;
}

@immutable
class InventoryStockCount {
  const InventoryStockCount({
    required this.id,
    required this.branchId,
    required this.warehouseId,
    required this.businessDate,
    required this.status,
    required this.createdByUserId,
    required this.linesCount,
    required this.diffAbsTotal,
    this.branchName,
    this.warehouseName,
    this.approvedByUserId,
    this.rejectionReason,
  });

  final String id;
  final String branchId;
  final String? branchName;
  final String warehouseId;
  final String? warehouseName;
  final DateTime businessDate;
  final String status;
  final String createdByUserId;
  final String? approvedByUserId;
  final String? rejectionReason;
  final int linesCount;
  final double diffAbsTotal;
}

@immutable
class InventoryStockCountLine {
  const InventoryStockCountLine({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.countedQty,
    required this.onhandQty,
    required this.diffQty,
  });

  final String productId;
  final String productName;
  final String unit;
  final double countedQty;
  final double onhandQty;
  final double diffQty;
}

@immutable
class InventoryStockCountTotals {
  const InventoryStockCountTotals({
    required this.countedTotal,
    required this.onhandTotal,
    required this.diffTotal,
    required this.diffAbsTotal,
  });

  final double countedTotal;
  final double onhandTotal;
  final double diffTotal;
  final double diffAbsTotal;
}

@immutable
class InventoryStockCountDetail {
  const InventoryStockCountDetail({
    required this.header,
    required this.lines,
    required this.totals,
  });

  final InventoryStockCount header;
  final List<InventoryStockCountLine> lines;
  final InventoryStockCountTotals totals;
}

@immutable
class InventoryRecipe {
  const InventoryRecipe({
    required this.id,
    required this.productId,
    required this.productName,
    required this.name,
    required this.yieldQty,
    required this.yieldUnit,
    required this.isActive,
    required this.linesCount,
    this.code,
    this.description,
    this.gimOran,
  });

  final String id;
  final String productId;
  final String productName;
  final String? code;
  final String name;
  final String? description;
  final double yieldQty;
  final String yieldUnit;
  final double? gimOran;
  final bool isActive;
  final int linesCount;
}

@immutable
class InventoryRecipeLine {
  const InventoryRecipeLine({
    required this.ingredientProductId,
    required this.ingredientProductName,
    required this.unit,
    required this.quantity,
    required this.wasteRate,
    required this.avgUnitCost,
    required this.lineCost,
  });

  final String ingredientProductId;
  final String ingredientProductName;
  final String unit;
  final double quantity;
  final double wasteRate;
  final double avgUnitCost;
  final double lineCost;
}

@immutable
class InventoryRecipeTotals {
  const InventoryRecipeTotals({required this.recipeCost});

  final double recipeCost;
}

@immutable
class InventoryRecipeDetail {
  const InventoryRecipeDetail({
    required this.header,
    required this.lines,
    required this.totals,
  });

  final InventoryRecipe header;
  final List<InventoryRecipeLine> lines;
  final InventoryRecipeTotals totals;
}

@immutable
class CrmFirm {
  const CrmFirm({
    required this.id,
    required this.firmName,
    required this.isActive,
    required this.isCurrent,
    this.tradeName,
    this.integrationCode,
    this.firmType,
    this.customerGroup,
    this.email,
    this.priceNo,
    this.wholesalePriceNo,
    this.invoiceCompany,
    this.generalDiscount,
    this.paymentMethod,
    this.taxOffice,
    this.taxNo,
    this.isEInvoice = false,
    this.cargoCode,
    this.purchasePriceNo,
    this.paymentVkn,
    this.iban,
    this.notes,
    this.updatedAt,
  });

  final String id;
  final String firmName;
  final String? tradeName;
  final String? integrationCode;
  final String? firmType;
  final bool isCurrent;
  final String? customerGroup;
  final String? email;
  final String? priceNo;
  final String? wholesalePriceNo;
  final String? invoiceCompany;
  final double? generalDiscount;
  final String? paymentMethod;
  final String? taxOffice;
  final String? taxNo;
  final bool isEInvoice;
  final String? cargoCode;
  final String? purchasePriceNo;
  final String? paymentVkn;
  final String? iban;
  final String? notes;
  final bool isActive;
  final DateTime? updatedAt;
}
