import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/device/device_info_service.dart';
import '../../../../core/profile/device_identity_store.dart';
import '../../domain/server_device_identity_service.dart';

class ServerDeviceIdentityCard extends StatefulWidget {
  const ServerDeviceIdentityCard({super.key});

  @override
  State<ServerDeviceIdentityCard> createState() =>
      _ServerDeviceIdentityCardState();
}

class _ServerDeviceIdentityCardState extends State<ServerDeviceIdentityCard> {
  late final DeviceIdentityStore _identityStore;
  late final ServerDeviceIdentityService _identityService;
  late final DeviceInfoService _deviceInfoService;

  String? _deviceName;
  String? _physicalDeviceId;
  String? _avatarPath;
  String? _displayAlias;
  String? _hostDeviceId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _identityStore = DeviceIdentityStore(keyValueStore: ServiceLocator.keyValueStore);
    _identityService = ServiceLocator.serverDeviceIdentityService;
    _deviceInfoService = ServiceLocator.deviceInfoService;
    _avatarPath = _identityStore.avatarPath;
    _displayAlias = _identityStore.displayAlias;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final info = await _deviceInfoService.getDeviceInfo();
      final host = await _identityService.resolveHostDevice();
      await _identityService.syncFromHostRecord();
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceName = info.deviceName;
        _physicalDeviceId = info.deviceId;
        _hostDeviceId = host?.deviceId;
        _displayAlias = _identityStore.displayAlias ?? host?.label;
        _avatarPath = _identityStore.avatarPath;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
    }
  }

  String get _resolvedDisplayName {
    final alias = _displayAlias?.trim();
    if (alias != null && alias.isNotEmpty) {
      return alias;
    }
    final hardwareName = _deviceName?.trim();
    if (hardwareName != null && hardwareName.isNotEmpty) {
      return hardwareName;
    }
    return '本机';
  }

  String get _deviceIdSummary {
    final id = (_hostDeviceId ?? _physicalDeviceId)?.trim();
    if (id == null || id.isEmpty) {
      return '物理 ID: 未注册';
    }
    if (id.length <= 8) {
      return '物理 ID: $id';
    }
    return '物理 ID: ${id.substring(0, 4)}…${id.substring(id.length - 4)}';
  }

  Future<void> _pickAvatar() async {
    const typeGroup = XTypeGroup(
      label: 'images',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    final path = file?.path;
    if (path == null || path.trim().isEmpty) {
      return;
    }
    try {
      await _identityService.setAvatarFromPath(path);
      if (!mounted) {
        return;
      }
      setState(() => _avatarPath = _identityStore.avatarPath);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('头像保存失败：$error')),
      );
    }
  }

  Future<void> _clearAvatar() async {
    try {
      await _identityService.clearAvatar();
      if (!mounted) {
        return;
      }
      setState(() => _avatarPath = null);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清除头像失败：$error')),
      );
    }
  }

  Future<void> _editDisplayAlias() async {
    final controller = TextEditingController(text: _displayAlias ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('设置名称'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 32,
            decoration: const InputDecoration(hintText: '例如：客厅 NAS'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (saved != true || !mounted) {
      controller.dispose();
      return;
    }
    try {
      await _identityService.updateDisplayAlias(controller.text);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _displayAlias = _identityStore.displayAlias);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('名称保存失败：$error')),
        );
      }
    }
    controller.dispose();
  }

  Future<void> _showIdentityOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('设置头像'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickAvatar();
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('设置名称'),
                onTap: () {
                  Navigator.of(context).pop();
                  _editDisplayAlias();
                },
              ),
              if (_avatarPath != null)
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('恢复默认头像'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _clearAvatar();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: _loading ? null : _showIdentityOptions,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.successContainer,
                backgroundImage:
                    _avatarPath != null ? FileImage(File(_avatarPath!)) : null,
                child: _avatarPath == null
                    ? const Icon(Icons.dns_rounded, color: AppTheme.accentColor)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '设备身份',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.lightCardForeground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _loading ? '加载中…' : _resolvedDisplayName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.lightSecondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.lightSecondaryText),
            ],
          ),
        ),
      ),
    );
  }
}
