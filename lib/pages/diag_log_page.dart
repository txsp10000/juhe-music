import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/toast.dart';

class DiagLogPage extends StatefulWidget {
  const DiagLogPage({super.key});

  @override
  State<DiagLogPage> createState() => _DiagLogPageState();
}

class _DiagLogPageState extends State<DiagLogPage> {
  static const _channel = MethodChannel('com.miaomiao.music/diag');

  String _content = '正在读取...';
  String _path = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await _channel.invokeMethod<String>('read');
      final path = await _channel.invokeMethod<String>('path');
      if (!mounted) return;
      setState(() {
        _content = (text == null || text.isEmpty) ? '(日志为空)' : text;
        _path = path ?? '';
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _content = '读取失败: ${e.message}');
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _content = '原生诊断通道未就绪');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断日志'),
        backgroundColor: const Color(0xFF171B26),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: '复制全部',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _content));
              Toast.show(context, '已复制到剪贴板');
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            tooltip: '刷新',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 22),
            tooltip: '清空',
            onPressed: () async {
              await _channel.invokeMethod('clear');
              await _load();
              if (mounted) Toast.show(context, '已清空');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_path.isNotEmpty)
            Container(
              width: double.infinity,
              color: const Color(0xFF171B26),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SelectableText(
                _path,
                style: const TextStyle(color: Color(0xFF8A93A6), fontSize: 11),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  height: 1.5,
                  fontFamily: 'Menlo',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
