import 'package:flutter/foundation.dart';

import '../models/inventory_item.dart';
import '../repositories/inventory_repository.dart';
import '../services/api_exception.dart';

enum InventoryDetailStatus { initial, loading, loaded, error }

class InventoryDetailController extends ChangeNotifier {
  InventoryDetailController(this._repository);

  final InventoryRepository _repository;

  InventoryDetailStatus _status = InventoryDetailStatus.initial;
  InventoryItem? _item;
  String? _errorMessage;

  InventoryDetailStatus get status => _status;
  InventoryItem? get item => _item;
  String? get errorMessage => _errorMessage;

  Future<void> loadItem(String itemId) async {
    _status = InventoryDetailStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _item = await _repository.getInventoryItem(itemId);
      _status = InventoryDetailStatus.loaded;
    } catch (error) {
      _item = null;
      _status = InventoryDetailStatus.error;
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
