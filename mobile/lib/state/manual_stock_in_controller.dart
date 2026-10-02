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
  int _sequence = 0;

  void reset() {
    ++_sequence;
    _clearOptions();
    _status = ManualStockInStatus.initial;
    notifyListeners();
  }

  void _clearOptions() {
    _storageSpaces = const [];
    _categories = const [];
    _definitions = const [];
    _selectedStorageSpaceId = null;
    _selectedCategoryId = null;
    _selectedDefinitionId = null;
    _errorMessage = null;
    _createdItem = null;
    _isLoadingDefinitions = false;
    _submissionUncertain = false;
  }

  @override
  void dispose() {
    ++_sequence;
    super.dispose();
  }

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
  bool _submissionUncertain = false;

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
  bool get submissionUncertain => _submissionUncertain;

  bool get hasRequiredOptions => _storageSpaces.isNotEmpty;

  Future<String> createCategory(String name) async {
    final sequence = _sequence;
    final category = await _catalogRepository.createCategory(name);
    if (sequence != _sequence) {
      throw const ApiException(
        statusCode: 401,
        message: 'Please sign in again.',
      );
    }
    if (!_categories.any((value) => value.id == category.id)) {
      _categories = [..._categories, category]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    notifyListeners();
    return category.id;
  }

  Future<void> reloadStorageSpaces() async {
    final sequence = _sequence;
    final spaces = <StorageSpace>[];
    for (var page = 1; ; page++) {
      final result = await _storageSpaceRepository.getStorageSpaces(
        page: page,
        pageSize: 100,
      );
      if (sequence != _sequence) return;
      spaces.addAll(result.items);
      if (spaces.length >= result.total || result.items.isEmpty) break;
    }
    _storageSpaces = spaces;
    if (!spaces.any((space) => space.id == _selectedStorageSpaceId)) {
      _selectedStorageSpaceId =
          spaces.where((space) => space.isDefault).firstOrNull?.id ??
          spaces.firstOrNull?.id;
    }
    notifyListeners();
  }

  Future<void> loadOptions() async {
    _submissionUncertain = false;
    final sequence = ++_sequence;
    _clearOptions();
    _status = ManualStockInStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final spaces = await _storageSpaceRepository.getStorageSpaces(
        pageSize: 100,
      );
      if (sequence != _sequence) return;
      final categories = <ItemCategory>[];
      for (var page = 1; ; page++) {
        final result = await _catalogRepository.getCategories(
          page: page,
          pageSize: 100,
        );
        if (sequence != _sequence) return;
        categories.addAll(result.items);
        if (categories.length >= result.total || result.items.isEmpty) break;
      }
      _storageSpaces = spaces.items;
      _categories = categories
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selectedStorageSpaceId =
          _storageSpaces.where((space) => space.isDefault).firstOrNull?.id ??
          _storageSpaces.firstOrNull?.id;
      _selectedCategoryId = _categories.firstOrNull?.id;

      if (_selectedCategoryId != null) {
        await _loadDefinitions(_selectedCategoryId!, sequence);
      }

      if (sequence != _sequence) return;
      _status = ManualStockInStatus.ready;
    } catch (error) {
      if (sequence != _sequence) return;
      _clearOptions();
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
    final sequence = ++_sequence;

    _selectedCategoryId = categoryId;
    _selectedDefinitionId = null;
    _definitions = const [];
    _isLoadingDefinitions = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _loadDefinitions(categoryId, sequence);
    } catch (error) {
      if (sequence != _sequence) return;
      _errorMessage = _messageFor(error);
    } finally {
      if (sequence == _sequence) {
        _isLoadingDefinitions = false;
        notifyListeners();
      }
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
    String? itemName,
  }) async {
    if (_status == ManualStockInStatus.submitting || _submissionUncertain) {
      return false;
    }
    final sequence = _sequence;
    final storageSpaceId = _selectedStorageSpaceId;
    var definitionId = _selectedDefinitionId;
    final name = itemName?.trim();
    if (storageSpaceId == null ||
        _selectedCategoryId == null ||
        (name == null && definitionId == null) ||
        name == '') {
      _errorMessage = 'Choose a storage space, category, and item.';
      notifyListeners();
      return false;
    }

    _status = ManualStockInStatus.submitting;
    _errorMessage = null;
    _createdItem = null;
    notifyListeners();

    try {
      if (name != null) {
        final existing = _definitions
            .where(
              (definition) =>
                  definition.name.toLowerCase() == name.toLowerCase(),
            )
            .firstOrNull;
        if (existing != null) {
          definitionId = existing.id;
        } else {
          final created = await _catalogRepository.createDefinition(
            name,
            _selectedCategoryId!,
          );
          if (sequence != _sequence) return false;
          _definitions = [..._definitions, created];
          definitionId = created.id;
        }
        _selectedDefinitionId = definitionId;
      }
      final createdItem = await _inventoryRepository.createInventoryItem(
        InventoryCreateRequest(
          storageSpaceId: storageSpaceId,
          itemDefinitionId: definitionId!,
          amount: amount.trim(),
          unit: unit,
          purchaseDate: purchaseDate,
          expiryDate: expiryDate,
          notes: notes,
        ),
      );
      if (sequence != _sequence) return false;
      _createdItem = createdItem;
      _status = ManualStockInStatus.success;
      notifyListeners();
      return true;
    } catch (error) {
      if (sequence != _sequence) return false;
      _submissionUncertain =
          error is! ApiException ||
          error.statusCode == 0 ||
          error.statusCode >= 500 ||
          error.code == 'INVALID_RESPONSE' ||
          error.isConflict;
      _status = ManualStockInStatus.ready;
      _errorMessage =
          '${_messageFor(error)}${_submissionUncertain ? '\nReturn to inventory and reload before trying again. The save result could not be verified.' : ''}';
      notifyListeners();
      return false;
    }
  }

  Future<void> _loadDefinitions(String categoryId, int sequence) async {
    final definitions = <ItemDefinition>[];
    for (var pageNumber = 1; ; pageNumber++) {
      final page = await _catalogRepository.getDefinitions(
        categoryId: categoryId,
        page: pageNumber,
        pageSize: 100,
      );
      if (sequence != _sequence) return;
      definitions.addAll(page.items);
      if (definitions.length >= page.total || page.items.isEmpty) break;
    }
    _definitions = definitions;
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
