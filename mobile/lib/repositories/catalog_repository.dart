import '../models/item_category_page.dart';
import '../models/item_definition_page.dart';
import '../models/item_definition.dart';
import '../models/item_category.dart';
import '../services/api_exception.dart';
import '../services/catalog_api_service.dart';
import '../services/token_storage.dart';

class CatalogRepository {
  const CatalogRepository(this._catalogApiService, this._tokenStorage);

  final CatalogApiService _catalogApiService;
  final TokenStorage _tokenStorage;

  Future<ItemCategory> createCategory(String name) async => _catalogApiService
      .createCategory(accessToken: await _requireAccessToken(), name: name);

  Future<ItemDefinition> createDefinition(
    String name,
    String categoryId,
  ) async => _catalogApiService.createDefinition(
    accessToken: await _requireAccessToken(),
    name: name,
    categoryId: categoryId,
  );

  Future<ItemCategoryPage> getCategories({
    int page = 1,
    int pageSize = 100,
  }) async {
    return _catalogApiService.getCategories(
      accessToken: await _requireAccessToken(),
      page: page,
      pageSize: pageSize,
    );
  }

  Future<ItemDefinitionPage> getDefinitions({
    String? categoryId,
    String query = '',
    int page = 1,
    int pageSize = 100,
  }) async {
    return _catalogApiService.getDefinitions(
      accessToken: await _requireAccessToken(),
      categoryId: categoryId,
      query: query,
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
        message: 'Please sign in before loading the item catalogue.',
      );
    }
    return accessToken;
  }
}
