import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/device/local_network_address_service.dart';
import '../../../../core/device/network_interface_candidate.dart';

class LocalIpSelectionDialog extends StatefulWidget {
  const LocalIpSelectionDialog({
    super.key,
    required this.candidates,
    required this.localNetworkAddressService,
    required this.onConfirm,
  });

  final List<NetworkInterfaceCandidate> candidates;
  final LocalNetworkAddressService localNetworkAddressService;
  final ValueChanged<String> onConfirm;

  @override
  State<LocalIpSelectionDialog> createState() => _LocalIpSelectionDialogState();
}

class _LocalIpSelectionDialogState extends State<LocalIpSelectionDialog> {
  late List<NetworkInterfaceCandidate> _candidates;
  String? _selectedIp;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _candidates = List.of(widget.candidates);
    _selectedIp = _initialSelection();
  }

  String? _initialSelection() {
    final savedIp = widget.localNetworkAddressService.selectedIp;
    if (savedIp != null &&
        _candidates.any((candidate) => candidate.address == savedIp)) {
      return savedIp;
    }
    return _candidates.isNotEmpty ? _candidates.first.address : null;
  }

  Future<void> _refreshCandidates() async {
    setState(() {
      _isRefreshing = true;
    });

    final refreshed =
        await widget.localNetworkAddressService.refreshCandidates();
    if (!mounted) {
      return;
    }

    setState(() {
      _candidates = refreshed;
      _isRefreshing = false;
      if (_selectedIp == null ||
          !_candidates.any((candidate) => candidate.address == _selectedIp)) {
        _selectedIp = _initialSelection();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择局域网 IP'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '检测到多个网络接口，请选择客户端应使用的服务端 IP 地址。',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppTheme.lightSecondaryText,
              ),
            ),
            const SizedBox(height: 16),
            if (_candidates.isEmpty)
              const Text('未检测到可用 IP，请刷新网卡列表后重试。')
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final candidate in _candidates)
                        RadioListTile<String>(
                          value: candidate.address,
                          groupValue: _selectedIp,
                          onChanged: (value) {
                            setState(() {
                              _selectedIp = value;
                            });
                          },
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
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isRefreshing ? null : _refreshCandidates,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('刷新网卡列表'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedIp == null
              ? null
              : () {
                  widget.onConfirm(_selectedIp!);
                  Navigator.of(context).pop(true);
                },
          child: const Text('确认并启动'),
        ),
      ],
    );
  }
}

Future<bool?> showLocalIpSelectionDialog({
  required BuildContext context,
  required List<NetworkInterfaceCandidate> candidates,
  required LocalNetworkAddressService localNetworkAddressService,
  required ValueChanged<String> onConfirm,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return LocalIpSelectionDialog(
        candidates: candidates,
        localNetworkAddressService: localNetworkAddressService,
        onConfirm: onConfirm,
      );
    },
  );
}
