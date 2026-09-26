class InventoryCreateRequest {
  const InventoryCreateRequest({
    required this.storageSpaceId,
    required this.itemDefinitionId,
    required this.amount,
    required this.unit,
    this.purchaseDate,
    this.expiryDate,
    this.notes,
  });

  final String storageSpaceId;
  final String itemDefinitionId;
  final String amount;
  final String unit;
  final DateTime? purchaseDate;
  final DateTime? expiryDate;
  final String? notes;

  Map<String, dynamic> toJson() {
    return {
      'storage_space_id': storageSpaceId,
      'item_definition_id': itemDefinitionId,
      'amount': amount,
      'unit': unit.trim(),
      if (purchaseDate != null) 'purchase_date': _date(purchaseDate!),
      if (expiryDate != null) 'expiry_date': _date(expiryDate!),
      if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
    };
  }

  String _date(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
