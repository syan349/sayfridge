import 'package:flutter/foundation.dart';

import '../models/inventory_item.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/workspace_repository.dart';
import '../services/api_exception.dart';
import 'inventory_detail_controller.dart';

enum InventoryLoadStatus { initial, loading, loaded, empty, error }

class InventoryController extends ChangeNotifier {
  InventoryController(this._repository, {this.workspace});
  final WorkspaceRepository? workspace;

  final InventoryRepository _repository;

  InventoryLoadStatus _status = InventoryLoadStatus.initial;
  List<InventoryItem> _items = [];
  String? _errorMessage;
  int _total = 0;
  int _page = 1;
  int _pageSize = 20;
  bool _hasNextPage = false;
  String _inventoryStatus = 'IN_STOCK';
  String _query = '';
  String? _storageSpaceId;
  String? _categoryId;
  DateTime? _purchaseFrom;
  DateTime? _purchaseTo;
  DateTime? _expiryFrom;
  DateTime? _expiryTo;
  int _requestSequence = 0;

  InventoryLoadStatus get status => _status;
  List<InventoryItem> get items => _items;
  String? get errorMessage => _errorMessage;
  int get total => _total;
  int get page => _page;
  int get pageSize => _pageSize;
  bool get hasNextPage => _hasNextPage;
  String get inventoryStatus => _inventoryStatus;
  String get query => _query;
  String? get storageSpaceId => _storageSpaceId;
  bool get hasItemFilters =>
      _query.isNotEmpty ||
      _categoryId != null ||
      _purchaseFrom != null ||
      _purchaseTo != null ||
      _expiryFrom != null ||
      _expiryTo != null;

  InventoryDetailController createDetailController() {
    return InventoryDetailController(_repository, workspace: workspace);
  }

  void reset() {
    ++_requestSequence;
    _items = [];
    _total = 0;
    _page = 1;
    _hasNextPage = false;
    _query = '';
    _inventoryStatus = 'IN_STOCK';
    _storageSpaceId = _categoryId = null;
    _purchaseFrom = _purchaseTo = _expiryFrom = _expiryTo = null;
    _errorMessage = null;
    _status = InventoryLoadStatus.initial;
    notifyListeners();
  }

  @override
  void dispose() {
    ++_requestSequence;
    super.dispose();
  }

  Future<void> loadInventory({
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
    final requestSequence = ++_requestSequence;
    _status = InventoryLoadStatus.loading;
    _errorMessage = null;
    _inventoryStatus = status;
    _query = query;
    _storageSpaceId = storageSpaceId;
    _categoryId = categoryId;
    _purchaseFrom = purchaseFrom;
    _purchaseTo = purchaseTo;
    _expiryFrom = expiryFrom;
    _expiryTo = expiryTo;
    notifyListeners();

    try {
      final result = await _repository.getInventory(
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

      if (requestSequence != _requestSequence) return;

      _items = result.items;
      _total = result.total;
      _page = result.page;
      _pageSize = result.pageSize;
      _hasNextPage = result.hasNextPage;
      _status = result.items.isEmpty
          ? InventoryLoadStatus.empty
          : InventoryLoadStatus.loaded;
    } catch (error) {
      if (requestSequence != _requestSequence) return;
      _items = [];
      _total = 0;
      _hasNextPage = false;
      _status = InventoryLoadStatus.error;
      _errorMessage = _messageFor(error);
    }

    notifyListeners();
  }

  Future<void> reload() {
    return loadInventory(
      status: _inventoryStatus,
      query: _query,
      storageSpaceId: _storageSpaceId,
      categoryId: _categoryId,
      purchaseFrom: _purchaseFrom,
      purchaseTo: _purchaseTo,
      expiryFrom: _expiryFrom,
      expiryTo: _expiryTo,
      page: _page,
      pageSize: _pageSize,
    );
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
