import 'package:flutter/foundation.dart';

import '../models/inventory_item.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/workspace_repository.dart';
import '../services/api_exception.dart';

enum InventoryDetailStatus { initial, loading, loaded, error }

class InventoryDetailController extends ChangeNotifier {
  InventoryDetailController(this._repository, {this.workspace});
  final WorkspaceRepository? workspace;
  int _sequence = 0;

  @override
  void dispose() {
    ++_sequence;
    super.dispose();
  }

  final InventoryRepository _repository;

  InventoryDetailStatus _status = InventoryDetailStatus.initial;
  InventoryItem? _item;
  String? _errorMessage;

  InventoryDetailStatus get status => _status;
  InventoryItem? get item => _item;
  String? get errorMessage => _errorMessage;

  Future<void> loadItem(String itemId) async {
    final sequence = ++_sequence;
    _status = InventoryDetailStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final item = await _repository.getInventoryItem(itemId);
      if (sequence != _sequence) return;
      _item = item;
      _status = InventoryDetailStatus.loaded;
    } catch (error) {
      if (sequence != _sequence) return;
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
