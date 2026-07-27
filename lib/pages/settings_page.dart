import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = SettingsService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: const Color(0xFF171B26),
        elevation: 0,
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              '音质选择',
              style: TextStyle(
                color: Color(0xFF6890F9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...AudioQuality.values.map((q) => _buildQualityTile(q)),
        ],
      ),
    );
  }

  Widget _buildQualityTile(AudioQuality q) {
    final isSelected = _settings.quality == q;
    return ListTile(
      title: Text(
        q.label,
        style: TextStyle(
          color: isSelected ? const Color(0xFF6890F9) : Colors.white,
          fontSize: 15,
        ),
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: Color(0xFF6890F9), size: 22)
          : null,
      onTap: () async {
        await _settings.setQuality(q);
        setState(() {});
      },
    );
  }
}