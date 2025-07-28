
## Note: Currently in development.

# FLuxBD Flow Kit

A comprehensive Flutter package for Firebase Cloud Messaging (FCM), Local Notifications, Background Tasks, Deep Linking & Navigation routing.

## Features

- 🔥 **Firebase Cloud Messaging (FCM)**: Complete FCM integration with background/foreground message handling
- 📱 **Local Notifications**: Rich local notifications with scheduling and management
- ⚡ **Background Tasks**: Robust background task execution with retry mechanisms
- 🔗 **Deep Linking**: Universal and custom deep link handling
- 🧭 **Navigation**: Advanced navigation with history and route management

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  fldb_flow_kit: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## Quick Start

### 1. Basic Setup

```dart
import 'package:fldb_flow_kit/fldb_flow_kit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  final cacheService = CacheService();
  await cacheService.initialize();
  
  final navigationService = NavigationService(cacheService: cacheService);
  await navigationService.initialize();
  
  runApp(MyApp(navigationService: navigationService));
}
```

### 2. Cache Service Usage

```dart
final cacheService = CacheService();
await cacheService.initialize();

// Store data with TTL
await cacheService.set('user_data', {'name': 'John', 'age': 30}, 
    ttl: Duration(hours: 1));

// Retrieve data
final userData = await cacheService.get<Map<String, dynamic>>('user_data');

// Check existence
final exists = await cacheService.containsKey('user_data');

// Get cache statistics
final stats = await cacheService.getStats();
print('Hit rate: ${stats.hitRate}%');
```

### 3. Background Tasks

```dart
final backgroundTaskService = BackgroundTaskService(cacheService: cacheService);
await backgroundTaskService.initialize();

// Register a simple task
await backgroundTaskService.registerTask(
  taskName: 'sync_data',
  taskHandler: () async {
    // Your background task logic
    print('Syncing data...');
    await syncDataWithServer();
  },
);

// Register a periodic task
await backgroundTaskService.registerPeriodicTask(
  taskName: 'daily_cleanup',
  taskHandler: () async {
    await performDailyCleanup();
  },
  frequency: Duration(days: 1),
);

// Enhanced task with retry configuration
final enhancedService = EnhancedBackgroundTaskService(
  cacheService: cacheService,
);

await enhancedService.registerTaskWithConfig(
  taskName: 'critical_sync',
  taskHandler: () async {
    await criticalDataSync();
  },
  frequency: Duration(hours: 6),
  config: BackgroundTaskConfig(
    maxRetries: 5,
    retryDelay: Duration(minutes: 5),
    constraints: BackgroundTaskConstraints.requiresNetworkConnected,
  ),
);
```

### 4. Firebase Cloud Messaging

```dart
final fcmService = FCMService(
  cacheService: cacheService,
  showForegroundNotifications: true,
);
await fcmService.initialize();

// Get FCM token
final token = await fcmService.getToken();
print('FCM Token: $token');

// Subscribe to topics
await fcmService.subscribeToTopic('news');
await fcmService.subscribeToTopic('updates');

// Handle foreground messages
fcmService.onForegroundMessage((message) {
  print('Received foreground message: ${message['title']}');
});

// Handle background messages
fcmService.onBackgroundMessage((message) async {
  // Process background message
  await processBackgroundMessage(message);
});

// Handle token refresh
fcmService.onTokenRefresh((newToken) {
  print('Token refreshed: $newToken');
  // Send new token to your server
});
```

### 5. Local Notifications

```dart
final localNotificationService = LocalNotificationService(
  cacheService: cacheService,
);
await localNotificationService.initialize();

// Show immediate notification
await localNotificationService.showNotification(
  title: 'Hello!',
  body: 'This is a test notification',
  payload: 'custom_data',
);

// Schedule a notification
await localNotificationService.scheduleNotification(
  id: 1,
  title: 'Reminder',
  body: 'Don\'t forget to check your tasks',
  scheduledDate: DateTime.now().add(Duration(hours: 2)),
  payload: 'reminder_data',
);

// Schedule periodic notifications
await localNotificationService.schedulePeriodicNotification(
  id: 2,
  title: 'Daily Reminder',
  body: 'Time for your daily check-in',
  interval: Duration(days: 1),
);

// Handle notification taps
localNotificationService.onNotificationTap((payload) {
  print('Notification tapped with payload: $payload');
  // Navigate to specific screen based on payload
});
```

### 6. Deep Linking

```dart
final deepLinkService = DeepLinkService(
  cacheService: cacheService,
  config: DeepLinkConfig(
    scheme: 'myapp',
    host: 'example.com',
    allowedDomains: ['example.com', 'app.example.com'],
  ),
);
await deepLinkService.initialize();

// Generate deep links
final deepLink = deepLinkService.generateDeepLink(
  '/product/123',
  parameters: {'ref': 'email', 'campaign': 'summer_sale'},
);
print('Generated link: $deepLink');

// Register deep link handlers
deepLinkService.registerDeepLinkHandler(
  'myapp://example.com/product/*',
  (link, parameters) async {
    final productId = parameters['pathSegments'][1];
    await navigateToProduct(productId);
  },
);

// Listen for incoming deep links
deepLinkService.listenForDeepLinks((link) {
  print('Received deep link: $link');
});

// Validate deep links
final isValid = deepLinkService.validateDeepLink('myapp://example.com/valid');
```

### 7. Navigation Service

