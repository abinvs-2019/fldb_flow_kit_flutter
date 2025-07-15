
/// Abstract interface for notification services
/// Follows Interface Segregation Principle - clients depend only on methods they use
abstract class NotificationServiceInterface {
  /// Initialize the notification service
  Future<bool> initialize();

  /// Request notification permissions
  Future<bool> requestPermissions();

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled();

  /// Show a notification
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    Map<String, dynamic>? data,
  });

  /// Cancel a notification by ID
  Future<void> cancelNotification(int id);

  /// Cancel all notifications
  Future<void> cancelAllNotifications();

  /// Handle notification tap events
  void onNotificationTap(Function(String? payload) callback);

  /// Dispose resources
  void dispose();
}

/// Interface for FCM-specific functionality
abstract class FCMServiceInterface extends NotificationServiceInterface {
  /// Get FCM token
  Future<String?> getToken();

  /// Subscribe to topic
  Future<void> subscribeToTopic(String topic);

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic);

  /// Handle background messages
  void onBackgroundMessage(Function(Map<String, dynamic>) handler);

  /// Handle foreground messages
  void onForegroundMessage(Function(Map<String, dynamic>) handler);

  /// Handle token refresh
  void onTokenRefresh(Function(String) handler);
}

/// Interface for local notification functionality
abstract class LocalNotificationServiceInterface
    extends NotificationServiceInterface {
  /// Schedule a notification
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  });

  /// Schedule a periodic notification
  Future<void> schedulePeriodicNotification({
    required int id,
    required String title,
    required String body,
    required Duration interval,
    String? payload,
  });

  /// Get pending notifications
  Future<List<PendingNotification>> getPendingNotifications();

  /// Cancel scheduled notification
  Future<void> cancelScheduledNotification(int id);
}

/// Data class for pending notifications
class PendingNotification {
  final int id;
  final String title;
  final String body;
  final String? payload;
  final DateTime? scheduledDate;

  const PendingNotification({
    required this.id,
    required this.title,
    required this.body,
    this.payload,
    this.scheduledDate,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PendingNotification &&
        other.id == id &&
        other.title == title &&
        other.body == body &&
        other.payload == payload &&
        other.scheduledDate == scheduledDate;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        title.hashCode ^
        body.hashCode ^
        payload.hashCode ^
        scheduledDate.hashCode;
  }

  @override
  String toString() {
    return 'PendingNotification(id: $id, title: $title, body: $body, payload: $payload, scheduledDate: $scheduledDate)';
  }
}
