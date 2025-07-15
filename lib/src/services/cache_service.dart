import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

import '../core/interfaces/cache_service_interface.dart';

/// Cache Service implementation using SharedPreferences and in-memory cache
/// Follows Single Responsibility Principle - handles only caching operations
class CacheService implements CacheServiceInterface {
  static const String _cachePrefix = 'fldb_cache_';
  static const String _statsKey = 'fldb_cache_stats';

  SharedPreferences? _prefs;
  final Logger _logger;
  final CacheConfig _config;

  // In-memory cache for performance
  final Map<String, CacheEntry> _memoryCache = {};

  // Statistics tracking
  int _hitCount = 0;
  int _missCount = 0;
  int _evictionCount = 0;

  bool _isInitialized = false;
  Timer? _cleanupTimer;

  CacheService({Logger? logger, CacheConfig? config})
    : _logger = logger ?? Logger(),
      _config = config ?? const CacheConfig();

  @override
  Future<bool> initialize() async {
    try {
      if (_isInitialized) {
        _logger.i('Cache Service already initialized');
        return true;
      }

      _prefs = await SharedPreferences.getInstance();

      // Load existing cache from persistent storage
      await _loadCacheFromStorage();

      // Start cleanup timer
      _startCleanupTimer();

      _isInitialized = true;
      _logger.i('Cache Service initialized successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.e(
        'Failed to initialize Cache Service',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> set<T>(String key, T value, {Duration? ttl}) async {
    try {
      _ensureInitialized();

      final effectiveTtl = ttl ?? _config.defaultTtl;
      final expiresAt = DateTime.now().add(effectiveTtl);

      final entry = CacheEntry<T>(
        key: key,
        value: value,
        createdAt: DateTime.now(),
        expiresAt: expiresAt,
        accessCount: 0,
        lastAccessedAt: DateTime.now(),
      );

      // Store in memory cache
      _memoryCache[key] = entry;

      // Store in persistent storage
      await _saveToStorage(key, entry);

      // Check if we need to evict entries
      await _evictIfNeeded();

      if (_config.enableLogging) {
        _logger.d('Cache set: $key');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error setting cache key: $key',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<T?> get<T>(String key) async {
    try {
      _ensureInitialized();

      // Check memory cache first
      var entry = _memoryCache[key] as CacheEntry<T>?;

      // If not in memory, try persistent storage
      if (entry == null) {
        entry = await _loadFromStorage<T>(key);
        if (entry != null) {
          _memoryCache[key] = entry;
        }
      }

      if (entry == null) {
        _missCount++;
        return null;
      }

      // Check if expired
      if (entry.isExpired) {
        await remove(key);
        _missCount++;
        return null;
      }

      // Update access statistics
      final updatedEntry = entry.copyWith(
        accessCount: entry.accessCount + 1,
        lastAccessedAt: DateTime.now(),
      );
      _memoryCache[key] = updatedEntry;

      _hitCount++;

      if (_config.enableLogging) {
        _logger.d('Cache hit: $key');
      }

      return entry.value;
    } catch (e, stackTrace) {
      _logger.e(
        'Error getting cache key: $key',
        error: e,
        stackTrace: stackTrace,
      );
      _missCount++;
      return null;
    }
  }

  @override
  Future<bool> containsKey(String key) async {
    try {
      _ensureInitialized();

      // Check memory cache first
      if (_memoryCache.containsKey(key)) {
        final entry = _memoryCache[key]!;
        if (!entry.isExpired) {
          return true;
        } else {
          await remove(key);
          return false;
        }
      }

      // Check persistent storage
      final entry = await _loadFromStorage(key);
      if (entry != null && !entry.isExpired) {
        _memoryCache[key] = entry;
        return true;
      }

      return false;
    } catch (e, stackTrace) {
      _logger.e(
        'Error checking cache key: $key',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      _ensureInitialized();

      // Remove from memory cache
      _memoryCache.remove(key);

      // Remove from persistent storage
      await _prefs!.remove('$_cachePrefix$key');

      if (_config.enableLogging) {
        _logger.d('Cache removed: $key');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error removing cache key: $key',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      _ensureInitialized();

      // Clear memory cache
      _memoryCache.clear();

      // Clear persistent storage
      final keys = _prefs!.getKeys().where(
        (key) => key.startsWith(_cachePrefix),
      );
      for (final key in keys) {
        await _prefs!.remove(key);
      }

      // Reset statistics
      _hitCount = 0;
      _missCount = 0;
      _evictionCount = 0;

      _logger.i('Cache cleared');
    } catch (e, stackTrace) {
      _logger.e('Error clearing cache', error: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<int> size() async {
    try {
      _ensureInitialized();
      return _memoryCache.length;
    } catch (e, stackTrace) {
      _logger.e('Error getting cache size', error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  @override
  Future<List<String>> keys() async {
    try {
      _ensureInitialized();

      // Get all keys from memory cache and persistent storage
      final allKeys = <String>{};

      // Add memory cache keys
      allKeys.addAll(_memoryCache.keys);

      // Add persistent storage keys
      final persistentKeys = _prefs!
          .getKeys()
          .where((key) => key.startsWith(_cachePrefix))
          .map((key) => key.substring(_cachePrefix.length));
      allKeys.addAll(persistentKeys);

      return allKeys.toList();
    } catch (e, stackTrace) {
      _logger.e('Error getting cache keys', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  @override
  Future<CacheStats> getStats() async {
    try {
      _ensureInitialized();

      final totalRequests = _hitCount + _missCount;
      final hitRate = totalRequests > 0 ? _hitCount / totalRequests : 0.0;

      return CacheStats(
        hitCount: _hitCount,
        missCount: _missCount,
        evictionCount: _evictionCount,
        totalSize: _memoryCache.length,
        maxSize: _config.maxSize,
        hitRate: hitRate,
      );
    } catch (e, stackTrace) {
      _logger.e('Error getting cache stats', error: e, stackTrace: stackTrace);
      return const CacheStats(
        hitCount: 0,
        missCount: 0,
        evictionCount: 0,
        totalSize: 0,
        maxSize: 0,
        hitRate: 0.0,
      );
    }
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _memoryCache.clear();
    _logger.i('Cache Service disposed');
  }

  // Private methods

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('Cache Service not initialized');
    }
  }

  Future<void> _loadCacheFromStorage() async {
    try {
      final keys = _prefs!.getKeys().where(
        (key) => key.startsWith(_cachePrefix),
      );

      for (final key in keys) {
        final cacheKey = key.substring(_cachePrefix.length);
        final entry = await _loadFromStorage(cacheKey);
        if (entry != null && !entry.isExpired) {
          _memoryCache[cacheKey] = entry;
        }
      }

      _logger.i('Loaded ${_memoryCache.length} entries from storage');
    } catch (e, stackTrace) {
      _logger.e(
        'Error loading cache from storage',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<CacheEntry<T>?> _loadFromStorage<T>(String key) async {
    try {
      final jsonString = _prefs!.getString('$_cachePrefix$key');
      if (jsonString == null) return null;

      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      return CacheEntry<T>(
        key: json['key'] as String,
        value: json['value'] as T,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt:
            json['expiresAt'] != null
                ? DateTime.parse(json['expiresAt'] as String)
                : null,
        accessCount: json['accessCount'] as int,
        lastAccessedAt: DateTime.parse(json['lastAccessedAt'] as String),
      );
    } catch (e, stackTrace) {
      _logger.e(
        'Error loading from storage: $key',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _saveToStorage<T>(String key, CacheEntry<T> entry) async {
    try {
      final json = {
        'key': entry.key,
        'value': entry.value,
        'createdAt': entry.createdAt.toIso8601String(),
        'expiresAt': entry.expiresAt?.toIso8601String(),
        'accessCount': entry.accessCount,
        'lastAccessedAt': entry.lastAccessedAt.toIso8601String(),
      };

      await _prefs!.setString('$_cachePrefix$key', jsonEncode(json));
    } catch (e, stackTrace) {
      _logger.e(
        'Error saving to storage: $key',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _evictIfNeeded() async {
    if (_memoryCache.length <= _config.maxSize) return;

    try {
      final entriesToEvict = _memoryCache.length - _config.maxSize;
      final sortedEntries = _memoryCache.entries.toList();

      // Sort based on eviction policy
      switch (_config.evictionPolicy) {
        case CacheEvictionPolicy.lru:
          sortedEntries.sort(
            (a, b) => a.value.lastAccessedAt.compareTo(b.value.lastAccessedAt),
          );
          break;
        case CacheEvictionPolicy.lfu:
          sortedEntries.sort(
            (a, b) => a.value.accessCount.compareTo(b.value.accessCount),
          );
          break;
        case CacheEvictionPolicy.fifo:
          sortedEntries.sort(
            (a, b) => a.value.createdAt.compareTo(b.value.createdAt),
          );
          break;
        case CacheEvictionPolicy.ttl:
          sortedEntries.sort((a, b) {
            final aExpiry =
                a.value.expiresAt ??
                DateTime.now().add(const Duration(days: 365));
            final bExpiry =
                b.value.expiresAt ??
                DateTime.now().add(const Duration(days: 365));
            return aExpiry.compareTo(bExpiry);
          });
          break;
      }

      // Evict oldest entries
      for (int i = 0; i < entriesToEvict; i++) {
        final keyToEvict = sortedEntries[i].key;
        await remove(keyToEvict);
        _evictionCount++;
      }

      _logger.d('Evicted $entriesToEvict entries');
    } catch (e, stackTrace) {
      _logger.e('Error during eviction', error: e, stackTrace: stackTrace);
    }
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanupExpiredEntries();
    });
  }

  Future<void> _cleanupExpiredEntries() async {
    try {
      final expiredKeys = <String>[];

      for (final entry in _memoryCache.entries) {
        if (entry.value.isExpired) {
          expiredKeys.add(entry.key);
        }
      }

      for (final key in expiredKeys) {
        await remove(key);
      }

      if (expiredKeys.isNotEmpty) {
        _logger.d('Cleaned up ${expiredKeys.length} expired entries');
      }
    } catch (e, stackTrace) {
      _logger.e('Error during cleanup', error: e, stackTrace: stackTrace);
    }
  }
}
