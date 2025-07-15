import 'dart:async';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

import '../core/interfaces/navigation_service_interface.dart';
import '../core/interfaces/cache_service_interface.dart';

/// Deep Link Service implementation
/// Follows Single Responsibility Principle - handles only deep linking operations
class DeepLinkService implements DeepLinkServiceInterface {
  static const String _handlersKey = 'deep_link_handlers';
  static const String _historyKey = 'deep_link_history';

  final CacheServiceInterface _cacheService;
  final Logger _logger;
  final DeepLinkConfig _config;

  final Map<String, DeepLinkHandler> _handlers = {};
  final List<Map<String, dynamic>> _linkHistory = [];

  bool _isInitialized = false;
  StreamSubscription<String>? _linkSubscription;

  // Stream controller for incoming links
  final StreamController<String> _linkController =
      StreamController<String>.broadcast();

  DeepLinkService({
    required CacheServiceInterface cacheService,
    Logger? logger,
    DeepLinkConfig? config,
  }) : _cacheService = cacheService,
       _logger = logger ?? Logger(),
       _config =
           config ?? const DeepLinkConfig(scheme: 'app', host: 'example.com');

  @override
  Future<bool> initialize() async {
    try {
      if (_isInitialized) {
        _logger.i('Deep Link Service already initialized');
        return true;
      }

      // Initialize cache service
      await _cacheService.initialize();

      // Load cached data
      await _loadCachedData();

      // Set up platform channel for deep links
      await _setupPlatformChannel();

      _isInitialized = true;
      _logger.i('Deep Link Service initialized successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.e(
        'Failed to initialize Deep Link Service',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> handleIncomingLink(String link) async {
    try {
      _ensureInitialized();

      if (!validateDeepLink(link)) {
        _logger.w('Invalid deep link: $link');
        return;
      }

      final parameters = parseDeepLinkParameters(link);
      final pattern = _findMatchingPattern(link);

      if (pattern != null && _handlers.containsKey(pattern)) {
        // Execute registered handler
        await _handlers[pattern]!(link, parameters);

        // Record successful handling
        await _recordLinkHandling(link, parameters, true);

        if (_config.handleUniversalLinks || _config.handleCustomSchemes) {
          _logger.i('Deep link handled: $link');
        }
      } else {
        _logger.w('No handler found for deep link: $link');
        await _recordLinkHandling(link, parameters, false);
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error handling incoming link: $link',
        error: e,
        stackTrace: stackTrace,
      );
      await _recordLinkHandling(link, {}, false, error: e.toString());
    }
  }

  @override
  String generateDeepLink(String route, {Map<String, dynamic>? parameters}) {
    try {
      _ensureInitialized();

      final uri = Uri(
        scheme: _config.scheme,
        host: _config.host,
        path: route,
        queryParameters: parameters?.map(
          (key, value) => MapEntry(key, value.toString()),
        ),
      );

      final deepLink = uri.toString();

      if (_config.handleUniversalLinks || _config.handleCustomSchemes) {
        _logger.d('Generated deep link: $deepLink');
      }

      return deepLink;
    } catch (e, stackTrace) {
      _logger.e(
        'Error generating deep link for route: $route',
        error: e,
        stackTrace: stackTrace,
      );
      return '';
    }
  }

  @override
  void registerDeepLinkHandler(String pattern, DeepLinkHandler handler) {
    try {
      _handlers[pattern] = handler;

      // Cache handlers
      _cacheHandlers();

      if (_config.handleUniversalLinks || _config.handleCustomSchemes) {
        _logger.d('Registered deep link handler: $pattern');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error registering deep link handler: $pattern',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void unregisterDeepLinkHandler(String pattern) {
    try {
      _handlers.remove(pattern);

      // Update cached handlers
      _cacheHandlers();

      if (_config.handleUniversalLinks || _config.handleCustomSchemes) {
        _logger.d('Unregistered deep link handler: $pattern');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error unregistering deep link handler: $pattern',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void listenForDeepLinks(Function(String) onLinkReceived) {
    try {
      _linkSubscription?.cancel();
      _linkSubscription = _linkController.stream.listen(onLinkReceived);

      _logger.i('Started listening for deep links');
    } catch (e, stackTrace) {
      _logger.e(
        'Error setting up deep link listener',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void stopListeningForDeepLinks() {
    try {
      _linkSubscription?.cancel();
      _linkSubscription = null;

      _logger.i('Stopped listening for deep links');
    } catch (e, stackTrace) {
      _logger.e(
        'Error stopping deep link listener',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  bool validateDeepLink(String link) {
    try {
      final uri = Uri.parse(link);

      // Check scheme
      if (_config.handleCustomSchemes && uri.scheme == _config.scheme) {
        return true;
      }

      // Check universal links
      if (_config.handleUniversalLinks &&
          (uri.scheme == 'http' || uri.scheme == 'https')) {
        // Check if host is in allowed domains
        if (_config.allowedDomains.isNotEmpty) {
          return _config.allowedDomains.contains(uri.host);
        }

        // Check if host matches config host
        return uri.host == _config.host;
      }

      return false;
    } catch (e, stackTrace) {
      _logger.e(
        'Error validating deep link: $link',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Map<String, dynamic> parseDeepLinkParameters(String link) {
    try {
      final uri = Uri.parse(link);
      final parameters = <String, dynamic>{};

      // Add query parameters
      parameters.addAll(uri.queryParameters);

      // Add path segments as parameters
      if (uri.pathSegments.isNotEmpty) {
        parameters['path'] = uri.path;
        parameters['pathSegments'] = uri.pathSegments;
      }

      // Add fragment if present
      if (uri.fragment.isNotEmpty) {
        parameters['fragment'] = uri.fragment;
      }

      return parameters;
    } catch (e, stackTrace) {
      _logger.e(
        'Error parsing deep link parameters: $link',
        error: e,
        stackTrace: stackTrace,
      );
      return {};
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _linkController.close();
    _handlers.clear();
    _linkHistory.clear();
    _cacheService.dispose();
    _logger.i('Deep Link Service disposed');
  }

  /// Get deep link handling history
  List<Map<String, dynamic>> getLinkHistory() {
    return List.unmodifiable(_linkHistory);
  }

  /// Clear deep link history
  Future<void> clearLinkHistory() async {
    try {
      _linkHistory.clear();
      await _cacheService.remove(_historyKey);
      _logger.i('Deep link history cleared');
    } catch (e, stackTrace) {
      _logger.e(
        'Error clearing deep link history',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get deep link statistics
  Map<String, dynamic> getLinkStats() {
    try {
      final totalLinks = _linkHistory.length;
      final successfulLinks =
          _linkHistory.where((link) => link['success'] as bool).length;
      final failedLinks = totalLinks - successfulLinks;

      return {
        'total_links': totalLinks,
        'successful_links': successfulLinks,
        'failed_links': failedLinks,
        'success_rate':
            totalLinks > 0 ? (successfulLinks / totalLinks) * 100 : 0.0,
        'registered_handlers': _handlers.length,
      };
    } catch (e, stackTrace) {
      _logger.e('Error getting link stats', error: e, stackTrace: stackTrace);
      return {
        'total_links': 0,
        'successful_links': 0,
        'failed_links': 0,
        'success_rate': 0.0,
        'registered_handlers': 0,
      };
    }
  }

  // Private methods

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('Deep Link Service not initialized');
    }
  }

  Future<void> _setupPlatformChannel() async {
    try {
      // Set up method channel for deep links
      const platform = MethodChannel('fldb_flow_kit/deep_links');

      platform.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onDeepLink':
            final link = call.arguments as String;
            _linkController.add(link);
            await handleIncomingLink(link);
            break;
          default:
            _logger.w('Unknown method call: ${call.method}');
        }
      });

      // Get initial link if app was opened via deep link
      try {
        final initialLink = await platform.invokeMethod<String>(
          'getInitialLink',
        );
        if (initialLink != null && initialLink.isNotEmpty) {
          _linkController.add(initialLink);
          await handleIncomingLink(initialLink);
        }
      } catch (e) {
        // Initial link might not be available, which is fine
        _logger.d('No initial link available');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error setting up platform channel',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  String? _findMatchingPattern(String link) {
    try {
      final uri = Uri.parse(link);

      // Try exact match first
      if (_handlers.containsKey(link)) {
        return link;
      }

      // Try pattern matching
      for (final pattern in _handlers.keys) {
        if (_matchesPattern(uri, pattern)) {
          return pattern;
        }
      }

      return null;
    } catch (e, stackTrace) {
      _logger.e(
        'Error finding matching pattern for: $link',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  bool _matchesPattern(Uri uri, String pattern) {
    try {
      final patternUri = Uri.parse(pattern);

      // Check scheme
      if (patternUri.scheme != uri.scheme) {
        return false;
      }

      // Check host
      if (patternUri.host != uri.host && patternUri.host != '*') {
        return false;
      }

      // Check path pattern
      if (patternUri.path.contains('*')) {
        final patternParts = patternUri.path.split('/');
        final uriParts = uri.path.split('/');

        if (patternParts.length > uriParts.length) {
          return false;
        }

        for (int i = 0; i < patternParts.length; i++) {
          if (patternParts[i] != '*' && patternParts[i] != uriParts[i]) {
            return false;
          }
        }

        return true;
      } else {
        return patternUri.path == uri.path;
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error matching pattern: $pattern',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _recordLinkHandling(
    String link,
    Map<String, dynamic> parameters,
    bool success, {
    String? error,
  }) async {
    try {
      final record = {
        'link': link,
        'parameters': parameters,
        'success': success,
        'timestamp': DateTime.now().toIso8601String(),
        'error': error,
      };

      _linkHistory.add(record);

      // Keep only last 100 entries for performance
      if (_linkHistory.length > 100) {
        _linkHistory.removeAt(0);
      }

      // Cache link history
      await _cacheLinkHistory();
    } catch (e, stackTrace) {
      _logger.e(
        'Error recording link handling',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadCachedData() async {
    try {
      // Load link history
      final cachedHistory = await _cacheService.get<List<Map<String, dynamic>>>(
        _historyKey,
      );
      if (cachedHistory != null) {
        _linkHistory.clear();
        _linkHistory.addAll(cachedHistory);
      }

      _logger.i('Loaded ${_linkHistory.length} deep link history entries');
    } catch (e, stackTrace) {
      _logger.e(
        'Error loading cached deep link data',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _cacheLinkHistory() async {
    try {
      await _cacheService.set(
        _historyKey,
        _linkHistory,
        ttl: const Duration(days: 7),
      );
    } catch (e, stackTrace) {
      _logger.e('Error caching link history', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _cacheHandlers() async {
    try {
      // We can't serialize function handlers, so we just cache the patterns
      final patterns = _handlers.keys.toList();
      await _cacheService.set(
        _handlersKey,
        patterns,
        ttl: const Duration(days: 30),
      );
    } catch (e, stackTrace) {
      _logger.e('Error caching handlers', error: e, stackTrace: stackTrace);
    }
  }
}
