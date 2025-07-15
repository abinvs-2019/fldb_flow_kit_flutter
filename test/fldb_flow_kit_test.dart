import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'package:fldb_flow_kit/fldb_flow_kit.dart';

void main() {
  group('CacheService Tests', () {
    late CacheService cacheService;
    late Logger logger;

    setUp(() {
      logger = Logger(level: Level.off);
      cacheService = CacheService(logger: logger);
    });

    tearDown(() {
      cacheService.dispose();
    });

    test('should initialize successfully', () async {
      final result = await cacheService.initialize();
      expect(result, isTrue);
    });

    test('should set and get values correctly', () async {
      await cacheService.initialize();

      const key = 'test_key';
      const value = 'test_value';

      await cacheService.set(key, value);
      final retrieved = await cacheService.get<String>(key);

      expect(retrieved, equals(value));
    });

    test('should handle TTL expiration', () async {
      await cacheService.initialize();

      const key = 'expiring_key';
      const value = 'expiring_value';

      await cacheService.set(
        key,
        value,
        ttl: const Duration(milliseconds: 100),
      );

      // Should be available immediately
      final immediate = await cacheService.get<String>(key);
      expect(immediate, equals(value));

      // Wait for expiration
      await Future.delayed(const Duration(milliseconds: 150));

      final expired = await cacheService.get<String>(key);
      expect(expired, isNull);
    });

    test('should check key existence correctly', () async {
      await cacheService.initialize();

      const key = 'existence_key';
      const value = 'existence_value';

      expect(await cacheService.containsKey(key), isFalse);

      await cacheService.set(key, value);
      expect(await cacheService.containsKey(key), isTrue);

      await cacheService.remove(key);
      expect(await cacheService.containsKey(key), isFalse);
    });

    test('should clear all cache entries', () async {
      await cacheService.initialize();

      await cacheService.set('key1', 'value1');
      await cacheService.set('key2', 'value2');

      expect(await cacheService.size(), equals(2));

      await cacheService.clear();
      expect(await cacheService.size(), equals(0));
    });

    test('should return cache statistics', () async {
      await cacheService.initialize();

      // Generate some hits and misses
      await cacheService.set('key1', 'value1');
      await cacheService.get<String>('key1'); // Hit
      await cacheService.get<String>('nonexistent'); // Miss

      final stats = await cacheService.getStats();
      expect(stats.hitCount, greaterThan(0));
      expect(stats.missCount, greaterThan(0));
      expect(stats.hitRate, greaterThanOrEqualTo(0.0));
      expect(stats.hitRate, lessThanOrEqualTo(1.0));
    });

    test('should handle different data types', () async {
      await cacheService.initialize();

      // Test with different data types
      await cacheService.set('string_key', 'string_value');
      await cacheService.set('int_key', 42);
      await cacheService.set('bool_key', true);
      await cacheService.set('list_key', [1, 2, 3]);
      await cacheService.set('map_key', {'nested': 'value'});

      expect(
        await cacheService.get<String>('string_key'),
        equals('string_value'),
      );
      expect(await cacheService.get<int>('int_key'), equals(42));
      expect(await cacheService.get<bool>('bool_key'), equals(true));
      expect(await cacheService.get<List<int>>('list_key'), equals([1, 2, 3]));
      expect(
        await cacheService.get<Map<String, String>>('map_key'),
        equals({'nested': 'value'}),
      );
    });

    test('should return all keys', () async {
      await cacheService.initialize();

      await cacheService.set('key1', 'value1');
      await cacheService.set('key2', 'value2');
      await cacheService.set('key3', 'value3');

      final keys = await cacheService.keys();
      expect(keys.length, equals(3));
      expect(keys.contains('key1'), isTrue);
      expect(keys.contains('key2'), isTrue);
      expect(keys.contains('key3'), isTrue);
    });
  });

  group('BackgroundTaskService Tests', () {
    late BackgroundTaskService backgroundTaskService;
    late CacheService cacheService;
    late Logger logger;

    setUp(() {
      logger = Logger(level: Level.off);
      cacheService = CacheService(logger: logger);
      backgroundTaskService = BackgroundTaskService(
        cacheService: cacheService,
        logger: logger,
      );
    });

    tearDown(() {
      backgroundTaskService.dispose();
      cacheService.dispose();
    });

    test('should initialize successfully', () async {
      final result = await backgroundTaskService.initialize();
      expect(result, isTrue);
    });

    test('should register and check task registration', () async {
      await backgroundTaskService.initialize();

      const taskName = 'test_task';

      await backgroundTaskService.registerTask(
        taskName: taskName,
        taskHandler: () async {},
      );

      final isRegistered = await backgroundTaskService.isTaskRegistered(
        taskName,
      );
      expect(isRegistered, isTrue);

      final tasks = await backgroundTaskService.getRegisteredTasks();
      expect(tasks.any((task) => task.taskName == taskName), isTrue);
    });

    test('should cancel tasks correctly', () async {
      await backgroundTaskService.initialize();

      const taskName = 'cancelable_task';

      await backgroundTaskService.registerTask(
        taskName: taskName,
        taskHandler: () async {},
      );

      expect(await backgroundTaskService.isTaskRegistered(taskName), isTrue);

      await backgroundTaskService.cancelTask(taskName);
      expect(await backgroundTaskService.isTaskRegistered(taskName), isFalse);
    });

    test('should get task statistics', () async {
      await backgroundTaskService.initialize();

      await backgroundTaskService.registerTask(
        taskName: 'stats_task',
        taskHandler: () async {},
      );

      final stats = await backgroundTaskService.getTaskStats();
      expect(stats['total_tasks'], equals(1));
      expect(stats['active_tasks'], equals(1));
      expect(stats['success_rate'], isA<double>());
    });
  });

  group('DeepLinkService Tests', () {
    late DeepLinkService deepLinkService;
    late CacheService cacheService;
    late Logger logger;

    setUp(() {
      logger = Logger(level: Level.off);
      cacheService = CacheService(logger: logger);
      deepLinkService = DeepLinkService(
        cacheService: cacheService,
        logger: logger,
        config: const DeepLinkConfig(scheme: 'testapp', host: 'test.com'),
      );
    });

    tearDown() {
      deepLinkService.dispose();
      cacheService.dispose();
    }

    test('should initialize successfully', () async {
      final result = await deepLinkService.initialize();
      expect(result, isTrue);
    });

    test('should generate deep links correctly', () async {
      await deepLinkService.initialize();

      const route = '/test';
      final parameters = {'param1': 'value1', 'param2': 'value2'};

      final deepLink = deepLinkService.generateDeepLink(
        route,
        parameters: parameters,
      );
      expect(deepLink, contains('testapp://test.com/test'));
      expect(deepLink, contains('param1=value1'));
      expect(deepLink, contains('param2=value2'));
    });

    test('should validate deep links correctly', () async {
      await deepLinkService.initialize();

      expect(
        deepLinkService.validateDeepLink('testapp://test.com/valid'),
        isTrue,
      );
      expect(
        deepLinkService.validateDeepLink('invalid://wrong.com/path'),
        isFalse,
      );
      expect(deepLinkService.validateDeepLink('not-a-url'), isFalse);
    });

    test('should parse deep link parameters correctly', () async {
      await deepLinkService.initialize();

      const link = 'testapp://test.com/path?param1=value1&param2=value2';
      final parameters = deepLinkService.parseDeepLinkParameters(link);

      expect(parameters['param1'], equals('value1'));
      expect(parameters['param2'], equals('value2'));
      expect(parameters['path'], equals('/path'));
    });

    test('should provide link statistics', () async {
      await deepLinkService.initialize();

      final stats = deepLinkService.getLinkStats();
      expect(stats, isA<Map<String, dynamic>>());
      expect(stats.containsKey('total_links'), isTrue);
      expect(stats.containsKey('successful_links'), isTrue);
      expect(stats.containsKey('failed_links'), isTrue);
      expect(stats.containsKey('success_rate'), isTrue);
    });
  });

  group('Integration Tests', () {
    test('should work together - cache and background tasks', () async {
      final cacheService = CacheService();
      await cacheService.initialize();

      final backgroundTaskService = BackgroundTaskService(
        cacheService: cacheService,
      );
      await backgroundTaskService.initialize();

      // Test that background task service can use cache service
      await backgroundTaskService.registerTask(
        taskName: 'integration_test',
        taskHandler: () async {},
      );

      final tasks = await backgroundTaskService.getRegisteredTasks();
      expect(tasks.length, equals(1));

      cacheService.dispose();
      backgroundTaskService.dispose();
    });

    test('should work together - cache and deep links', () async {
      final cacheService = CacheService();
      await cacheService.initialize();

      final deepLinkService = DeepLinkService(
        cacheService: cacheService,
        config: const DeepLinkConfig(scheme: 'test', host: 'example.com'),
      );
      await deepLinkService.initialize();

      // Test that deep link service can use cache service
      final link = deepLinkService.generateDeepLink('/test');
      expect(link, isNotEmpty);

      cacheService.dispose();
      deepLinkService.dispose();
    });
  });
}
