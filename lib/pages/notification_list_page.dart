import 'package:flutter/material.dart';
import '../models/notification_item.dart';
import '../services/notification_service.dart';
import '../services/app_service.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../utils/permission_helper.dart';
import '../widgets/notification_card.dart';
import '../widgets/empty_notification_view.dart';
import 'dart:async';

class NotificationListPage extends StatefulWidget {
  @override
  _NotificationListPageState createState() => _NotificationListPageState();
}

class _NotificationListPageState extends State<NotificationListPage>
    with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  final AppService _appService = AppService();
  final PermissionService _permissionService = PermissionService();
  final SettingsService _settingsService = SettingsService();
  StreamSubscription? _notificationSubscription;
  List<NotificationItem> _notifications = [];
  List<NotificationItem> _filteredNotifications = [];
  bool _hasPermission = false;
  bool _hasNotificationPermission = false;
  double _cardSizeScale = 1.0;

  // 初始化为当天日期
  DateTime _todayStart = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 设置今天的开始时间（凌晨）
    _updateTimeInfo();
    // 加载卡片大小设置
    _loadCardSize();

    // 启动后自动请求通知权限
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
    });

    _initializeNotificationService();
  }

  // 更新时间信息
  void _updateTimeInfo() {
    setState(() {
      _todayStart = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
    });
  }

  // 加载卡片大小设置
  Future<void> _loadCardSize() async {
    try {
      final size = await _settingsService.getCardSize();
      setState(() {
        _cardSizeScale = size;
      });
    } catch (e) {
      print('加载卡片大小设置失败: $e');
    }
  }

  // 请求所有必需的权限
  Future<void> _requestPermissions() async {
    try {
      final permissionsMap =
          await _permissionService.checkAndRequestAllPermissions();

      setState(() {
        _hasNotificationPermission =
            permissionsMap['notificationPermission'] ?? false;
        _hasPermission =
            permissionsMap['notificationServicePermission'] ?? false;
      });

      // 如果获得了通知权限，但没有通知监听服务权限，则提示用户去设置
      if (_hasNotificationPermission && !_hasPermission) {
        // 使用延迟，确保UI已完全加载
        Future.delayed(Duration(milliseconds: 500), () {
          _openSettings();
        });
      }
    } catch (e) {
      print('请求权限时出错: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 更新时间信息
      _updateTimeInfo();

      // 应用回到前台，刷新通知状态
      _checkPermissionAndInitialize();

      // 检查通知权限
      _permissionService.hasNotificationPermission().then((hasPermission) {
        setState(() {
          _hasNotificationPermission = hasPermission;
        });
      });

      // 从设置页面返回时，重新加载卡片大小设置
      _loadCardSize();
    } else if (state == AppLifecycleState.paused) {
      // 应用进入后台，确保数据保存
      if (_hasPermission) {
        // 无需额外操作，通知服务已在变更时保存数据
      }
    }
  }

  void _applyTodayFilter() {
    final DateTime todayEnd = _todayStart.add(Duration(days: 1));

    _filteredNotifications =
        _notifications.where((notification) {
          final notificationDate = DateTime.fromMillisecondsSinceEpoch(
            notification.postTime,
          );
          return notificationDate.isAfter(_todayStart) &&
              notificationDate.isBefore(todayEnd);
        }).toList();
  }

  Future<void> _initializeNotificationService() async {
    await _checkPermissionAndInitialize();

    // 同步选中的应用到原生端
    await _appService.syncSelectedAppsToNative();

    // 监听新通知
    _notificationSubscription = _notificationService.notificationStream.listen((
      notification,
    ) {
      setState(() {
        _notifications = List.from(_notificationService.notifications)
          ..sort((a, b) => b.postTime.compareTo(a.postTime));
        _applyTodayFilter();
      });
    });
  }

  Future<void> _checkPermissionAndInitialize() async {
    final hasPermission =
        await _permissionService.isNotificationServiceEnabled();

    setState(() {
      _hasPermission = hasPermission;
    });

    if (hasPermission) {
      await _notificationService.init();
      setState(() {
        _notifications = List.from(_notificationService.notifications)
          ..sort((a, b) => b.postTime.compareTo(a.postTime));
        _applyTodayFilter();
      });
    }
  }

  // 导航到统计页面
  void _navigateToStatistics() {
    Navigator.pushNamed(context, '/statistics');
  }

  // 导航到设置页面
  void _navigateToSettings() async {
    await Navigator.pushNamed(context, '/settings');
    // 从设置页面返回时，重新加载卡片大小设置
    _loadCardSize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('今日通知'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _checkPermissionAndInitialize,
          ),
          IconButton(
            icon: Icon(Icons.bar_chart),
            onPressed: _navigateToStatistics,
            tooltip: '查看统计',
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: _navigateToSettings,
            tooltip: '设置',
          ),
        ],
      ),
      body:
          !_hasPermission
              ? _buildPermissionRequest()
              : _buildNotificationList(),
    );
  }

  Widget _buildPermissionRequest() {
    return PermissionHelper.buildPermissionRequestView(
      hasNotificationPermission: _hasNotificationPermission,
      hasNotificationServicePermission: _hasPermission,
      onRequestPermission: _requestPermissions,
      onOpenSettings: _openSettings,
    );
  }

  Widget _buildNotificationList() {
    if (_filteredNotifications.isEmpty) {
      return EmptyNotificationView(message: '今日暂无通知');
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '今日通知（${_filteredNotifications.length}）',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                icon: Icon(Icons.bar_chart),
                label: Text('查看所有统计'),
                onPressed: _navigateToStatistics,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredNotifications.length,
            itemBuilder: (context, index) {
              final notification = _filteredNotifications[index];
              return NotificationCard(
                notification: notification,
                showDeleteButton: false, // 不显示删除按钮
                cardStyle: NotificationCardStyle.large, // 使用大型卡片样式
                sizeScale: _cardSizeScale, // 设置卡片大小
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openSettings() async {
    await _permissionService.openNotificationServiceSettings();
  }
}
