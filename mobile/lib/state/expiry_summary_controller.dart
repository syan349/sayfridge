import 'package:flutter/foundation.dart';

import '../models/expiry_summary.dart';
import '../repositories/inventory_repository.dart';
import '../services/api_exception.dart';

enum ExpirySummaryLoadStatus { initial, loading, loaded, empty, error }

class ExpirySummaryController extends ChangeNotifier {
  ExpirySummaryController(this._repository);

  final InventoryRepository _repository;

  ExpirySummaryLoadStatus _status = ExpirySummaryLoadStatus.initial;
  ExpiryCounts _counts = const ExpiryCounts(overdue: 0, today: 0, upcoming: 0);
  List<ExpirySummaryItem> _items = [];
  String? _errorMessage;
  int _total = 0;
  int _page = 1;
  int _pageSize = 20;
  bool _hasNextPage = false;
  DateTime? _asOf;
  int _daysBefore = 3;
  String? _storageSpaceId;
  String? _categoryId;
  String? _bucket;

  ExpirySummaryLoadStatus get status => _status;
  ExpiryCounts get counts => _counts;
  List<ExpirySummaryItem> get items => _items;
  String? get errorMessage => _errorMessage;
  int get total => _total;
  int get page => _page;
  int get pageSize => _pageSize;
  bool get hasNextPage => _hasNextPage;
  String? get bucket => _bucket;

  Future<void> selectBucket(String? bucket) {
    final asOf = _asOf;
    if (asOf == null) return Future<void>.value();

    return loadSummary(
      asOf: asOf,
      daysBefore: _daysBefore,
      storageSpaceId: _storageSpaceId,
      categoryId: _categoryId,
      bucket: bucket,
      pageSize: _pageSize,
    );
  }

  Future<void> loadPage(int page) {
    final asOf = _asOf;
    if (asOf == null) return Future<void>.value();

    return loadSummary(
      asOf: asOf,
      daysBefore: _daysBefore,
      storageSpaceId: _storageSpaceId,
      categoryId: _categoryId,
      bucket: _bucket,
      page: page,
      pageSize: _pageSize,
    );
  }

  Future<void> loadSummary({
    required DateTime asOf,
    int daysBefore = 3,
    String? storageSpaceId,
    String? categoryId,
    String? bucket,
    int page = 1,
    int pageSize = 20,
  }) async {
    _status = ExpirySummaryLoadStatus.loading;
    _errorMessage = null;
    _asOf = asOf;
    _daysBefore = daysBefore;
    _storageSpaceId = storageSpaceId;
    _categoryId = categoryId;
    _bucket = bucket;
    notifyListeners();

    try {
      final result = await _repository.getExpirySummary(
        asOf: asOf,
        daysBefore: daysBefore,
        storageSpaceId: storageSpaceId,
        categoryId: categoryId,
        bucket: bucket,
        page: page,
        pageSize: pageSize,
      );

      _counts = result.counts;
      _items = result.items;
      _total = result.total;
      _page = result.page;
      _pageSize = result.pageSize;
      _hasNextPage = result.hasNextPage;
      _status = result.items.isEmpty
          ? ExpirySummaryLoadStatus.empty
          : ExpirySummaryLoadStatus.loaded;
    } catch (error) {
      _counts = const ExpiryCounts(overdue: 0, today: 0, upcoming: 0);
      _items = [];
      _total = 0;
      _hasNextPage = false;
      _status = ExpirySummaryLoadStatus.error;
      _errorMessage = _messageFor(error);
    }

    notifyListeners();
  }

  Future<void> reload() {
    final asOf = _asOf;
    if (asOf == null) return Future<void>.value();

    return loadSummary(
      asOf: asOf,
      daysBefore: _daysBefore,
      storageSpaceId: _storageSpaceId,
      categoryId: _categoryId,
      bucket: _bucket,
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
