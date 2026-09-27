import '../models/expiry_summary.dart';
import '../models/inventory_item.dart';
import '../models/inventory_page.dart';
import '../models/inventory_create_request.dart';
import 'api_client.dart';

class InventoryApiService {
  const InventoryApiService(this._apiClient);

  final ApiClient _apiClient;

  Future<InventoryItem> createInventoryItem({
    required String accessToken,
    required InventoryCreateRequest request,
  }) async {
    final response = await _apiClient.postJson(
      '/inventory-items',
      accessToken: accessToken,
      body: request.toJson(),
    );
    return InventoryItem.fromJson(response);
  }

  Future<ExpirySummary> getExpirySummary({
    required String accessToken,
    required DateTime asOf,
    int daysBefore = 3,
    String? storageSpaceId,
    String? categoryId,
    String? bucket,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _apiClient.getJson(
      '/inventory-items/expiry-summary',
      accessToken: accessToken,
      queryParameters: {
        'as_of': _date(asOf),
        'days_before': daysBefore.toString(),
        'storage_space_id': ?storageSpaceId,
        'category_id': ?categoryId,
        'bucket': ?bucket,
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
    );

    return ExpirySummary.fromJson(response);
  }

  Future<InventoryItem> getInventoryItem({
    required String accessToken,
    required String itemId,
  }) async {
    final response = await _apiClient.getJson(
      '/inventory-items/$itemId',
      accessToken: accessToken,
    );

    return InventoryItem.fromJson(response);
  }

  Future<InventoryPage> getInventory({
    required String accessToken,
    String status = 'IN_STOCK',
    String query = '',
    String? storageSpaceId,
    String? categoryId,
    DateTime? purchaseFrom,
    DateTime? purchaseTo,
    DateTime? expiryFrom,
    DateTime? expiryTo,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _apiClient.getJson(
      '/inventory-items',
      accessToken: accessToken,
      queryParameters: {
        'status': status,
        'q': query,
        'storage_space_id': ?storageSpaceId,
        'category_id': ?categoryId,
        if (purchaseFrom != null) 'purchase_from': _date(purchaseFrom),
        if (purchaseTo != null) 'purchase_to': _date(purchaseTo),
        if (expiryFrom != null) 'expiry_from': _date(expiryFrom),
        if (expiryTo != null) 'expiry_to': _date(expiryTo),
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
    );

    return InventoryPage.fromJson(response);
  }

  String _date(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
