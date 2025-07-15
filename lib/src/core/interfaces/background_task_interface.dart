import 'package:flutter/foundation.dart';

/// Abstract interface for background task management
/// Follows Single Responsibility Principle - handles only background task operations
abstract class BackgroundTaskInterface {
  /// Initialize the background task service
  Future<bool> initialize();

  /// Register a background task
  Future<void> registerTask({
    required String taskName,
    required Function() taskHandler,
    Duration? frequency,
    Map<String, dynamic>? inputData,
  });

  /// Register a periodic background task
  Future<void> registerPeriodicTask({
    required String taskName,
    required Function() taskHandler,
    required Duration frequency,
    Map<String, dynamic>? inputData,
  });

  /// Cancel a background task
  Future<void> cancelTask(String taskName);

  /// Cancel all background tasks
  Future<void> cancelAllTasks();

  /// Check if a task is registered
  Future<bool> isTaskRegistered(String taskName);

  /// Get all registered tasks
  Future<List<BackgroundTaskInfo>> getRegisteredTasks();

  /// Dispose resources
  void dispose();
}

/// Data class for background task information
class BackgroundTaskInfo {
  final String taskName;
  final Duration? frequency;
  final Map<String, dynamic>? inputData;
  final DateTime? lastExecuted;
  final DateTime? nextExecution;
  final bool isActive;

  const BackgroundTaskInfo({
    required this.taskName,
    this.frequency,
    this.inputData,
    this.lastExecuted,
    this.nextExecution,
    required this.isActive,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BackgroundTaskInfo &&
        other.taskName == taskName &&
        other.frequency == frequency &&
        mapEquals(other.inputData, inputData) &&
        other.lastExecuted == lastExecuted &&
        other.nextExecution == nextExecution &&
        other.isActive == isActive;
  }

  @override
  int get hashCode {
    return taskName.hashCode ^
        frequency.hashCode ^
        inputData.hashCode ^
        lastExecuted.hashCode ^
        nextExecution.hashCode ^
        isActive.hashCode;
  }

  @override
  String toString() {
    return 'BackgroundTaskInfo(taskName: $taskName, frequency: $frequency, inputData: $inputData, lastExecuted: $lastExecuted, nextExecution: $nextExecution, isActive: $isActive)';
  }
}

/// Enum for background task execution constraints
enum BackgroundTaskConstraints {
  none,
  requiresCharging,
  requiresDeviceIdle,
  requiresNetworkConnected,
  requiresNetworkUnmetered,
  requiresStorageNotLow,
}

/// Configuration for background tasks
class BackgroundTaskConfig {
  final BackgroundTaskConstraints constraints;
  final int maxRetries;
  final Duration retryDelay;
  final bool requiresMainThread;

  const BackgroundTaskConfig({
    this.constraints = BackgroundTaskConstraints.none,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 30),
    this.requiresMainThread = false,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BackgroundTaskConfig &&
        other.constraints == constraints &&
        other.maxRetries == maxRetries &&
        other.retryDelay == retryDelay &&
        other.requiresMainThread == requiresMainThread;
  }

  @override
  int get hashCode {
    return constraints.hashCode ^
        maxRetries.hashCode ^
        retryDelay.hashCode ^
        requiresMainThread.hashCode;
  }

  @override
  String toString() {
    return 'BackgroundTaskConfig(constraints: $constraints, maxRetries: $maxRetries, retryDelay: $retryDelay, requiresMainThread: $requiresMainThread)';
  }
}
