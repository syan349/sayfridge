import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/item_icon.dart';

/// A device-local display preference. Inventory IDs are unique across accounts;
/// callers only request artwork for items returned by their authenticated API.
class ItemArtworkRepository {
  const ItemArtworkRepository([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  Future<String?> read(String itemId) async {
    final asset = await _storage.read(key: 'item_artwork_$itemId');
    return ItemIcon.isValidAsset(asset) ? asset : null;
  }

  Future<void> save(String itemId, String asset) {
    if (!ItemIcon.isValidAsset(asset)) throw ArgumentError('Unknown item icon');
    return _storage.write(key: 'item_artwork_$itemId', value: asset);
  }
}
