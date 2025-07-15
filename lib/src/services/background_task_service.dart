import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:workmanager/workmanager.dart';

import '../core/interfaces/background_task_interface.dart';
import '../core/interfaces/cache_service_interface.dart';

/// Background Task Service implementation
/// Follows Single Responsibility Principle - handles only background task operations
class BackgroundTaskService implements BackgroundTaskInterface {
  static const String _tasksCacheKey = 'background_tasks';
  static const String _taskHistoryCacheKey = 'task_history';

  final Workmanager _workmanager;
  final CacheServiceInterface _cacheService;
  final Logger _logger;

  // State management
  bool _isInitialized = false;
  final Map<String, BackgroundTaskInfo> _registeredTasks = {};
  final Map<String, Function()> _taskHandlers = {};

  // Stream controllers for reactive programming
  final StreamController<BackgroundTaskInfo> _taskExecutionController =
      StreamController<BackgroundTaskInfo>.broadcast();

  BackgroundTaskService({
    Workmanager? workmanager,
    required CacheServiceInterface cacheService,
    Logger? logger,
  }) : _workmanager = workmanager ?? Workmanager(),
       _cacheService = cacheService,
       _logger = logger ?? Logger();

  @override
  Future<bool> initialize() async {
    try {
      if (_isInitialized) {
        _logger.i('Background Task Service already initialized');
        return true;
      }

      // Initialize cache service
      await _cacheService.initialize();

      // Initialize workmanager
      await _workmanager.initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );

      // Load cached tasks
      await _loadCachedTasks();

      _isInitialized = true;
      _logger.i('Background Task Service initialized successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.e(
        'Failed to initialize Background Task Service',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> registerTask({
    required String taskName,
    required Function() taskHandler,
    Duration? frequency,
    Map<String, dynamic>? inputData,
  }) async {
    try {
      if (!_isInitialized) {
        throw StateError('Background Task Service not initialized');
      }

      // Store task handler locally and globally
      _taskHandlers[taskName] = taskHandler;
      _globalTaskHandlers[taskName] = taskHandler;

      // Create task info
      final taskInfo = BackgroundTaskInfo(
        taskName: taskName,
        frequency: frequency,
        inputData: inputData,
        nextExecution: frequency != null ? DateTime.now().add(frequency) : null,
        isActive: true,
      );

      // Register with workmanager
      if (frequency != null) {
        await _workmanager.registerPeriodicTask(
          taskName,
          taskName,
          frequency: frequency,
          inputData: inputData,
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresCharging: false,
            requiresDeviceIdle: false,
          ),
        );
      } else {
        await _workmanager.registerOneOffTask(
          taskName,
          taskName,
          inputData: inputData,
        );
      }

      // Cache task info
      _registeredTasks[taskName] = taskInfo;
      await _cacheTaskInfo(taskInfo);

      _logger.i('Background task registered: $taskName');
    } catch (e, stackTrace) {
      _logger.e(
        'Error registering background task: $taskName',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> registerPeriodicTask({
    required String taskName,
    required Function() taskHandler,
    required Duration frequency,
    Map<String, dynamic>? inputData,
  }) async {
    await registerTask(
      taskName: taskName,
      taskHandler: taskHandler,
      frequency: frequency,
      inputData: inputData,
    );
  }

  @override
  Future<void> cancelTask(String taskName) async {
    try {
      if (!_isInitialized) {
        throw StateError('Background Task Service not initialized');
      }

      // Cancel with workmanager
      await _workmanager.cancelByUniqueName(taskName);

      // Remove from local storage and global handlers
      _registeredTasks.remove(taskName);
      _taskHandlers.remove(taskName);
      _globalTaskHandlers.remove(taskName);

      // Remove from cache
      await _removeTaskFromCache(taskName);

      _logger.i('Background task canceled: $taskName');
    } catch (e, stackTrace) {
      _logger.e(
        'Error canceling background task: $taskName',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> cancelAllTasks() async {
    try {
      if (!_isInitialized) {
        throw StateError('Background Task Service not initialized');
      }

      // Cancel all tasks with workmanager
      await _workmanager.cancelAll();

      // Clear local storage and global handlers
      _registeredTasks.clear();
      _taskHandlers.clear();
      _globalTaskHandlers.clear();

      // Clear cache
      await _cacheService.remove(_tasksCacheKey);

      _logger.i('All background tasks canceled');
    } catch (e, stackTrace) {
      _logger.e(
        'Error canceling all background tasks',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<bool> isTaskRegistered(String taskName) async {
    try {
      return _registeredTasks.containsKey(taskName);
    } catch (e, stackTrace) {
      _logger.e(
        'Error checking if task is registered: $taskName',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<List<BackgroundTaskInfo>> getRegisteredTasks() async {
    try {
      return _registeredTasks.values.toList();
    } catch (e, stackTrace) {
      _logger.e(
        'Error getting registered tasks',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  @override
  void dispose() {
    _taskExecutionController.close();
    _cacheService.dispose();
    _logger.i('Background Task Service disposed');
  }

  // Private methods

  Future<void> _loadCachedTasks() async {
    try {
      final cachedTasks = await _cacheService.get<List<Map<String, dynamic>>>(
        _tasksCacheKey,
      );
      if (cachedTasks != null) {
        for (final taskMap in cachedTasks) {
          final taskInfo = BackgroundTaskInfo(
            taskName: taskMap['taskName'] as String,
            frequency:
                taskMap['frequency'] != null
                    ? Duration(milliseconds: taskMap['frequency'] as int)
                    : null,
            inputData: taskMap['inputData'] as Map<String, dynamic>?,
            lastExecuted:
                taskMap['lastExecuted'] != null
                    ? DateTime.parse(taskMap['lastExecuted'] as String)
                    : null,
            nextExecution:
                taskMap['nextExecution'] != null
                    ? DateTime.parse(taskMap['nextExecution'] as String)
                    : null,
            isActive: taskMap['isActive'] as bool? ?? true,
          );
          _registeredTasks[taskInfo.taskName] = taskInfo;
        }
      }
      _logger.i('Cached background tasks loaded');
    } catch (e, stackTrace) {
      _logger.e(
        'Error loading cached background tasks',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _cacheTaskInfo(BackgroundTaskInfo taskInfo) async {
    try {
      final cachedTasks =
          await _cacheService.get<List<Map<String, dynamic>>>(_tasksCacheKey) ??
          [];

      // Remove existing task if it exists
      cachedTasks.removeWhere((task) => task['taskName'] == taskInfo.taskName);

      // Add updated task
      cachedTasks.add({
        'taskName': taskInfo.taskName,
        'frequency': taskInfo.frequency?.inMilliseconds,
        'inputData': taskInfo.inputData,
        'lastExecuted': taskInfo.lastExecuted?.toIso8601String(),
        'nextExecution': taskInfo.nextExecution?.toIso8601String(),
        'isActive': taskInfo.isActive,
      });

      await _cacheService.set(
        _tasksCacheKey,
        cachedTasks,
        ttl: const Duration(days: 30),
      );
    } catch (e, stackTrace) {
      _logger.e('Error caching task info', error: e, stackTrace: stackTrace);
    }
  }

  Future<void> _removeTaskFromCache(String taskName) async {
    try {
      final cachedTasks =
          await _cacheService.get<List<Map<String, dynamic>>>(_tasksCacheKey) ??
          [];
      cachedTasks.removeWhere((task) => task['taskName'] == taskName);
      await _cacheService.set(
        _tasksCacheKey,
        cachedTasks,
        ttl: const Duration(days: 30),
      );
    } catch (e, stackTrace) {
      _logger.e(
        'Error removing task from cache',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get task execution stream
  Stream<BackgroundTaskInfo> get taskExecutionStream =>
      _taskExecutionController.stream;

  /// Get task execution history
  Future<List<Map<String, dynamic>>> getTaskHistory() async {
    try {
      return await _cacheService.get<List<Map<String, dynamic>>>(
            _taskHistoryCacheKey,
          ) ??
          [];
    } catch (e, stackTrace) {
      _logger.e('Error getting task history', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Clear task history
  Future<void> clearTaskHistory() async {
    try {
      await _cacheService.remove(_taskHistoryCacheKey);
      _logger.i('Task history cleared');
    } catch (e, stackTrace) {
      _logger.e(
        'Error clearing task history',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get task statistics
  Future<Map<String, dynamic>> getTaskStats() async {
    try {
      final history = await getTaskHistory();
      final activeTasks =
          _registeredTasks.values.where((task) => task.isActive).length;
      final totalExecutions = history.length;
      final successfulExecutions =
          history.where((exec) => exec['success'] as bool).length;

      return {
        'active_tasks': activeTasks,
        'total_tasks': _registeredTasks.length,
        'total_executions': totalExecutions,
        'successful_executions': successfulExecutions,
        'success_rate':
            totalExecutions > 0
                ? (successfulExecutions / totalExecutions) * 100
                : 0.0,
      };
    } catch (e, stackTrace) {
      _logger.e('Error getting task stats', error: e, stackTrace: stackTrace);
      return {
        'active_tasks': 0,
        'total_tasks': 0,
        'total_executions': 0,
        'successful_executions': 0,
        'success_rate': 0.0,
      };
    }
  }
}

/// Global task handlers storage
/// This is used to bridge the top-level function with the service instance
Map<String, Function()> _globalTaskHandlers = {};

/// Global callback dispatcher for workmanager
/// This function must be a top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Log task execution
      print('Executing background task: $taskName');

      // Execute the registered task handler
      if (_globalTaskHandlers.containsKey(taskName)) {
        await _globalTaskHandlers[taskName]!();
        print('Background task completed: $taskName');
        return Future.value(true);
      } else {
        print('No handler found for background task: $taskName');
        return Future.value(false);
      }
    } catch (e) {
      print('Background task failed: $taskName - $e');
      return Future.value(false);
    }
  });
}

/// Enhanced background task service with additional features
class EnhancedBackgroundTaskService extends BackgroundTaskService {
  EnhancedBackgroundTaskService({
    super.workmanager,
    required super.cacheService,
    super.logger,
  });

  /// Register a task with custom configuration
  Future<void> registerTaskWithConfig({
    required String taskName,
    required Function() taskHandler,
    Duration? frequency,
    Map<String, dynamic>? inputData,
    BackgroundTaskConfig? config,
  }) async {
    try {
      // Apply configuration constraints
      final constraints =
          config != null
              ? Constraints(
                networkType: _mapNetworkConstraint(config.constraints),
                requiresCharging:
                    config.constraints ==
                    BackgroundTaskConstraints.requiresCharging,
                requiresDeviceIdle:
                    config.constraints ==
                    BackgroundTaskConstraints.requiresDeviceIdle,
              )
              : Constraints(
                networkType: NetworkType.connected,
                requiresCharging: false,
                requiresDeviceIdle: false,
              );

      // Store task handler with retry logic
      final wrappedHandler = () async {
        int retryCount = 0;
        final maxRetries = config?.maxRetries ?? 3;

        while (retryCount < maxRetries) {
          try {
            await taskHandler();
            return;
          } catch (e) {
            retryCount++;
            if (retryCount < maxRetries) {
              await Future.delayed(
                config?.retryDelay ?? const Duration(seconds: 30),
              );
            } else {
              rethrow;
            }
          }
        }
      };

      _taskHandlers[taskName] = wrappedHandler;
      _globalTaskHandlers[taskName] = wrappedHandler;

      // Register with workmanager using constraints
      if (frequency != null) {
        await _workmanager.registerPeriodicTask(
          taskName,
          taskName,
          frequency: frequency,
          inputData: inputData,
          constraints: constraints,
        );
      } else {
        await _workmanager.registerOneOffTask(
          taskName,
          taskName,
          inputData: inputData,
          constraints: constraints,
        );
      }

      // Create and cache task info
      final taskInfo = BackgroundTaskInfo(
        taskName: taskName,
        frequency: frequency,
        inputData: inputData,
        nextExecution: frequency != null ? DateTime.now().add(frequency) : null,
        isActive: true,
      );

      _registeredTasks[taskName] = taskInfo;
      await _cacheTaskInfo(taskInfo);

      _logger.i('Enhanced background task registered: $taskName');
    } catch (e, stackTrace) {
      _logger.e(
        'Error registering enhanced background task: $taskName',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Map background task constraints to workmanager network type
  NetworkType _mapNetworkConstraint(BackgroundTaskConstraints constraints) {
    switch (constraints) {
      case BackgroundTaskConstraints.requiresNetworkConnected:
        return NetworkType.connected;
      case BackgroundTaskConstraints.requiresNetworkUnmetered:
        return NetworkType.unmetered;
      case BackgroundTaskConstraints.none:
      case BackgroundTaskConstraints.requiresCharging:
      case BackgroundTaskConstraints.requiresDeviceIdle:
      case BackgroundTaskConstraints.requiresStorageNotLow:
      default:
        return NetworkType.not_required;
    }
  }
}
