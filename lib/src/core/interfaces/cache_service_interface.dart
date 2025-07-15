
/// Abstract interface for caching services
/// Follows Single Responsibility Principle - handles only caching operations
abstract class CacheServiceInterface {
  /// Initialize the cache service
  Future<bool> initialize();

  /// Store a value in cache
  Future<void> set<T>(String key, T value, {Duration? ttl});

  /// Get a value from cache
  Future<T?> get<T>(String key);

  /// Check if key exists in cache
  Future<bool> containsKey(String key);

  /// Remove a key from cache
  Future<void> remove(String key);

  /// Clear all cache
  Future<void> clear();

  /// Get cache size
  Future<int> size();

  /// Get all keys
  Future<List<String>> keys();

  /// Get cache statistics
  Future<CacheStats> getStats();

  /// Dispose resources
  void dispose();
}

/// Cache statistics data class
class CacheStats {
  final int hitCount;
  final int missCount;
  final int evictionCount;
  final int totalSize;
  final int maxSize;
  final double hitRate;

  const CacheStats({
    required this.hitCount,
    required this.missCount,
    required this.evictionCount,
    required this.totalSize,
    required this.maxSize,
    required this.hitRate,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CacheStats &&
        other.hitCount == hitCount &&
        other.missCount == missCount &&
        other.evictionCount == evictionCount &&
        other.totalSize == totalSize &&
        other.maxSize == maxSize &&
        other.hitRate == hitRate;
  }

  @override
  int get hashCode {
    return hitCount.hashCode ^
        missCount.hashCode ^
        evictionCount.hashCode ^
        totalSize.hashCode ^
        maxSize.hashCode ^
        hitRate.hashCode;
  }

  @override
  String toString() {
    return 'CacheStats(hitCount: $hitCount, missCount: $missCount, evictionCount: $evictionCount, totalSize: $totalSize, maxSize: $maxSize, hitRate: $hitRate)';
  }
}

/// Cache configuration
class CacheConfig {
  final int maxSize;
  final Duration defaultTtl;
  final bool enableLogging;
  final CacheEvictionPolicy evictionPolicy;

  const CacheConfig({
    this.maxSize = 1000,
    this.defaultTtl = const Duration(hours: 1),
    this.enableLogging = false,
    this.evictionPolicy = CacheEvictionPolicy.lru,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CacheConfig &&
        other.maxSize == maxSize &&
        other.defaultTtl == defaultTtl &&
        other.enableLogging == enableLogging &&
        other.evictionPolicy == evictionPolicy;
  }

  @override
  int get hashCode {
    return maxSize.hashCode ^
        defaultTtl.hashCode ^
        enableLogging.hashCode ^
        evictionPolicy.hashCode;
  }

  @override
  String toString() {
    return 'CacheConfig(maxSize: $maxSize, defaultTtl: $defaultTtl, enableLogging: $enableLogging, evictionPolicy: $evictionPolicy)';
  }
}

/// Cache eviction policies
enum CacheEvictionPolicy {
  lru, // Least Recently Used
  lfu, // Least Frequently Used
  fifo, // First In, First Out
  ttl, // Time To Live based
}

/// Cache entry data class
class CacheEntry<T> {
  final String key;
  final T value;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int accessCount;
  final DateTime lastAccessedAt;

  const CacheEntry({
    required this.key,
    required this.value,
    required this.createdAt,
    this.expiresAt,
    required this.accessCount,
    required this.lastAccessedAt,
  });

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  CacheEntry<T> copyWith({
    String? key,
    T? value,
    DateTime? createdAt,
    DateTime? expiresAt,
    int? accessCount,
    DateTime? lastAccessedAt,
  }) {
    return CacheEntry<T>(
      key: key ?? this.key,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      accessCount: accessCount ?? this.accessCount,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CacheEntry<T> &&
        other.key == key &&
        other.value == value &&
        other.createdAt == createdAt &&
        other.expiresAt == expiresAt &&
        other.accessCount == accessCount &&
        other.lastAccessedAt == lastAccessedAt;
  }

  @override
  int get hashCode {
    return key.hashCode ^
        value.hashCode ^
        createdAt.hashCode ^
        expiresAt.hashCode ^
        accessCount.hashCode ^
        lastAccessedAt.hashCode;
  }

  @override
  String toString() {
    return 'CacheEntry(key: $key, value: $value, createdAt: $createdAt, expiresAt: $expiresAt, accessCount: $accessCount, lastAccessedAt: $lastAccessedAt)';
  }
}
