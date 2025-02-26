import 'package:flutter/material.dart';
import '../models/notification_item.dart';
import '../services/notification_service.dart';
import 'dart:async';

class NotificationListPage extends StatefulWidget {
  @override
  _NotificationListPageState createState() => _NotificationListPageState();
}

class _NotificationListPageState extends State<NotificationListPage> with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  StreamSubscription? _notificationSubscription;
  List<NotificationItem> _notifications = [];
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeNotificationService();
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
      // 应用回到前台，刷新通知状态
      _checkPermissionAndInitialize();
    } else if (state == AppLifecycleState.paused) {
      // 应用进入后台，确保数据保存
      if (_hasPermission) {
        // 无需额外操作，通知服务已在变更时保存数据
      }
    }
  }

  Future<void> _initializeNotificationService() async {
    await _checkPermissionAndInitialize();
    
    // 监听新通知
    _notificationSubscription = _notificationService.notificationStream.listen((notification) {
      setState(() {
        _notifications = List.from(_notificationService.notifications);
      });
    });
  }

  Future<void> _checkPermissionAndInitialize() async {
    final hasPermission = await _notificationService.isNotificationServiceEnabled();
    
    setState(() {
      _hasPermission = hasPermission;
    });
    
    if (hasPermission) {
      await _notificationService.init();
      setState(() {
        _notifications = List.from(_notificationService.notifications);
      });
    }
  }

  Future<void> _openSettings() async {
    await _notificationService.openNotificationSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('通知监听器'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _checkPermissionAndInitialize,
          ),
          if (_hasPermission && _notifications.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep),
              onPressed: _showClearConfirmDialog,
            ),
        ],
      ),
      body: !_hasPermission 
          ? _buildPermissionRequest()
          : _buildNotificationList(),
    );
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            '需要通知访问权限',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            '请点击下方按钮，然后在系统设置中启用通知访问权限',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _openSettings,
            child: Text('打开设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList() {
    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              '暂无通知',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return Dismissible(
          key: Key(notification.key),
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Icon(Icons.delete, color: Colors.white),
          ),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            return await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('删除通知'),
                content: Text('确定要删除这条通知记录吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text('确定'),
                  ),
                ],
              ),
            );
          },
          onDismissed: (direction) {
            _notificationService.deleteNotification(notification.key);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('通知已删除')),
            );
          },
          child: Card(
            margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor,
                child: Text(
                  notification.appName.isNotEmpty ? notification.appName[0] : '?',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              title: Text(
                notification.title.isNotEmpty ? notification.title : '无标题',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification.text.isNotEmpty ? notification.text : '无内容'),
                  SizedBox(height: 4),
                  Text(
                    '应用: ${notification.appName}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  Text(
                    '时间: ${_formatTime(notification.postTime)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('删除通知'),
                      content: Text('确定要删除这条通知记录吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text('确定'),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirmed == true) {
                    _notificationService.deleteNotification(notification.key);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('通知已删除')),
                    );
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  Future<void> _showClearConfirmDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清空所有通知'),
        content: Text('确定要清空所有通知记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              _notificationService.clearNotifications();
              Navigator.of(context).pop();
            },
            child: Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
} 