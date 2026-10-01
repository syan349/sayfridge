import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/profile_preferences.dart';
import '../repositories/auth_repository.dart';
import '../repositories/inventory_repository.dart';
import '../repositories/profile_preferences_repository.dart';
import '../repositories/storage_space_repository.dart';
import '../services/api_client.dart';
import '../services/auth_api_service.dart';
import '../services/inventory_api_service.dart';
import '../services/storage_space_api_service.dart';
import '../services/token_storage.dart';
import '../state/auth_controller.dart';
import '../state/expiry_summary_controller.dart';
import '../state/inventory_controller.dart';
import '../state/profile_controller.dart';
import '../state/storage_space_controller.dart';
import 'preview_inventory.dart';

/// All preview dependencies live in memory. No real token or profile is read,
/// overwritten, or deleted, and the transport cannot open a network connection.
class PreviewSession {
  PreviewSession() {
    if (!kDebugMode) {
      throw UnsupportedError('UI preview is available only in debug builds.');
    }
    _client = ApiClient(client: _OfflineTransport(_inventoryData));
    auth = AuthController(AuthRepository(AuthApiService(_client), _tokens));
    profile = ProfileController(auth, _MemoryPreferences());
    final inventoryRepository = InventoryRepository(
      InventoryApiService(_client),
      _tokens,
    );
    inventory = InventoryController(inventoryRepository);
    expiry = ExpirySummaryController(inventoryRepository);
    spaces = StorageSpaceController(
      StorageSpaceRepository(StorageSpaceApiService(_client), _tokens),
    );
  }

  final _tokens = _MemoryTokens();
  final _inventoryData = PreviewInventory();
  late final ApiClient _client;
  late final AuthController auth;
  late final ProfileController profile;
  late final InventoryController inventory;
  late final ExpirySummaryController expiry;
  late final StorageSpaceController spaces;

  VoiceUsage get voiceUsage {
    final now = DateTime.now();
    return VoiceUsage(
      used: 12,
      limit: 50,
      period: DateTime(now.year, now.month),
      resetsAt: DateTime(now.year, now.month + 1),
    );
  }

  Future<void> enter() async {
    await _tokens.saveAccessToken('ui-preview-not-a-real-token');
    await auth.initialize();
  }

  Future<void> setEmptyInventory(bool isEmpty) async {
    _inventoryData.isEmpty = isEmpty;
    final now = DateTime.now();
    await Future.wait([
      inventory.loadInventory(),
      expiry.loadSummary(asOf: DateTime(now.year, now.month, now.day)),
      spaces.loadStorageSpaces(),
    ]);
  }

  void dispose() {
    expiry.dispose();
    inventory.dispose();
    spaces.dispose();
    profile.dispose();
    auth.dispose();
    _client.close();
  }
}

class _MemoryTokens extends TokenStorage {
  String? _token;
  String? _refresh;

  @override
  Future<void> saveSession(String access, String? refresh) async {
    _token = access;
    _refresh = refresh;
  }

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<void> clearSession() async {
    _token = null;
    _refresh = null;
  }


  @override
  Future<String?> readAccessToken() async => _token;

  @override
  Future<void> saveAccessToken(String accessToken) async =>
      _token = accessToken;

  @override
  Future<void> deleteAccessToken() async => _token = null;
}

class _MemoryPreferences extends ProfilePreferencesRepository {
  ProfilePreferences _preferences = const ProfilePreferences(
    fullName: 'Demo User',
  );

  @override
  Future<ProfilePreferences> read(String userId) async => _preferences;

  @override
  Future<void> save(String userId, ProfilePreferences preferences) async {
    _preferences = preferences;
  }
}

class _OfflineTransport extends http.BaseClient {
  _OfflineTransport(this.inventory);

  final PreviewInventory inventory;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    // Fail closed: unsupported requests never fall back to a real HTTP client.
    if (request.method != 'GET') {
      return _response(501, {'detail': 'UI preview only. No data was sent.'});
    }
    if (path == '/api/v1/auth/me') {
      return _response(200, {
        'id': 'ui-preview-user',
        'email': 'preview@example.com',
        'role': 'USER',
        'status': 'ACTIVE',
        'created_at': '2026-09-01T00:00:00Z',
      });
    }
    final query = request.url.queryParameters;
    if (path == '/api/v1/inventory-items') {
      return _response(200, inventory.inventoryPage(query));
    }
    if (path == '/api/v1/storage-spaces') {
      return _response(200, inventory.storagePage(query));
    }
    if (path == '/api/v1/inventory-items/expiry-summary') {
      return _response(200, inventory.expirySummary(query));
    }
    if (path.startsWith('/api/v1/inventory-items/')) {
      final id = request.url.pathSegments.last;
      final matches = inventory.items.where((item) => item['id'] == id);
      return matches.isEmpty
          ? _response(404, {'detail': 'Preview item not found.'})
          : _response(200, matches.first);
    }
    return _response(501, {
      'detail': 'This feature has no offline preview data.',
    });
  }

  http.StreamedResponse _response(int status, Map<String, dynamic> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );
}
