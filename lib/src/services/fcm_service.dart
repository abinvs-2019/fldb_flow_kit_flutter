import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/interfaces/notification_service_interface.dart';
import '../core/interfaces/cache_service_interface.dart';

/// Utility class to convert RemoteMessage to Map
class RemoteMessageConverter {
  /// Convert a RemoteMessage to a standardized Map
  static Map<String, dynamic> toMap(RemoteMessage message) {
    return {
      'messageId': message.messageId,
      'title': message.notification?.title,
      'body': message.notification?.body,
      'data': message.data,
      'from': message.from,
      'category': message.category,
      'collapseKey': message.collapseKey,
      'contentAvailable': message.contentAvailable,
      'mutableContent': message.mutableContent,
      'sentTime': message.sentTime?.toIso8601String(),
      'threadId': message.threadId,
      'ttl': message.ttl,
    };
  }
}

/// Background notification handler data
class BackgroundHandlerConfig {
  static LocalNotificationServiceInterface? localNotificationService;
  static Function(Map<String, dynamic>)? messageHandler;
  static bool showBackgroundNotifications = false;
}

/// Top-level function to handle background messages
/// This function must be a top-level function as required by Firebase
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Initialize Firebase if not already done
    await Firebase.initializeApp();

    // Convert message to map format
    final messageData = RemoteMessageConverter.toMap(message);

    // Show local notification if configured
    if (BackgroundHandlerConfig.showBackgroundNotifications &&
        BackgroundHandlerConfig.localNotificationService != null &&
        message.notification != null) {
      final title = message.notification!.title ?? 'New Message';
      final body = message.notification!.body ?? '';
      final payload = jsonEncode(messageData);

      await BackgroundHandlerConfig.localNotificationService!.showNotification(
        title: title,
        body: body,
        payload: payload,
        data: message.data,
      );
    }

    // Call the registered background message handler if available
    if (BackgroundHandlerConfig.messageHandler != null) {
      await BackgroundHandlerConfig.messageHandler!(messageData);
    }
  } catch (e) {
    // Cannot log in background handler as logger might not be initialized
    // Background errors will be handled by Firebase itself
  }
}

/// FCM Service implementation
/// Follows Single Responsibility Principle - handles only FCM operations
class FCMService implements FCMServiceInterface {
  static const String _tokenCacheKey = 'fcm_token';
  static const String _topicsCacheKey = 'fcm_topics';
  static const String _messagesCacheKey = 'fcm_messages';

  final FirebaseMessaging _firebaseMessaging;
  final CacheServiceInterface _cacheService;
  final Logger _logger;

  // Optional local notification integration
  final LocalNotificationServiceInterface? _localNotificationService;
  bool _showForegroundNotifications; // Made mutable for setter to work

  // Callbacks
  Function(String? payload)? _onNotificationTap;
  Function(Map<String, dynamic>)? _onBackgroundMessage;
  Function(Map<String, dynamic>)? _onForegroundMessage;
  Function(String)? _onTokenRefresh;

  // State management
  bool _isInitialized = false;
  String? _currentToken;
  final Set<String> _subscribedTopics = {};

  // Stream controllers for reactive programming
  final StreamController<Map<String, dynamic>> _messageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _tokenStreamController =
      StreamController<String>.broadcast();

  FCMService({
    FirebaseMessaging? firebaseMessaging,
    required CacheServiceInterface cacheService,
    Logger? logger,
    LocalNotificationServiceInterface? localNotificationService,
    bool showForegroundNotifications = false,
    bool showBackgroundNotifications = false,
  }) : _firebaseMessaging = firebaseMessaging ?? FirebaseMessaging.instance,
       _cacheService = cacheService,
       _logger = logger ?? Logger(),
       _localNotificationService = localNotificationService,
       _showForegroundNotifications = showForegroundNotifications {
    // Configure background handler if local notification service is provided
    if (localNotificationService != null) {
      BackgroundHandlerConfig.localNotificationService =
          localNotificationService;
      BackgroundHandlerConfig.showBackgroundNotifications =
          showBackgroundNotifications;
    }
  }

