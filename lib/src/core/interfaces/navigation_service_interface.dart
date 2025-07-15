import 'package:flutter/material.dart';

/// Abstract interface for navigation and deep linking services
/// Follows Open/Closed Principle - open for extension, closed for modification
abstract class NavigationServiceInterface {
  /// Initialize the navigation service
  Future<bool> initialize();

  /// Navigate to a route
  Future<void> navigateTo(String route, {Map<String, dynamic>? parameters});

  /// Navigate and replace current route
  Future<void> navigateAndReplace(
    String route, {
    Map<String, dynamic>? parameters,
  });

  /// Navigate and clear stack
  Future<void> navigateAndClearStack(
    String route, {
    Map<String, dynamic>? parameters,
  });

  /// Go back to previous route
  Future<void> goBack();

  /// Check if can go back
  bool canGoBack();

  /// Get current route
  String? getCurrentRoute();

  /// Handle deep link
  Future<void> handleDeepLink(String link);

  /// Register route handler
  void registerRouteHandler(String route, RouteHandler handler);

  /// Unregister route handler
  void unregisterRouteHandler(String route);

  /// Get navigation history
  List<RouteInfo> getNavigationHistory();

  /// Clear navigation history
  void clearNavigationHistory();

  /// Dispose resources
  void dispose();
}

/// Abstract interface for deep linking functionality
abstract class DeepLinkServiceInterface {
  /// Initialize deep linking
  Future<bool> initialize();

  /// Handle incoming deep link
  Future<void> handleIncomingLink(String link);

  /// Generate deep link
  String generateDeepLink(String route, {Map<String, dynamic>? parameters});

  /// Register deep link handler
  void registerDeepLinkHandler(String pattern, DeepLinkHandler handler);

  /// Unregister deep link handler
  void unregisterDeepLinkHandler(String pattern);

  /// Listen for deep links
  void listenForDeepLinks(Function(String) onLinkReceived);

  /// Stop listening for deep links
  void stopListeningForDeepLinks();

  /// Validate deep link
  bool validateDeepLink(String link);

  /// Parse deep link parameters
  Map<String, dynamic> parseDeepLinkParameters(String link);

  /// Dispose resources
  void dispose();
}

/// Type definition for route handlers
typedef RouteHandler =
    Widget Function(BuildContext context, Map<String, dynamic> parameters);

/// Type definition for deep link handlers
typedef DeepLinkHandler =
    Future<void> Function(String link, Map<String, dynamic> parameters);

/// Data class for route information
class RouteInfo {
  final String route;
  final Map<String, dynamic>? parameters;
  final DateTime timestamp;
  final String? source; // 'navigation', 'deep_link', 'notification'

  const RouteInfo({
    required this.route,
    this.parameters,
    required this.timestamp,
    this.source,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RouteInfo &&
        other.route == route &&
        _mapsEqual(other.parameters, parameters) &&
        other.timestamp == timestamp &&
        other.source == source;
  }

  @override
  int get hashCode {
    return route.hashCode ^
        parameters.hashCode ^
        timestamp.hashCode ^
        source.hashCode;
  }

  @override
  String toString() {
    return 'RouteInfo(route: $route, parameters: $parameters, timestamp: $timestamp, source: $source)';
  }

  bool _mapsEqual(Map<String, dynamic>? map1, Map<String, dynamic>? map2) {
    if (map1 == null && map2 == null) return true;
    if (map1 == null || map2 == null) return false;
    if (map1.length != map2.length) return false;
    for (final key in map1.keys) {
      if (!map2.containsKey(key) || map1[key] != map2[key]) return false;
    }
    return true;
  }
}

/// Configuration for deep linking
class DeepLinkConfig {
  final String scheme;
  final String host;
  final List<String> allowedDomains;
  final bool handleUniversalLinks;
  final bool handleCustomSchemes;
  final Duration linkTimeout;

  const DeepLinkConfig({
    required this.scheme,
    required this.host,
    this.allowedDomains = const [],
    this.handleUniversalLinks = true,
    this.handleCustomSchemes = true,
    this.linkTimeout = const Duration(seconds: 30),
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeepLinkConfig &&
        other.scheme == scheme &&
        other.host == host &&
        _listEquals(other.allowedDomains, allowedDomains) &&
        other.handleUniversalLinks == handleUniversalLinks &&
        other.handleCustomSchemes == handleCustomSchemes &&
        other.linkTimeout == linkTimeout;
  }

  @override
  int get hashCode {
    return scheme.hashCode ^
        host.hashCode ^
        allowedDomains.hashCode ^
        handleUniversalLinks.hashCode ^
        handleCustomSchemes.hashCode ^
        linkTimeout.hashCode;
  }

  @override
  String toString() {
    return 'DeepLinkConfig(scheme: $scheme, host: $host, allowedDomains: $allowedDomains, handleUniversalLinks: $handleUniversalLinks, handleCustomSchemes: $handleCustomSchemes, linkTimeout: $linkTimeout)';
  }

  bool _listEquals(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }
}

/// Navigation configuration
class NavigationConfig {
  final String initialRoute;
  final bool enableLogging;
  final Duration routeTimeout;
  final Map<String, RouteHandler> routes;

  const NavigationConfig({
    required this.initialRoute,
    this.enableLogging = false,
    this.routeTimeout = const Duration(seconds: 10),
    this.routes = const {},
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NavigationConfig &&
        other.initialRoute == initialRoute &&
        other.enableLogging == enableLogging &&
        other.routeTimeout == routeTimeout &&
        _mapsEqual(other.routes, routes);
  }

  @override
  int get hashCode {
    return initialRoute.hashCode ^
        enableLogging.hashCode ^
        routeTimeout.hashCode ^
        routes.hashCode;
  }

  @override
  String toString() {
    return 'NavigationConfig(initialRoute: $initialRoute, enableLogging: $enableLogging, routeTimeout: $routeTimeout, routes: ${routes.keys.toList()})';
  }

  bool _mapsEqual(
    Map<String, RouteHandler> map1,
    Map<String, RouteHandler> map2,
  ) {
    if (map1.length != map2.length) return false;
    for (final key in map1.keys) {
      if (!map2.containsKey(key)) return false;
    }
    return true;
  }
}
