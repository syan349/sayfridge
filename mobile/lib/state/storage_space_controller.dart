import 'package:flutter/foundation.dart';

import '../models/storage_space.dart';
import '../repositories/storage_space_repository.dart';
import '../services/api_exception.dart';

enum StorageSpaceLoadStatus {
  initial,
  loading,
  loaded,
  empty,
  error,
}

class StorageSpaceController extends ChangeNotifier {
  StorageSpaceController(this._repository);

  final StorageSpaceRepository _repository;

  StorageSpaceLoadStatus _status = StorageSpaceLoadStatus.initial;
  List<StorageSpace> _storageSpaces = [];
  String? _errorMessage;
  int _total = 0;
  int _page = 1;
  int _pageSize = 20;
  bool _hasNextPage = false;

  StorageSpaceLoadStatus get status => _status;

  List<StorageSpace> get storageSpaces => _storageSpaces;

  String? get errorMessage => _errorMessage;

  int get total => _total;

  int get page => _page;

  int get pageSize => _pageSize;

  bool get hasNextPage => _hasNextPage;

  Future<void> loadStorageSpaces({
    String spaceStatus = 'ACTIVE',
    int page = 1,
    int pageSize = 20,
  }) async {
    _status = StorageSpaceLoadStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.getStorageSpaces(
        status: spaceStatus,
        page: page,
        pageSize: pageSize,
      );

      _storageSpaces = result.items;
      _total = result.total;
      _page = result.page;
      _pageSize = result.pageSize;
      _hasNextPage = result.hasNextPage;
      _status = result.items.isEmpty
          ? StorageSpaceLoadStatus.empty
          : StorageSpaceLoadStatus.loaded;
    } catch (error) {
      _storageSpaces = [];
      _total = 0;
      _hasNextPage = false;
      _status = StorageSpaceLoadStatus.error;
      _errorMessage = _messageFor(error);
    }

    notifyListeners();
  }

  String _messageFor(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 0) {
        return 'Unable to connect to the server. Please try again.';
      }

      return error.message;
    }

    return 'Something went wrong. Please try again.';
  }
}