  @override
  Future<bool> initialize() async {
    try {
      if (_isInitialized) {
        _logger.i('FCM Service already initialized');
        return true;
      }

      // Initialize Firebase if not already done
      await Firebase.initializeApp();

      // Initialize cache service
      await _cacheService.initialize();

      // Request permissions
      final permissionGranted = await requestPermissions();
      if (!permissionGranted) {
        _logger.w('FCM permissions not granted');
        // Continue initialization even if permissions aren't granted
        // User might grant them later
      }

      // Load cached data
      await _loadCachedData();

      // Set up message handlers
      _setupMessageHandlers();

      // Get and cache initial token
      await _refreshToken();

      _isInitialized = true;
      _logger.i('FCM Service initialized successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.e(
        'Failed to initialize FCM Service',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      // Check current permission status
      final status = await Permission.notification.status;
      if (status.isGranted) {
        return true;
      }

      // Request permission
      final result = await Permission.notification.request();
      if (result.isGranted) {
        _logger.i('FCM permissions granted');
        return true;
      }

      _logger.w('FCM permissions denied');
      return false;
    } catch (e, stackTrace) {
      _logger.e(
        'Error requesting FCM permissions',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e, stackTrace) {
      _logger.e(
        'Error checking notification status',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    Map<String, dynamic>? data,
  }) async {
    try {
      // FCM doesn't directly show notifications - this is handled by the platform
      // We can log and cache the notification for analytics
      final notification = {
        'title': title,
        'body': body,
        'payload': payload,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
      };

      await _cacheNotification(notification);
      _logger.i('Notification logged: $title');

      // If local notification service is available, use it to show the notification
      if (_localNotificationService != null) {
        await _localNotificationService!.showNotification(
          title: title,
          body: body,
          payload: payload,
          data: data,
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Error showing notification', error: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> cancelNotification(int id) async {
    // FCM doesn't support canceling individual notifications
    // This would be handled by the local notification service
    if (_localNotificationService != null) {
      await _localNotificationService!.cancelNotification(id);
      _logger.i(
        'Notification with ID $id canceled via local notification service',
      );
    } else {
      _logger.w('FCM does not support canceling individual notifications');
    }
  }

  @override
  Future<void> cancelAllNotifications() async {
    // FCM doesn't support canceling all notifications
    // This would be handled by the local notification service
    if (_localNotificationService != null) {
      await _localNotificationService!.cancelAllNotifications();
      _logger.i('All notifications canceled via local notification service');
    } else {
      _logger.w('FCM does not support canceling all notifications');
    }
  }

  @override
  void onNotificationTap(Function(String? payload) callback) {
    _onNotificationTap = callback;
  }

  @override
  Future<String?> getToken() async {
    try {
      if (_currentToken != null) {
        return _currentToken;
      }

      // Try to get from cache first
      final cachedToken = await _cacheService.get<String>(_tokenCacheKey);
      if (cachedToken != null) {
        _currentToken = cachedToken;
        return cachedToken;
      }

      // Get fresh token
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        _currentToken = token;
        await _cacheService.set(
          _tokenCacheKey,
          token,
          ttl: const Duration(days: 7),
        );
        _logger.i('FCM token retrieved and cached');
      }

      return token;
    } catch (e, stackTrace) {
      _logger.e('Error getting FCM token', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  @override
  Future<void> subscribeToTopic(String topic) async {
    try {
      if (_subscribedTopics.contains(topic)) {
        _logger.i('Already subscribed to topic: $topic');
        return;
      }

      await _firebaseMessaging.subscribeToTopic(topic);
      _subscribedTopics.add(topic);

      // Cache subscribed topics
      await _cacheService.set(_topicsCacheKey, _subscribedTopics.toList());

      _logger.i('Subscribed to topic: $topic');
    } catch (e, stackTrace) {
      _logger.e(
        'Error subscribing to topic: $topic',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      if (!_subscribedTopics.contains(topic)) {
        _logger.i('Not subscribed to topic: $topic');
        return;
      }

      await _firebaseMessaging.unsubscribeFromTopic(topic);
      _subscribedTopics.remove(topic);

      // Update cached topics
      await _cacheService.set(_topicsCacheKey, _subscribedTopics.toList());

      _logger.i('Unsubscribed from topic: $topic');
    } catch (e, stackTrace) {
      _logger.e(
        'Error unsubscribing from topic: $topic',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  void onBackgroundMessage(Function(Map<String, dynamic>) handler) {
    _onBackgroundMessage = handler;
    // Register the handler globally so it can be called from the top-level function
    BackgroundHandlerConfig.messageHandler = handler;
  }

  @override
  void onForegroundMessage(Function(Map<String, dynamic>) handler) {
    _onForegroundMessage = handler;
  }

  @override
  void onTokenRefresh(Function(String) handler) {
    _onTokenRefresh = handler;
  }

  @override
  void dispose() {
    _messageStreamController.close();
    _tokenStreamController.close();

    // Clear background handler references
    BackgroundHandlerConfig.localNotificationService = null;
    BackgroundHandlerConfig.messageHandler = null;

    // Don't dispose the cache service here as it might be shared
    // Just indicate we're done with it
    _logger.i('FCM Service disposed');
  }

  // Private methods

  Future<void> _loadCachedData() async {
    try {
      // Load cached token
      final cachedToken = await _cacheService.get<String>(_tokenCacheKey);
      if (cachedToken != null) {
        _currentToken = cachedToken;
      }

      // Load cached topics
      final cachedTopics = await _cacheService.get<List<dynamic>>(
        _topicsCacheKey,
      );
      if (cachedTopics != null) {
        // Convert to String if needed to handle type casting issues
        _subscribedTopics.addAll(cachedTopics.map((topic) => topic.toString()));
      }

      _logger.i('Cached FCM data loaded');
    } catch (e, stackTrace) {
      _logger.e(
        'Error loading cached FCM data',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _setupMessageHandlers() {
    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleForegroundMessage(message);
    });

    // Handle messages when app is in background but not terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleMessageOpenedApp(message);
    });

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((String token) {
      _handleTokenRefresh(token);
    });
  }

  void _handleForegroundMessage(RemoteMessage message) {
    try {
      final messageData = RemoteMessageConverter.toMap(message);

      // Cache the message
      _cacheNotification(messageData);

      // Notify listeners
      _messageStreamController.add(messageData);

      // Optionally show as local notification
      if (_showForegroundNotifications &&
          _localNotificationService != null &&
          message.notification != null) {
        _showForegroundMessageAsLocalNotification(message, messageData);
      }

      // Call custom handler if set
      _onForegroundMessage?.call(messageData);

      _logger.i('Foreground message handled: ${message.notification?.title}');
    } catch (e, stackTrace) {
      _logger.e(
        'Error handling foreground message',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    try {
      final messageData = RemoteMessageConverter.toMap(message);

      // Call notification tap handler
      _onNotificationTap?.call(jsonEncode(messageData));

      _logger.i('Message opened app: ${message.notification?.title}');
    } catch (e, stackTrace) {
      _logger.e(
        'Error handling message opened app',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _handleTokenRefresh(String token) {
    try {
      _currentToken = token;

      // Cache the new token
      _cacheService.set(_tokenCacheKey, token, ttl: const Duration(days: 7));

      // Notify listeners
      _tokenStreamController.add(token);

      // Call custom handler if set
      _onTokenRefresh?.call(token);

      _logger.i('FCM token refreshed and cached');
    } catch (e, stackTrace) {
      _logger.e(
        'Error handling token refresh',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _refreshToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      if (token != null && token != _currentToken) {
        _handleTokenRefresh(token);
      }
    } catch (e, stackTrace) {
      _logger.e('Error refreshing token', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _cacheNotification(Map<String, dynamic> notification) async {
    try {
      // Get existing cached messages
      List<dynamic> cachedMessages =
          await _cacheService.get<List<dynamic>>(_messagesCacheKey) ?? [];

      // Convert to List<Map<String, dynamic>> if needed
      List<Map<String, dynamic>> typedMessages =
          cachedMessages
              .map(
                (msg) =>
                    msg is Map
                        ? Map<String, dynamic>.from(msg as Map)
                        : <String, dynamic>{},
              )
              .toList();

      // Add new message
      typedMessages.add(notification);

      // Keep only last 100 messages for performance
      if (typedMessages.length > 100) {
        typedMessages.removeRange(0, typedMessages.length - 100);
      }

      // Cache updated messages
      await _cacheService.set(
        _messagesCacheKey,
        typedMessages,
        ttl: const Duration(days: 7),
      );
    } catch (e, stackTrace) {
      _logger.e('Error caching notification', error: e, stackTrace: stackTrace);
    }
  }

  /// Show foreground FCM message as local notification
  Future<void> _showForegroundMessageAsLocalNotification(
    RemoteMessage message,
    Map<String, dynamic> messageData,
  ) async {
    try {
      if (_localNotificationService == null || message.notification == null) {
        return;
      }

      final title = message.notification!.title ?? 'New Message';
      final body = message.notification!.body ?? '';
      final payload = jsonEncode(messageData);

      await _localNotificationService.showNotification(
        title: title,
        body: body,
        payload: payload,
        data: message.data,
      );

      _logger.i('FCM message shown as local notification: $title');
    } catch (e, stackTrace) {
      _logger.e(
        'Error showing FCM message as local notification',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Enable/disable showing foreground notifications
  /// This requires localNotificationService to be provided during initialization
  void setShowForegroundNotifications(bool enabled) {
    if (_localNotificationService == null && enabled) {
      _logger.w(
        'Cannot enable foreground notifications: LocalNotificationService not provided',
      );
      return;
    }
    _showForegroundNotifications = enabled;
    _logger.i('Foreground notifications setting: $enabled');
  }

  /// Enable/disable showing background notifications
  /// This requires localNotificationService to be provided during initialization
  void setShowBackgroundNotifications(bool enabled) {
    if (_localNotificationService == null && enabled) {
      _logger.w(
        'Cannot enable background notifications: LocalNotificationService not provided',
      );
      return;
    }
    BackgroundHandlerConfig.showBackgroundNotifications = enabled;
    _logger.i('Background notifications setting: $enabled');
  }

  // Public getters for accessing cached data

  /// Get subscribed topics
  Set<String> get subscribedTopics => Set.from(_subscribedTopics);

  /// Get message stream
  Stream<Map<String, dynamic>> get messageStream =>
      _messageStreamController.stream;

  /// Get token stream
  Stream<String> get tokenStream => _tokenStreamController.stream;

  /// Get cached messages
  Future<List<Map<String, dynamic>>> getCachedMessages() async {
    try {
      List<dynamic> rawMessages =
          await _cacheService.get<List<dynamic>>(_messagesCacheKey) ?? [];

      // Convert to List<Map<String, dynamic>> for type safety
      return rawMessages
          .map(
            (msg) =>
                msg is Map
                    ? Map<String, dynamic>.from(msg as Map)
                    : <String, dynamic>{},
          )
          .toList();
    } catch (e, stackTrace) {
      _logger.e(
        'Error getting cached messages',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Clear cached messages
  Future<void> clearCachedMessages() async {
    try {
      await _cacheService.remove(_messagesCacheKey);
      _logger.i('Cached messages cleared');
    } catch (e, stackTrace) {
      _logger.e(
        'Error clearing cached messages',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
