import '../models/item_category_page.dart';
import '../models/item_definition_page.dart';
import '../models/item_definition.dart';
import 'api_client.dart';

class CatalogApiService {
  const CatalogApiService(this._apiClient);

  final ApiClient _apiClient;

  Future<ItemDefinition> createDefinition({
    required String accessToken,
    required String name,
    required String categoryId,
  }) async => ItemDefinition.fromJson(
    await _apiClient.postJson(
      '/item-definitions',
      accessToken: accessToken,
      body: {'name': name.trim(), 'category_id': categoryId},
    ),
  );

  Future<ItemCategoryPage> getCategories({
    required String accessToken,
    String status = 'ACTIVE',
    int page = 1,
    int pageSize = 100,
  }) async {
    final response = await _apiClient.getJson(
      '/item-categories',
      accessToken: accessToken,
      queryParameters: {
        'status': status,
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
    );
    return ItemCategoryPage.fromJson(response);
  }

  Future<ItemDefinitionPage> getDefinitions({
    required String accessToken,
    String status = 'ACTIVE',
    String scope = 'ALL',
    String? categoryId,
    String query = '',
    int page = 1,
    int pageSize = 100,
  }) async {
    final response = await _apiClient.getJson(
      '/item-definitions',
      accessToken: accessToken,
      queryParameters: {
        'status': status,
        'scope': scope,
        'category_id': ?categoryId,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
    );
    return ItemDefinitionPage.fromJson(response);
  }
}
