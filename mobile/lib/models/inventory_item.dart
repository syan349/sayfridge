class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.storageSpaceId,
    required this.storageSpaceName,
    required this.itemDefinitionId,
    required this.itemDefinitionName,
    required this.categoryId,
    required this.categoryName,
    required this.purchaseDate,
    required this.expiryDate,
    required this.notes,
    required this.status,
    required this.initialAmount,
    required this.initialUnit,
    required this.confirmedCurrentAmount,
    required this.confirmedCurrentUnit,
    required this.confirmedAt,
    required this.estimatedCurrentAmount,
    required this.estimatedCurrentUnit,
    required this.estimatedAt,
    required this.displayAmount,
    required this.displayUnit,
    required this.isEstimated,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String storageSpaceId;
  final String storageSpaceName;
  final String itemDefinitionId;
  final String itemDefinitionName;
  final String categoryId;
  final String categoryName;
  final DateTime? purchaseDate;
  final DateTime? expiryDate;
  final String? notes;
  final String status;
  final double initialAmount;
  final String initialUnit;
  final double confirmedCurrentAmount;
  final String confirmedCurrentUnit;
  final DateTime confirmedAt;
  final double? estimatedCurrentAmount;
  final String? estimatedCurrentUnit;
  final DateTime? estimatedAt;
  final double displayAmount;
  final String displayUnit;
  final bool isEstimated;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isInStock => status == 'IN_STOCK';

  String get displayQuantity => '${_formatAmount(displayAmount)} $displayUnit';

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] as String,
      storageSpaceId: json['storage_space_id'] as String,
      storageSpaceName: json['storage_space_name'] as String,
      itemDefinitionId: json['item_definition_id'] as String,
      itemDefinitionName: json['item_definition_name'] as String,
      categoryId: json['category_id'] as String,
      categoryName: json['category_name'] as String,
      purchaseDate: _optionalDate(json['purchase_date']),
      expiryDate: _optionalDate(json['expiry_date']),
      notes: json['notes'] as String?,
      status: json['status'] as String,
      initialAmount: _amount(json['initial_amount']),
      initialUnit: json['initial_unit'] as String,
      confirmedCurrentAmount: _amount(json['confirmed_current_amount']),
      confirmedCurrentUnit: json['confirmed_current_unit'] as String,
      confirmedAt: DateTime.parse(json['confirmed_at'] as String),
      estimatedCurrentAmount: _optionalAmount(json['estimated_current_amount']),
      estimatedCurrentUnit: json['estimated_current_unit'] as String?,
      estimatedAt: _optionalDate(json['estimated_at']),
      displayAmount: _amount(json['display_amount']),
      displayUnit: json['display_unit'] as String,
      isEstimated: json['is_estimated'] as bool,
      version: json['version'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  static double _amount(Object? value) {
    if (value is num) return value.toDouble();
    return double.parse(value as String);
  }

  static double? _optionalAmount(Object? value) {
    return value == null ? null : _amount(value);
  }

  static DateTime? _optionalDate(Object? value) {
    return value == null ? null : DateTime.parse(value as String);
  }

  static String _formatAmount(double value) {
    return value == value.truncateToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }
}
