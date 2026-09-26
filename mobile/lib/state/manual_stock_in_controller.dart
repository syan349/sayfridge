import 'package:flutter/foundation.dart';

import '../models/inventory_create_request.dart';
import '../models/inventory_item.dart';
import '../models/item_category.dart';
import '../models/item_definition.dart';
import '../models/storage_space.dart';
import '../repositories/catalog_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/storage_space_repository.dart';
import '../services/api_exception.dart';

enum ManualStockInStatus { initial, loading, ready, submitting, success, error }

class ManualStockInController extends ChangeNotifier {
  ManualStockInController(
    this._catalogRepository,
    this._inventoryRepository,
    this._storageSpaceRepository,
  );

  final CatalogRepository _catalogRepository;
  final InventoryRepository _inventoryRepository;
  final StorageSpaceRepository _storageSpaceRepository;

  ManualStockInStatus _status = ManualStockInStatus.initial;
  List<StorageSpace> _storageSpaces = const [];
  List<ItemCategory> _categories = const [];
  List<ItemDefinition> _definitions = const [];
  String? _selectedStorageSpaceId;
  String? _selectedCategoryId;
  String? _selectedDefinitionId;
  String? _errorMessage;
  InventoryItem? _createdItem;
  bool _isLoadingDefinitions = false;

  ManualStockInStatus get status => _status;
  List<StorageSpace> get storageSpaces => _storageSpaces;
  List<ItemCategory> get categories => _categories;
  List<ItemDefinition> get definitions => _definitions;
  String? get selectedStorageSpaceId => _selectedStorageSpaceId;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedDefinitionId => _selectedDefinitionId;
  String? get errorMessage => _errorMessage;
  InventoryItem? get createdItem => _createdItem;
  bool get isLoadingDefinitions => _isLoadingDefinitions;

  bool get hasRequiredOptions =>
      _storageSpaces.isNotEmpty &&
      _categories.isNotEmpty &&
      _definitions.isNotEmpty;

  Future<void> loadOptions() async {
    _status = ManualStockInStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final spacesFuture = _storageSpaceRepository.getStorageSpaces(
        pageSize: 100,
      );
      final categoriesFuture = _catalogRepository.getCategories(pageSize: 100);
      final spaces = await spacesFuture;
      final categories = await categoriesFuture;
      _storageSpaces = spaces.items;
      _categories = categories.items;
      _selectedStorageSpaceId = _storageSpaces.firstOrNull?.id;
      _selectedCategoryId = _categories.firstOrNull?.id;

      if (_selectedCategoryId != null) {
        await _loadDefinitions(_selectedCategoryId!);
      }

      _status = ManualStockInStatus.ready;
    } catch (error) {
      _status = ManualStockInStatus.error;
      _errorMessage = _messageFor(error);
    }

    notifyListeners();
  }

  void selectStorageSpace(String? storageSpaceId) {
    _selectedStorageSpaceId = storageSpaceId;
    notifyListeners();
  }

  Future<void> selectCategory(String? categoryId) async {
    if (categoryId == null || categoryId == _selectedCategoryId) return;

    _selectedCategoryId = categoryId;
    _selectedDefinitionId = null;
    _definitions = const [];
    _isLoadingDefinitions = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _loadDefinitions(categoryId);
    } catch (error) {
      _errorMessage = _messageFor(error);
    } finally {
      _isLoadingDefinitions = false;
      notifyListeners();
    }
  }

  void selectDefinition(String? definitionId) {
    _selectedDefinitionId = definitionId;
    notifyListeners();
  }

  Future<bool> submit({
    required String amount,
    required String unit,
    DateTime? purchaseDate,
    DateTime? expiryDate,
    String? notes,
  }) async {
    final storageSpaceId = _selectedStorageSpaceId;
    final definitionId = _selectedDefinitionId;
    if (storageSpaceId == null || definitionId == null) {
      _errorMessage = 'Choose a storage space, category, and item.';
      notifyListeners();
      return false;
    }

    _status = ManualStockInStatus.submitting;
    _errorMessage = null;
    _createdItem = null;
    notifyListeners();

    try {
      _createdItem = await _inventoryRepository.createInventoryItem(
        InventoryCreateRequest(
          storageSpaceId: storageSpaceId,
          itemDefinitionId: definitionId,
          amount: amount.trim(),
          unit: unit,
          purchaseDate: purchaseDate,
          expiryDate: expiryDate,
          notes: notes,
        ),
      );
      _status = ManualStockInStatus.success;
      notifyListeners();
      return true;
    } catch (error) {
      _status = ManualStockInStatus.ready;
      _errorMessage = _messageFor(error);
      notifyListeners();
      return false;
    }
  }

  Future<void> _loadDefinitions(String categoryId) async {
    final page = await _catalogRepository.getDefinitions(
      categoryId: categoryId,
      pageSize: 100,
    );
    _definitions = page.items;
    _selectedDefinitionId = _definitions.firstOrNull?.id;
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
