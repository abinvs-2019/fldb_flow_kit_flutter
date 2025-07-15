import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

import '../core/interfaces/navigation_service_interface.dart';
import '../core/interfaces/cache_service_interface.dart';

/// Navigation Service implementation using GoRouter
/// Follows Single Responsibility Principle - handles only navigation operations
class NavigationService implements NavigationServiceInterface {
  static const String _historyKey = 'navigation_history';
  static const String _routeHandlersKey = 'route_handlers';

  final CacheServiceInterface _cacheService;
  final Logger _logger;
  final NavigationConfig _config;

  GoRouter? _router;
  final Map<String, RouteHandler> _routeHandlers = {};
  final List<RouteInfo> _navigationHistory = [];

  bool _isInitialized = false;

  // Global navigator key for programmatic navigation
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  NavigationService({
    required CacheServiceInterface cacheService,
    Logger? logger,
    NavigationConfig? config,
  }) : _cacheService = cacheService,
       _logger = logger ?? Logger(),
       _config = config ?? const NavigationConfig(initialRoute: '/');

  @override
  Future<bool> initialize() async {
    try {
      if (_isInitialized) {
        _logger.i('Navigation Service already initialized');
        return true;
      }

      // Initialize cache service
      await _cacheService.initialize();

      // Load cached data
      await _loadCachedData();

      // Initialize router
      _initializeRouter();

      _isInitialized = true;
      _logger.i('Navigation Service initialized successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.e(
        'Failed to initialize Navigation Service',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> navigateTo(
    String route, {
    Map<String, dynamic>? parameters,
  }) async {
    try {
      _ensureInitialized();

      final context = navigatorKey.currentContext;
      if (context == null) {
        throw StateError('Navigation context not available');
      }

      // Build route with parameters
      final uri = _buildRouteUri(route, parameters);

      // Navigate using GoRouter
      context.go(uri);

      // Record navigation
      await _recordNavigation(route, parameters, 'navigation');

      if (_config.enableLogging) {
        _logger.d('Navigated to: $route');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error navigating to: $route',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> navigateAndReplace(
    String route, {
    Map<String, dynamic>? parameters,
  }) async {
    try {
      _ensureInitialized();

      final context = navigatorKey.currentContext;
      if (context == null) {
        throw StateError('Navigation context not available');
      }

      // Build route with parameters
      final uri = _buildRouteUri(route, parameters);

      // Navigate and replace using GoRouter
      context.pushReplacement(uri);

      // Record navigation
      await _recordNavigation(route, parameters, 'navigation');

      if (_config.enableLogging) {
        _logger.d('Navigated and replaced to: $route');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error navigating and replacing to: $route',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> navigateAndClearStack(
    String route, {
    Map<String, dynamic>? parameters,
  }) async {
    try {
      _ensureInitialized();

      final context = navigatorKey.currentContext;
      if (context == null) {
        throw StateError('Navigation context not available');
      }

      // Build route with parameters
      final uri = _buildRouteUri(route, parameters);

      // Navigate and clear stack using GoRouter
      context.go(uri);

      // Clear navigation history
      _navigationHistory.clear();

      // Record navigation
      await _recordNavigation(route, parameters, 'navigation');

      if (_config.enableLogging) {
        _logger.d('Navigated and cleared stack to: $route');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error navigating and clearing stack to: $route',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> goBack() async {
    try {
      _ensureInitialized();

      final context = navigatorKey.currentContext;
      if (context == null) {
        throw StateError('Navigation context not available');
      }

      if (context.canPop()) {
        context.pop();

        // Remove last entry from history
        if (_navigationHistory.isNotEmpty) {
          _navigationHistory.removeLast();
          await _cacheNavigationHistory();
        }

        if (_config.enableLogging) {
          _logger.d('Navigated back');
        }
      } else {
        _logger.w('Cannot go back - no previous route');
      }
    } catch (e, stackTrace) {
      _logger.e('Error going back', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  @override
  bool canGoBack() {
    try {
      _ensureInitialized();

      final context = navigatorKey.currentContext;
      if (context == null) return false;

      return context.canPop();
    } catch (e, stackTrace) {
      _logger.e(
        'Error checking if can go back',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  String? getCurrentRoute() {
    try {
      _ensureInitialized();

      final context = navigatorKey.currentContext;
      if (context == null) return null;

      return GoRouterState.of(context).uri.toString();
    } catch (e, stackTrace) {
      _logger.e(
        'Error getting current route',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  Future<void> handleDeepLink(String link) async {
    try {
      _ensureInitialized();

      final uri = Uri.parse(link);
      final route = uri.path;
      final parameters = uri.queryParameters;

      // Navigate to deep link
      await navigateTo(route, parameters: parameters);

      // Record as deep link navigation
      await _recordNavigation(route, parameters, 'deep_link');

      if (_config.enableLogging) {
        _logger.d('Handled deep link: $link');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error handling deep link: $link',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  void registerRouteHandler(String route, RouteHandler handler) {
    try {
      _routeHandlers[route] = handler;

      // Cache route handlers
      _cacheRouteHandlers();

      if (_config.enableLogging) {
        _logger.d('Registered route handler: $route');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error registering route handler: $route',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void unregisterRouteHandler(String route) {
    try {
      _routeHandlers.remove(route);

      // Update cached route handlers
      _cacheRouteHandlers();

      if (_config.enableLogging) {
        _logger.d('Unregistered route handler: $route');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error unregistering route handler: $route',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  List<RouteInfo> getNavigationHistory() {
    return List.unmodifiable(_navigationHistory);
  }

  @override
  void clearNavigationHistory() {
    try {
      _navigationHistory.clear();
      _cacheService.remove(_historyKey);

      if (_config.enableLogging) {
        _logger.d('Navigation history cleared');
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error clearing navigation history',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void dispose() {
    _routeHandlers.clear();
    _navigationHistory.clear();
    _cacheService.dispose();
    _logger.i('Navigation Service disposed');
  }

  /// Get the GoRouter instance
  GoRouter get router {
    if (_router == null) {
      throw StateError('Navigation Service not initialized');
    }
    return _router!;
  }

  // Private methods

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('Navigation Service not initialized');
    }
  }

  void _initializeRouter() {
    final routes = <RouteBase>[];

    // Add routes from config
    for (final entry in _config.routes.entries) {
      routes.add(
        GoRoute(
          path: entry.key,
          builder: (context, state) {
            final parameters = <String, dynamic>{};
            parameters.addAll(state.pathParameters);
            parameters.addAll(state.uri.queryParameters);
            return entry.value(context, parameters);
          },
        ),
      );
    }

    // Add routes from registered handlers
    for (final entry in _routeHandlers.entries) {
      // Skip if already added from config
      if (_config.routes.containsKey(entry.key)) continue;

      routes.add(
        GoRoute(
          path: entry.key,
          builder: (context, state) {
            final parameters = <String, dynamic>{};
            parameters.addAll(state.pathParameters);
            parameters.addAll(state.uri.queryParameters);
            return entry.value(context, parameters);
          },
        ),
      );
    }

    // Add default route if no routes defined
    if (routes.isEmpty) {
      routes.add(
        GoRoute(
          path: '/',
          builder:
              (context, state) => const Scaffold(
                body: Center(
                  child: Text('Default Route - No routes configured'),
                ),
              ),
        ),
      );
    }

    _router = GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: _config.initialRoute,
      routes: routes,
      errorBuilder:
          (context, state) => Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Route not found: ${state.uri}',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Go Home'),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  String _buildRouteUri(String route, Map<String, dynamic>? parameters) {
    if (parameters == null || parameters.isEmpty) {
      return route;
    }

    final uri = Uri.parse(route);
    final queryParams = <String, String>{};

    for (final entry in parameters.entries) {
      queryParams[entry.key] = entry.value.toString();
    }

    return uri.replace(queryParameters: queryParams).toString();
  }

  Future<void> _recordNavigation(
    String route,
    Map<String, dynamic>? parameters,
    String source,
  ) async {
    try {
      final routeInfo = RouteInfo(
        route: route,
        parameters: parameters,
        timestamp: DateTime.now(),
        source: source,
      );

      _navigationHistory.add(routeInfo);

      // Keep only last 100 entries for performance
      if (_navigationHistory.length > 100) {
        _navigationHistory.removeAt(0);
      }

      // Cache navigation history
      await _cacheNavigationHistory();
    } catch (e, stackTrace) {
      _logger.e('Error recording navigation', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _loadCachedData() async {
    try {
      // Load navigation history
      final cachedHistory = await _cacheService.get<List<Map<String, dynamic>>>(
        _historyKey,
      );
      if (cachedHistory != null) {
        _navigationHistory.clear();
        for (final historyMap in cachedHistory) {
          _navigationHistory.add(
            RouteInfo(
              route: historyMap['route'] as String,
              parameters: historyMap['parameters'] as Map<String, dynamic>?,
              timestamp: DateTime.parse(historyMap['timestamp'] as String),
              source: historyMap['source'] as String?,
            ),
          );
        }
      }

      _logger.i(
        'Loaded ${_navigationHistory.length} navigation history entries',
      );
    } catch (e, stackTrace) {
      _logger.e(
        'Error loading cached navigation data',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _cacheNavigationHistory() async {
    try {
      final historyMaps =
          _navigationHistory
              .map(
                (routeInfo) => {
                  'route': routeInfo.route,
                  'parameters': routeInfo.parameters,
                  'timestamp': routeInfo.timestamp.toIso8601String(),
                  'source': routeInfo.source,
                },
              )
              .toList();

      await _cacheService.set(
        _historyKey,
        historyMaps,
        ttl: const Duration(days: 7),
      );
    } catch (e, stackTrace) {
      _logger.e(
        'Error caching navigation history',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _cacheRouteHandlers() async {
    try {
      // We can't serialize function handlers, so we just cache the route names
      final routeNames = _routeHandlers.keys.toList();
      await _cacheService.set(
        _routeHandlersKey,
        routeNames,
        ttl: const Duration(days: 30),
      );
    } catch (e, stackTrace) {
      _logger.e(
        'Error caching route handlers',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
