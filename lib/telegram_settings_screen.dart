import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'monitor_service.dart';

class TelegramSettingsScreen extends StatefulWidget {
  const TelegramSettingsScreen({super.key});

  @override
  State<TelegramSettingsScreen> createState() => _TelegramSettingsScreenState();
}

class _TelegramSettingsScreenState extends State<TelegramSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _chatIdController = TextEditingController();

  bool _obscureToken = true;
  bool _syncEnabled = true;
  bool _isTesting = false;
  bool _isSaving = false;
  bool _isSyncing = false;
  String? _testResult;
  bool _testSuccess = false;

  int _pendingTexts = 0;
  int _pendingPhotos = 0;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('telegram_bot_token') ?? '';
    final savedChatId = prefs.getString('telegram_chat_id') ?? '';
    final savedEnabled = prefs.getBool('telegram_sync_enabled') ?? false;

    final nativeConfig = await MonitorService.getTelegramConfig();
    final token = savedToken.isNotEmpty
        ? savedToken
        : (nativeConfig['botToken'] as String? ?? '');
    final chatId = savedChatId.isNotEmpty
        ? savedChatId
        : (nativeConfig['chatId'] as String? ?? '');
    final enabled = prefs.containsKey('telegram_sync_enabled')
        ? savedEnabled
        : (nativeConfig['enabled'] as bool? ?? false);

    final stats = await MonitorService.getDatabaseStats();

    if (mounted) {
      setState(() {
        _tokenController.text = token;
        _chatIdController.text = chatId;
        _syncEnabled = enabled;
        _pendingTexts = stats['textCount'] ?? 0;
        _pendingPhotos = stats['screenshotCount'] ?? 0;
      });
    }
  }

  Future<void> _pasteToController(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        controller.text = data.text!.trim();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã dán từ bộ nhớ tạm'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bộ nhớ tạm đang trống'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    final token = _tokenController.text.trim();
    final chatId = _chatIdController.text.trim();

    if (token.isEmpty || chatId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập cả BOT_TOKEN và CHAT_ID trước khi test'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final res = await MonitorService.testTelegramConnection(
      botToken: token,
      chatId: chatId,
    );

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = res['success'] == true;
        _testResult =
            (res['message'] as String?) ??
            (_testSuccess ? 'Kết nối thành công!' : 'Thất bại');
      });
    }
  }

  Future<void> _saveConfig() async {
    final token = _tokenController.text.trim();
    final chatId = _chatIdController.text.trim();

    setState(() => _isSaving = true);

    // Lưu vào SharedPreferences của Flutter
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('telegram_bot_token', token);
    await prefs.setString('telegram_chat_id', chatId);
    await prefs.setBool('telegram_sync_enabled', _syncEnabled);

    // Đồng bộ xuống native Android
    await MonitorService.saveTelegramConfig(
      botToken: token,
      chatId: chatId,
      enabled: _syncEnabled,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu cấu hình Telegram thành công!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    final res = await MonitorService.syncTelegramNow();
    final stats = await MonitorService.getDatabaseStats();

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _pendingTexts = stats['textCount'] ?? 0;
        _pendingPhotos = stats['screenshotCount'] ?? 0;
      });

      final texts = res['sentTexts'] ?? 0;
      final photos = res['sentPhotos'] ?? 0;
      final error = (res['error'] as String?) ?? '';

      if (error.isNotEmpty && texts == 0 && photos == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đồng bộ thất bại: $error'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã gửi $photos ảnh và $texts mục text lên Telegram, dọn sạch bộ nhớ Máy 1.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu hình Telegram Máy 2'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới trạng thái',
            onPressed: _loadConfig,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thông báo bảo mật
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.security, color: Colors.blue.shade800, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Token và Chat ID được lưu trực tiếp trên thiết bị này và không bao giờ chia sẻ ra ngoài. Bạn chỉ cần tự nhập 1 lần duy nhất.',
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Thẻ bật/tắt gửi tự động
              Card(
                elevation: 0,
                color: _syncEnabled
                    ? Colors.teal.shade50
                    : Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _syncEnabled
                        ? Colors.teal.shade300
                        : Colors.grey.shade300,
                  ),
                ),
                child: SwitchListTile(
                  title: const Text(
                    'Tự động gửi lên Telegram',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    _syncEnabled
                        ? 'Ảnh và phím gõ sẽ tự động gửi về Telegram. Sau khi gửi thành công sẽ xoá ngay file ảnh và SQLite trên máy này.'
                        : 'Đang tạm dừng gửi. Dữ liệu sẽ lưu tạm trong máy.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  value: _syncEnabled,
                  onChanged: (val) {
                    setState(() => _syncEnabled = val);
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Ô 1: BOT_TOKEN
              const Text(
                '1. Telegram Bot Token',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Lấy từ @BotFather trên Máy 2 (dạng: 7891234567:AAF_...)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _tokenController,
                obscureText: _obscureToken,
                decoration: InputDecoration(
                  hintText: 'Dán BOT_TOKEN vào đây',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          _obscureToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        tooltip: _obscureToken ? 'Hiện token' : 'Ẩn token',
                        onPressed: () {
                          setState(() => _obscureToken = !_obscureToken);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.paste_outlined),
                        tooltip: 'Dán từ clipboard',
                        onPressed: () => _pasteToController(_tokenController),
                      ),
                      if (_tokenController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            setState(() => _tokenController.clear());
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Ô 2: CHAT_ID
              const Text(
                '2. Telegram Chat ID',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Lấy từ @userinfobot trên Máy 2 (dạng dãy số: 1234567890)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _chatIdController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Dán CHAT_ID vào đây',
                  prefixIcon: const Icon(Icons.chat_bubble_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.paste_outlined),
                        tooltip: 'Dán từ clipboard',
                        onPressed: () => _pasteToController(_chatIdController),
                      ),
                      if (_chatIdController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            setState(() => _chatIdController.clear());
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Kết quả kiểm tra kết nối nếu có
              if (_testResult != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _testSuccess
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _testSuccess
                          ? Colors.green.shade300
                          : Colors.red.shade300,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _testSuccess
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: _testSuccess
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            color: _testSuccess
                                ? Colors.green.shade900
                                : Colors.red.shade900,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Hai nút thao tác chính: Test kết nối & Lưu
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isTesting ? null : _testConnection,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(_isTesting ? 'Đang test...' : 'Test kết nối'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveConfig,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_isSaving ? 'Đang lưu...' : 'Lưu cấu hình'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              const Divider(),
              const SizedBox(height: 12),

              // Thẻ dọn dẹp & Gửi bù dữ liệu chưa gửi
              Text(
                'Dữ liệu lưu tạm trên Máy 1',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Khi mất mạng, dữ liệu sẽ tạm giữ lại ở đây. Bấm nút bên dưới để gửi bù ngay lập tức.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📸 Ảnh chờ gửi: $_pendingPhotos ảnh',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '⌨️ Gõ phím chờ gửi: $_pendingTexts mục',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed:
                          (_isSyncing ||
                              (_pendingPhotos == 0 && _pendingTexts == 0))
                          ? null
                          : _syncNow,
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(_isSyncing ? 'Đang gửi...' : 'Gửi bù ngay'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Hướng dẫn nhanh cho người dùng
              Card(
                elevation: 0,
                color: Colors.amber.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.amber.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.tips_and_updates_outlined,
                            color: Colors.amber.shade900,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Lưu ý quan trọng trên Máy 2 (Telegram):',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '1. Sau khi tạo bot bằng @BotFather, bạn BẮT BUỘC phải bấm vào link bot (t.me/tên_bot) và nhấn nút START.\n'
                        '2. Nếu chưa nhấn START, Telegram sẽ chặn bot gửi tin nhắn và báo lỗi "chat not found".\n'
                        '3. Nhập xong Token và Chat ID, hãy bấm nút "Test kết nối" ở trên để kiểm tra trước.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
