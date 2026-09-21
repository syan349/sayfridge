import '../models/storage_space_page.dart';
import '../services/api_exception.dart';
import '../services/storage_space_api_service.dart';
import '../services/token_storage.dart';

class StorageSpaceRepository {
  const StorageSpaceRepository(
    this._storageSpaceApiService,
    this._tokenStorage,
  );

  final StorageSpaceApiService _storageSpaceApiService;
  final TokenStorage _tokenStorage;

  Future<StorageSpacePage> getStorageSpaces({
    String status = 'ACTIVE',
    int page = 1,
    int pageSize = 20,
  }) async {
    final accessToken = await _tokenStorage.readAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      throw const ApiException(
        statusCode: 401,
        code: 'AUTH_REQUIRED',
        message: 'Please sign in before loading storage spaces.',
      );
    }

    return _storageSpaceApiService.getStorageSpaces(
      accessToken: accessToken,
      status: status,
      page: page,
      pageSize: pageSize,
    );
  }
}