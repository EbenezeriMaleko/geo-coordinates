import 'dart:io';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path_provider/path_provider.dart';

class MapTileCache {
  MapTileCache._();
  static CacheStore? _store;

  static CacheStore get store {
    assert(_store != null, 'Call MapTileCache.init() before accessing store');
    return _store!;
  }

  static Future<void> init() async {
    if (_store != null) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}${Platform.pathSeparator}map_tile_cache';
    _store = FileCacheStore(path);
  }

  static Future<void> clear() async => _store?.clean();
}
