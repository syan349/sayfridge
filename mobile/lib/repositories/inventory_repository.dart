import '../models/expiry_summary.dart';
import '../models/inventory_item.dart';
import '../models/inventory_page.dart';
import '../services/api_exception.dart';
import '../services/inventory_api_service.dart';
import '../services/token_storage.dart';

class InventoryRepository {
  const InventoryRepository(this._inventoryApiService, this._tokenStorage);

  final InventoryApiService _inventoryApiService;
  final TokenStorage _tokenStorage;

  Future<ExpirySummary> getExpirySummary({
    required DateTime asOf,
    int daysBefore = 3,
    String? storageSpaceId,
    String? categoryId,
    String? bucket,
    int page = 1,
    int pageSize = 20,
  }) async {
    final accessToken = await _requireAccessToken();
    return _inventoryApiService.getExpirySummary(
      accessToken: accessToken,
      asOf: asOf,
      daysBefore: daysBefore,
      storageSpaceId: storageSpaceId,
      categoryId: categoryId,
      bucket: bucket,
      page: page,
      pageSize: pageSize,
    );
  }

  Future<InventoryItem> getInventoryItem(String itemId) async {
    final accessToken = await _requireAccessToken();
    return _inventoryApiService.getInventoryItem(
      accessToken: accessToken,
      itemId: itemId,
    );
  }

  Future<InventoryPage> getInventory({
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
    final accessToken = await _requireAccessToken();

    return _inventoryApiService.getInventory(
      accessToken: accessToken,
      status: status,
      query: query,
      storageSpaceId: storageSpaceId,
      categoryId: categoryId,
      purchaseFrom: purchaseFrom,
      purchaseTo: purchaseTo,
      expiryFrom: expiryFrom,
      expiryTo: expiryTo,
      page: page,
      pageSize: pageSize,
    );
  }

  Future<String> _requireAccessToken() async {
    final accessToken = await _tokenStorage.readAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(
        statusCode: 401,
        code: 'AUTH_REQUIRED',
        message: 'Please sign in before loading inventory.',
      );
    }

    return accessToken;
  }
}