```dart
final navigationService = NavigationService(
  cacheService: cacheService,
  config: NavigationConfig(
    initialRoute: '/',
    enableLogging: true,
    routes: {
      '/': (context, params) => HomeScreen(),
      '/profile': (context, params) => ProfileScreen(),
      '/settings': (context, params) => SettingsScreen(),
    },
  ),
);
await navigationService.initialize();

// Use in your app
class MyApp extends StatelessWidget {
  final NavigationService navigationService;
  
  MyApp({required this.navigationService});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: navigationService.router,
    );
  }
}

// Navigate programmatically
await navigationService.navigateTo('/profile', 
    parameters: {'userId': '123'});

// Navigate and replace
await navigationService.navigateAndReplace('/login');

// Navigate and clear stack
await navigationService.navigateAndClearStack('/home');

// Check navigation history
final history = navigationService.getNavigationHistory();
print('Navigation history: ${history.length} entries');
```

## Advanced Usage

### Custom Cache Configuration

```dart
final cacheService = CacheService(
  config: CacheConfig(
    maxSize: 5000,
    defaultTtl: Duration(hours: 2),
    enableLogging: true,
    evictionPolicy: CacheEvictionPolicy.lru,
  ),
);
```

### Error Handling

```dart
try {
  await backgroundTaskService.registerTask(
    taskName: 'risky_task',
    taskHandler: () async {
      throw Exception('Task failed');
    },
  );
} catch (e) {
  print('Failed to register task: $e');
}
```

### Performance Monitoring

```dart
// Cache statistics
final cacheStats = await cacheService.getStats();
print('Cache hit rate: ${cacheStats.hitRate}%');
print('Cache size: ${cacheStats.totalSize}/${cacheStats.maxSize}');

// Background task statistics
final taskStats = await backgroundTaskService.getTaskStats();
print('Active tasks: ${taskStats['active_tasks']}');
print('Success rate: ${taskStats['success_rate']}%');

// Deep link statistics
final linkStats = deepLinkService.getLinkStats();
print('Total links processed: ${linkStats['total_links']}');
print('Success rate: ${linkStats['success_rate']}%');
```

## Integration Examples

### Complete App Setup

```dart
class AppServices {
  late final CacheService cacheService;
  late final NavigationService navigationService;
  late final BackgroundTaskService backgroundTaskService;
  late final FCMService fcmService;
  late final LocalNotificationService localNotificationService;
  late final DeepLinkService deepLinkService;
  
  Future<void> initialize() async {
    // Initialize cache service first
    cacheService = CacheService();
    await cacheService.initialize();
    
    // Initialize other services
    navigationService = NavigationService(cacheService: cacheService);
    await navigationService.initialize();
    
    backgroundTaskService = BackgroundTaskService(cacheService: cacheService);
    await backgroundTaskService.initialize();
    
    fcmService = FCMService(cacheService: cacheService);
    await fcmService.initialize();
    
    localNotificationService = LocalNotificationService(cacheService: cacheService);
    await localNotificationService.initialize();
    
    deepLinkService = DeepLinkService(cacheService: cacheService);
    await deepLinkService.initialize();
    
    // Set up integrations
    _setupIntegrations();
  }
  
  void _setupIntegrations() {
    // Deep link to navigation integration
    deepLinkService.registerDeepLinkHandler(
      'myapp://example.com/*',
      (link, parameters) async {
        final route = parameters['path'];
        await navigationService.navigateTo(route, parameters: parameters);
      },
    );
    
    // FCM to local notification integration
    fcmService.onForegroundMessage((message) async {
      await localNotificationService.showNotification(
        title: message['title'] ?? 'New Message',
        body: message['body'] ?? '',
        payload: jsonEncode(message),
      );
    });
  }
  
  void dispose() {
    deepLinkService.dispose();
    localNotificationService.dispose();
    fcmService.dispose();
    backgroundTaskService.dispose();
    navigationService.dispose();
    cacheService.dispose();
  }
}
```

## Testing

The package includes comprehensive tests. Run them with:

```bash
flutter test
```

Example test:

```dart
void main() {
  group('CacheService Tests', () {
    late CacheService cacheService;
    
    setUp(() {
      cacheService = CacheService();
    });
    
    test('should cache and retrieve data', () async {
      await cacheService.initialize();
      
      await cacheService.set('key', 'value');
      final result = await cacheService.get<String>('key');
      
      expect(result, equals('value'));
    });
  });
}
```

## Performance Tips

1. **Cache Optimization**: Use appropriate TTL values and eviction policies
2. **Background Tasks**: Avoid heavy operations in task handlers
3. **Memory Management**: Always dispose services when done
4. **Network Efficiency**: Cache FCM tokens and minimize API calls

## Troubleshooting

### Common Issues

1. **Cache not persisting**: Ensure `initialize()` is called before use
2. **Background tasks not executing**: Check platform-specific background execution limits
3. **FCM not receiving messages**: Verify Firebase configuration and permissions
4. **Deep links not working**: Check URL scheme configuration in platform files

### Debug Mode

Enable logging for debugging:

```dart
final cacheService = CacheService(
  config: CacheConfig(enableLogging: true),
  logger: Logger(level: Level.debug),
);
```

## Platform Setup

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### iOS

Add to `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>background-fetch</string>
    <string>background-processing</string>
</array>
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Create an issue on GitHub
- Check the documentation
- Review the example code

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and updates.
