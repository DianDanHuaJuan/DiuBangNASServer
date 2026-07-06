import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/device/local_network_address_service.dart';
import '../../../../core/device/network_interface_candidate.dart';

class NetworkSettingsCard extends StatefulWidget {
  const NetworkSettingsCard({super.key});

  @override
  State<NetworkSettingsCard> createState() => _NetworkSettingsCardState();
}

class _NetworkSettingsCardState extends State<NetworkSettingsCard> {
  late final LocalNetworkAddressService _networkService;
  List<NetworkInterfaceCandidate> _candidates = const [];
  String? _selectedIp;
  bool _isRefreshing = false;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _networkService = ServiceLocator.localNetworkAddressService;
    _selectedIp = _networkService.selectedIp;
    _candidates = _networkService.candidates;
    _networkService.addListener(_syncFromService);
    if (_candidates.isEmpty) {
      unawaited(_refreshCandidates());
    }
  }

  @override
  void dispose() {
    _networkService.removeListener(_syncFromService);
    super.dispose();
  }

  void _syncFromService() {
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedIp = _networkService.selectedIp;
      _candidates = _networkService.candidates;
    });
  }

  Future<void> _refreshCandidates() async {
    setState(() {
      _isRefreshing = true;
    });

    final refreshed = await _networkService.refreshCandidates();
    if (!mounted) {
      return;
    }

    setState(() {
      _candidates = refreshed;
      _isRefreshing = false;
      if (_selectedIp == null ||
          !_candidates.any((candidate) => candidate.address == _selectedIp)) {
        _selectedIp = _networkService.selectedIp ?? _defaultSelection();
      }
    });
  }

  String? _defaultSelection() {
    return _candidates.isNotEmpty ? _candidates.first.address : null;
  }

  Future<void> _applySelection(String ip) async {
    if (_isApplying || ip == _networkService.selectedIp) {
      return;
    }

    setState(() {
      _isApplying = true;
      _selectedIp = ip;
    });

    try {
      final wasRunning = ServiceLocator.isServerRunning;
      await ServiceLocator.applyLocalNetworkAddressChange(ip);
      if (!mounted) {
        return;
      }

      final message = wasRunning ? '局域网 IP 已更新，服务已重启。' : '局域网 IP 已保存。';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新局域网 IP 失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveIp = _networkService.effectiveIp;
    final isRunning = ServiceLocator.isServerRunning;
    final statusText = effectiveIp == null
        ? '尚未选择'
        : isRunning
        ? '当前服务使用：$effectiveIp'
        : '已选择，启动服务后生效：$effectiveIp';

    return Container(
      constraints: const BoxConstraints(minHeight: 312),
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.lightDivider, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBright,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lan_outlined,
                  size: 22,
                  color: AppTheme.accentColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '网络设置',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.lightCardForeground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusText,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.lightSecondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '选择客户端连接时使用的服务端 IP。虚拟网卡与 VPN 接口也会列出，请按实际网络环境选择。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppTheme.lightSecondaryText,
            ),
          ),
          const SizedBox(height: 16),
          if (_candidates.isEmpty)
            const Text('暂无可用网络接口')
          else
            ..._candidates.map((candidate) {
              return RadioListTile<String>(
                value: candidate.address,
                groupValue: _selectedIp,
                onChanged: _isApplying
                    ? null
                    : (value) {
                        if (value != null) {
                          unawaited(_applySelection(value));
                        }
                      },
                activeColor: AppTheme.accentColor,
                title: Text(
                  candidate.address,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${candidate.interfaceName} · '
                  '${candidate.isPrivate ? '私有地址' : '公有地址'}',
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
              );
            }),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _isRefreshing || _isApplying ? null : _refreshCandidates,
            style: TextButton.styleFrom(foregroundColor: AppTheme.accentColor),
            icon: _isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: const Text('刷新网卡列表'),
          ),
        ],
      ),
    );
  }
}
