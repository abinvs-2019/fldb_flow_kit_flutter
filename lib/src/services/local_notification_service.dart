import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

import '../core/interfaces/notification_service_interface.dart';
import '../core/interfaces/cache_service_interface.dart';

/// Local Notification Service implementation
/// Follows Single Responsibility Principle - handles only local notification operations
class LocalNotificationService implements LocalNotificationServiceInterface {
  static const String _notificationsCacheKey = 'local_notifications';
  static const String _pendingNotificationsCacheKey = 'pending_notifications';

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;
  final CacheServiceInterface _cacheService;
  final Logger _logger;

  // Callbacks
  Function(String? payload)? _onNotificationTap;

  // State management
  bool _isInitialized = false;
  int _notificationIdCounter = 1000;

  LocalNotificationService({
    FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin,
    required CacheServiceInterface cacheService,
    Logger? logger,
  }) : _flutterLocalNotificationsPlugin =
           flutterLocalNotificationsPlugin ?? FlutterLocalNotificationsPlugin(),
       _cacheService = cacheService,
       _logger = logger ?? Logger();

  @override
  Future<bool> initialize() async {
    try {
      if (_isInitialized) {
        _logger.i('Local Notification Service already initialized');
        return true;
      }

      // Initialize cache service
      await _cacheService.initialize();

      // Initialize timezone data
      tz.initializeTimeZones();

      // Initialize notification plugin
      await _initializeNotificationPlugin();

      // Load cached counter
      await _loadNotificationCounter();

      _isInitialized = true;
      _logger.i('Local Notification Service initialized successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.e(
        'Failed to initialize Local Notification Service',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      if (Platform.isIOS) {
        final result = await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return result ?? false;
      } else if (Platform.isAndroid) {
        final result =
            await _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission();
        return result ?? false;
      }
      return true;
    } catch (e, stackTrace) {
      _logger.e(
        'Error requesting local notification permissions',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    try {
      if (Platform.isAndroid) {
        final result =
            await _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.areNotificationsEnabled();
        return result ?? false;
      }
      // For iOS, we assume notifications are enabled if permissions were granted
      return true;
    } catch (e, stackTrace) {
      _logger.e(
        'Error checking local notification status',
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
      final id = _getNextNotificationId();

      const androidDetails = AndroidNotificationDetails(
        'fluxbd_channel',
        'FLuxBD Notifications',
        channelDescription: 'Notifications from FLuxBD package',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      // Cache the notification
      await _cacheNotification({
        'id': id,
        'title': title,
        'body': body,
        'payload': payload,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
        'type': 'immediate',
      });

      _logger.i('Local notification shown: $title');
    } catch (e, stackTrace) {
      _logger.e(
        'Error showing local notification',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'fluxbd_scheduled_channel',
        'FLuxBD Scheduled Notifications',
        channelDescription: 'Scheduled notifications from FLuxBD package',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      // Cache the scheduled notification
      await _cachePendingNotification(
        PendingNotification(
          id: id,
          title: title,
          body: body,
          payload: payload,
          scheduledDate: scheduledDate,
        ),
      );

      _logger.i('Notification scheduled: $title at $scheduledDate');
    } catch (e, stackTrace) {
      _logger.e(
        'Error scheduling notification',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> schedulePeriodicNotification({
    required int id,
    required String title,
    required String body,
    required Duration interval,
    String? payload,
  }) async {
    try {
      // Convert Duration to RepeatInterval
      RepeatInterval repeatInterval;
      if (interval.inMinutes <= 1) {
        repeatInterval = RepeatInterval.everyMinute;
      } else if (interval.inHours <= 1) {
        repeatInterval = RepeatInterval.hourly;
      } else if (interval.inDays <= 1) {
        repeatInterval = RepeatInterval.daily;
      } else if (interval.inDays <= 7) {
        repeatInterval = RepeatInterval.weekly;
      } else {
        // For longer intervals, use daily and handle logic in app
        repeatInterval = RepeatInterval.daily;
      }

      const androidDetails = AndroidNotificationDetails(
        'fluxbd_periodic_channel',
        'FLuxBD Periodic Notifications',
        channelDescription: 'Periodic notifications from FLuxBD package',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _flutterLocalNotificationsPlugin.periodicallyShow(
        id,
        title,
        body,
        repeatInterval,
        notificationDetails,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      // Cache the periodic notification
      await _cachePendingNotification(
        PendingNotification(
          id: id,
          title: title,
          body: body,
          payload: payload,
          scheduledDate: DateTime.now().add(interval),
        ),
      );

      _logger.i(
        'Periodic notification scheduled: $title with interval $interval',
      );
    } catch (e, stackTrace) {
      _logger.e(
        'Error scheduling periodic notification',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<List<PendingNotification>> getPendingNotifications() async {
    try {
      final pendingNotificationRequests =
          await _flutterLocalNotificationsPlugin.pendingNotificationRequests();

      final pendingNotifications =
          pendingNotificationRequests.map((request) {
            return PendingNotification(
              id: request.id,
              title: request.title ?? '',
              body: request.body ?? '',
              payload: request.payload,
              scheduledDate: null, // Plugin doesn't provide scheduled date
            );
          }).toList();

      // Also get from cache for additional information
      final cachedPending =
          await _cacheService.get<List<Map<String, dynamic>>>(
            _pendingNotificationsCacheKey,
          ) ??
          [];

      // Merge with cached data for complete information
      for (final cached in cachedPending) {
        final id = cached['id'] as int;
        final existingIndex = pendingNotifications.indexWhere(
          (n) => n.id == id,
        );
        if (existingIndex != -1) {
          // Update with cached scheduled date
          final scheduledDateStr = cached['scheduledDate'] as String?;
          if (scheduledDateStr != null) {
            pendingNotifications[existingIndex] = PendingNotification(
              id: id,
              title: cached['title'] as String,
              body: cached['body'] as String,
              payload: cached['payload'] as String?,
              scheduledDate: DateTime.parse(scheduledDateStr),
            );
          }
        }
      }

      return pendingNotifications;
    } catch (e, stackTrace) {
      _logger.e(
        'Error getting pending notifications',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  @override
  Future<void> cancelNotification(int id) async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(id);

      // Remove from cache
      await _removePendingNotificationFromCache(id);

      _logger.i('Notification canceled: $id');
    } catch (e, stackTrace) {
      _logger.e(
        'Error canceling notification: $id',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> cancelScheduledNotification(int id) async {
    await cancelNotification(id); // Same implementation
  }

  @override
  Future<void> cancelAllNotifications() async {
    try {
      await _flutterLocalNotificationsPlugin.cancelAll();

      // Clear cache
      await _cacheService.remove(_pendingNotificationsCacheKey);

      _logger.i('All notifications canceled');
    } catch (e, stackTrace) {
      _logger.e(
        'Error canceling all notifications',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  void onNotificationTap(Function(String? payload) callback) {
    _onNotificationTap = callback;
  }

  @override
  void dispose() {
    _cacheService.dispose();
    _logger.i('Local Notification Service disposed');
  }

  // Private methods

  Future<void> _initializeNotificationPlugin() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTap(response);
      },
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }
  }

  Future<void> _createNotificationChannels() async {
    final androidPlugin =
        _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidPlugin != null) {
      // Default channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'fluxbd_channel',
          'FLuxBD Notifications',
          description: 'Notifications from FLuxBD package',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        ),
      );

      // Scheduled notifications channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'fluxbd_scheduled_channel',
          'FLuxBD Scheduled Notifications',
          description: 'Scheduled notifications from FLuxBD package',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        ),
      );

      // Periodic notifications channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'fluxbd_periodic_channel',
          'FLuxBD Periodic Notifications',
          description: 'Periodic notifications from FLuxBD package',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        ),
      );
    }
  }

  void _handleNotificationTap(NotificationResponse response) {
    try {
      _onNotificationTap?.call(response.payload);
      _logger.i('Notification tapped: ${response.payload}');
    } catch (e, stackTrace) {
      _logger.e(
        'Error handling notification tap',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  int _getNextNotificationId() {
    return _notificationIdCounter++;
  }

  Future<void> _loadNotificationCounter() async {
    try {
      final cachedCounter = await _cacheService.get<int>(
        'notification_counter',
      );
      if (cachedCounter != null) {
        _notificationIdCounter = cachedCounter;
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error loading notification counter',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _saveNotificationCounter() async {
    try {
      await _cacheService.set('notification_counter', _notificationIdCounter);
    } catch (e, stackTrace) {
      _logger.e(
        'Error saving notification counter',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _cacheNotification(Map<String, dynamic> notification) async {
    try {
      // Get existing cached notifications
      final cachedNotifications =
          await _cacheService.get<List<Map<String, dynamic>>>(
            _notificationsCacheKey,
          ) ??
          [];

      // Add new notification
      cachedNotifications.add(notification);

      // Keep only last 100 notifications for performance
      if (cachedNotifications.length > 100) {
        cachedNotifications.removeRange(0, cachedNotifications.length - 100);
      }

      // Cache updated notifications
      await _cacheService.set(
        _notificationsCacheKey,
        cachedNotifications,
        ttl: const Duration(days: 7),
      );

      // Save counter
      await _saveNotificationCounter();
    } catch (e, stackTrace) {
      _logger.e('Error caching notification', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _cachePendingNotification(
    PendingNotification notification,
  ) async {
    try {
      // Get existing cached pending notifications
      final cachedPending =
          await _cacheService.get<List<Map<String, dynamic>>>(
            _pendingNotificationsCacheKey,
          ) ??
          [];

      // Add new pending notification
      cachedPending.add({
        'id': notification.id,
        'title': notification.title,
        'body': notification.body,
        'payload': notification.payload,
        'scheduledDate': notification.scheduledDate?.toIso8601String(),
      });

      // Cache updated pending notifications
      await _cacheService.set(
        _pendingNotificationsCacheKey,
        cachedPending,
        ttl: const Duration(days: 30),
      );
    } catch (e, stackTrace) {
      _logger.e(
        'Error caching pending notification',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _removePendingNotificationFromCache(int id) async {
    try {
      final cachedPending =
          await _cacheService.get<List<Map<String, dynamic>>>(
            _pendingNotificationsCacheKey,
          ) ??
          [];

      // Remove the notification with the given ID
      cachedPending.removeWhere((notification) => notification['id'] == id);

      // Update cache
      await _cacheService.set(
        _pendingNotificationsCacheKey,
        cachedPending,
        ttl: const Duration(days: 30),
      );
    } catch (e, stackTrace) {
      _logger.e(
        'Error removing pending notification from cache',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  // Public getters for accessing cached data

  /// Get cached notifications
  Future<List<Map<String, dynamic>>> getCachedNotifications() async {
    try {
      return await _cacheService.get<List<Map<String, dynamic>>>(
            _notificationsCacheKey,
          ) ??
          [];
    } catch (e, stackTrace) {
      _logger.e(
        'Error getting cached notifications',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Clear cached notifications
  Future<void> clearCachedNotifications() async {
    try {
      await _cacheService.remove(_notificationsCacheKey);
      _logger.i('Cached notifications cleared');
    } catch (e, stackTrace) {
      _logger.e(
        'Error clearing cached notifications',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get notification statistics
  Future<Map<String, int>> getNotificationStats() async {
    try {
      final cached = await getCachedNotifications();
      final pending = await getPendingNotifications();

      return {
        'total_sent': cached.length,
        'pending': pending.length,
        'last_id': _notificationIdCounter - 1,
      };
    } catch (e, stackTrace) {
      _logger.e(
        'Error getting notification stats',
        error: e,
        stackTrace: stackTrace,
      );
      return {'total_sent': 0, 'pending': 0, 'last_id': 0};
    }
  }
}
