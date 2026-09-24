import '../models/storage_space_page.dart';
import 'api_client.dart';

class StorageSpaceApiService {
  const StorageSpaceApiService(this._apiClient);

  final ApiClient _apiClient;

  Future<StorageSpacePage> getStorageSpaces({
    required String accessToken,
    String status = 'ACTIVE',
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _apiClient.getJson(
      '/storage-spaces',
      accessToken: accessToken,
      queryParameters: {
        'status': status,
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
    );

    return StorageSpacePage.fromJson(response);
  }
}