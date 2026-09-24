import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sayfridge/models/storage_space.dart';
import 'package:sayfridge/models/storage_space_page.dart';
import 'package:sayfridge/repositories/storage_space_repository.dart';
import 'package:sayfridge/services/api_exception.dart';
import 'package:sayfridge/state/storage_space_controller.dart';

void main() {
  late _FakeStorageSpaceRepository repository;
  late StorageSpaceController controller;

  setUp(() {
    repository = _FakeStorageSpaceRepository();
    controller = StorageSpaceController(repository);
  });

  tearDown(() {
    controller.dispose();
  });

  group('StorageSpaceController', () {
    test('starts in the initial state', () {
      expect(controller.status, StorageSpaceLoadStatus.initial);
      expect(controller.storageSpaces, isEmpty);
      expect(controller.errorMessage, isNull);
      expect(controller.total, 0);
      expect(controller.hasNextPage, isFalse);
    });

    test('loads and exposes storage spaces', () async {
      final completer = Completer<StorageSpacePage>();
      repository.completer = completer;

      final loadFuture = controller.loadStorageSpaces(
        spaceStatus: 'ALL',
        page: 2,
        pageSize: 10,
      );

      expect(controller.status, StorageSpaceLoadStatus.loading);

      completer.complete(
        StorageSpacePage(
          items: [
            StorageSpace(
              id: 'space-1',
              name: 'Kitchen fridge',
              type: 'FRIDGE',
              status: 'ACTIVE',
              createdAt: DateTime.utc(2026, 9, 21, 1),
              updatedAt: DateTime.utc(2026, 9, 21, 2),
            ),
          ],
          total: 15,
          page: 2,
          pageSize: 10,
        ),
      );

      await loadFuture;

      expect(controller.status, StorageSpaceLoadStatus.loaded);
      expect(controller.storageSpaces, hasLength(1));
      expect(controller.storageSpaces.first.name, 'Kitchen fridge');
      expect(controller.total, 15);
      expect(controller.page, 2);
      expect(controller.pageSize, 10);
      expect(controller.hasNextPage, isFalse);

      expect(repository.receivedStatus, 'ALL');
      expect(repository.receivedPage, 2);
      expect(repository.receivedPageSize, 10);
    });

    test('uses the empty state when no storage spaces exist', () async {
      repository.result = const StorageSpacePage(
        items: [],
        total: 0,
        page: 1,
        pageSize: 20,
      );

      await controller.loadStorageSpaces();

      expect(controller.status, StorageSpaceLoadStatus.empty);
      expect(controller.storageSpaces, isEmpty);
      expect(controller.total, 0);
      expect(controller.errorMessage, isNull);
    });

    test('exposes a network error', () async {
      repository.error = const ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'Network unavailable',
      );

      await controller.loadStorageSpaces();

      expect(controller.status, StorageSpaceLoadStatus.error);
      expect(
        controller.errorMessage,
        'Unable to connect to the server. Please try again.',
      );
      expect(controller.storageSpaces, isEmpty);
    });
  });
}

class _FakeStorageSpaceRepository implements StorageSpaceRepository {
  StorageSpacePage? result;
  Object? error;
  Completer<StorageSpacePage>? completer;

  String? receivedStatus;
  int? receivedPage;
  int? receivedPageSize;

  @override
  Future<StorageSpacePage> getStorageSpaces({
    String status = 'ACTIVE',
    int page = 1,
    int pageSize = 20,
  }) {
    receivedStatus = status;
    receivedPage = page;
    receivedPageSize = pageSize;

    if (error != null) {
      return Future<StorageSpacePage>.error(error!);
    }

    if (completer != null) {
      return completer!.future;
    }

    return Future<StorageSpacePage>.value(result);
  }
}