import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../app/di/service_locator.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/device_registry/device_models.dart';
import '../../../../core/device_registry/device_store.dart';
import '../../../../core/device/mdns_runtime_status.dart';
import '../../../../core/device/system_status_cache.dart';
import '../../../../core/platform/app_platform.dart';
import '../../../../core/state/view_status.dart';
import '../widgets/local_ip_selection_dialog.dart';
import '../cubit/server_cubit.dart';
import '../cubit/server_state.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import 'backup_files_page.dart';
import 'device_management_page.dart';
import '../widgets/control_center_shell.dart';

class ServerManagementPage extends StatefulWidget {
  const ServerManagementPage({super.key});

  @override
  State<ServerManagementPage> createState() => _ServerManagementPageState();
}

class _ServerManagementPageState extends State<ServerManagementPage> {
  static const String _backgroundPermissionReminderDismissedKey =
      'background_permission_reminder_dismissed_v1';
  static const double _wideOverviewCardHeight = 520;

  bool _isBackgroundPermissionReminderDismissed = false;
  bool _isIpSelectionDialogVisible = false;
  late final SettingsCubit _settingsCubit;
  String _uiDeviceName = '';

  @override
  void initState() {
    super.initState();
    _settingsCubit = ServiceLocator.createSettingsCubit();
    _isBackgroundPermissionReminderDismissed =
        ServiceLocator.keyValueStore.getBool(
          _backgroundPermissionReminderDismissedKey,
        ) ??
        false;
    ServiceLocator.deviceStore.addListener(_onDeviceRegistryChanged);
    unawaited(_refreshUiDeviceName());
  }

  void _onDeviceRegistryChanged(StoredDeviceRecord device) {
    unawaited(_refreshUiDeviceName());
  }

  Future<void> _refreshUiDeviceName() async {
    final name =
        await ServiceLocator.serverDeviceIdentityService.resolveUiDeviceName();
    if (!mounted) {
      return;
    }
    setState(() => _uiDeviceName = name);
  }

  Future<void> _showIpSelectionDialog(
    BuildContext context,
    ServerState state,
  ) async {
    if (_isIpSelectionDialogVisible) {
      return;
    }

    _isIpSelectionDialogVisible = true;
    final cubit = context.read<ServerCubitImpl>();

    try {
      final confirmed = await showLocalIpSelectionDialog(
        context: context,
        candidates: state.pendingIpCandidates,
        localNetworkAddressService: ServiceLocator.localNetworkAddressService,
        onConfirm: (ip) {
          unawaited(cubit.confirmIpAndStartServer(ip));
        },
      );

      if (!mounted) {
        return;
      }

      if (confirmed != true) {
        cubit.cancelIpSelection();
      }
    } finally {
      _isIpSelectionDialogVisible = false;
    }
  }

  @override
  void dispose() {
    ServiceLocator.deviceStore.removeListener(_onDeviceRegistryChanged);
    _settingsCubit.close();
    super.dispose();
  }

  Future<void> _openAppManagementSettings() async {
    final opened = await ServiceLocator.batteryOptimizationService
        .openAppManagementSettings();

    if (!mounted || opened) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('无法直接打开系统设置，请手动前往 设置->应用->应用管理->当前APP->耗电管理'),
      ),
    );
  }

  Future<void> _dismissBackgroundPermissionReminder() async {
    await ServiceLocator.keyValueStore.setBool(
      _backgroundPermissionReminderDismissedKey,
      true,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isBackgroundPermissionReminderDismissed = true;
    });
  }

  bool get _shouldShowBackgroundPermissionReminder =>
      AppPlatform.supportsBatteryOptimizationControl &&
      !_isBackgroundPermissionReminderDismissed;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb >= 100 ? 1 : 2)}K';
    }
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1) {
      return '${gb.toStringAsFixed(gb >= 100 ? 1 : 2)}G';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 100 ? 1 : 2)}M';
  }

  String _formatUptime(Duration uptime) {
    if (uptime.inDays > 0) {
      return '${uptime.inDays}天${uptime.inHours % 24}小时';
    }
    if (uptime.inHours > 0) {
      return '${uptime.inHours}小时${uptime.inMinutes % 60}分';
    }
    if (uptime.inMinutes > 0) {
      return '${uptime.inMinutes}分';
    }
    return '0分';
  }

  String _getTemperatureDisplay(double temp) {
    if (temp <= 0) return '未知';
    if (temp < 40) return '低';
    if (temp < 60) return '正常';
    return '高';
  }

  Duration _currentUptime() {
    final startedAt = ServiceLocator.serverStartedAt;
    if (startedAt == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(startedAt);
  }

  String _formatLastUpdated(DateTime? updatedAt) {
    if (updatedAt == null) {
      return '--';
    }
    final hh = updatedAt.hour.toString().padLeft(2, '0');
    final mm = updatedAt.minute.toString().padLeft(2, '0');
    final ss = updatedAt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  String _formatBroadcastSummary(MdnsRuntimeStatus status) {
    if (status.isFailed) {
      return '不可用';
    }
    if (status.isActive) {
      return '已启用';
    }
    return '已禁用';
  }

  String _formatBroadcastDetails(MdnsRuntimeStatus status) {
    if (status.isFailed) {
      return status.details ?? '局域网发现不可用';
    }
    if (status.isActive) {
      return '局域网发现已激活';
    }
    return '等待服务启动';
  }

  Future<void> _showPairingQrDialog() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    String? pairingToken;
    try {
      pairingToken = await ServiceLocator.loadServerPairingToken();
    } catch (error) {
      if (!mounted) {
        return;
      }
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('生成 HTTPS 配对二维码失败：$error')),
      );
      return;
    }
    if (pairingToken == null || pairingToken.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('服务尚未生成 HTTPS 配对二维码，请稍后重试')),
      );
      return;
    }
    String? token = pairingToken;
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('HTTPS 配对二维码'),
              content: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('请在客户端登录页扫描此二维码，一次完成 HTTPS 配对并自动导入客户端凭据。'),
                      const SizedBox(height: 12),
                      Center(
                        child: QrImageView(
                          data: token!,
                          size: 280,
                          errorStateBuilder: (c, e) => const Text('无法生成二维码'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(dialogContext);
                    String? newToken;
                    try {
                      newToken = await ServiceLocator.loadServerPairingToken();
                    } catch (error) {
                      if (!dialogContext.mounted) return;
                      scaffoldMessenger.showSnackBar(
                        SnackBar(content: Text('刷新二维码失败：$error')),
                      );
                      return;
                    }
                    if (newToken == null || newToken.trim().isEmpty) {
                      if (!dialogContext.mounted) return;
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('服务尚未生成 HTTPS 配对二维码，请稍后重试')),
                      );
                      return;
                    }
                    setDialogState(() => token = newToken);
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新二维码'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cache = ServiceLocator.systemStatusCache;
    final currentSettings = ServiceLocator.currentServerSettings;

    return BlocConsumer<ServerCubitImpl, ServerState>(
      listener: (context, state) {
        if (state.serverStatus == ServerStatus.awaitingIpSelection &&
            state.pendingIpCandidates.isNotEmpty) {
          unawaited(_showIpSelectionDialog(context, state));
          return;
        }

        if (state.viewStatus == ViewStatus.failure &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('错误: ${state.errorMessage}')));
        }
      },
      builder: (context, state) {
        final isLoading = state.viewStatus == ViewStatus.loading;
        final isRunning = ServiceLocator.isServerRunning;
        final serviceChild = cache == null
            ? _buildServiceContent(
                displayIp: '服务未启动',
                port: currentSettings.port,
                isLoading: isLoading,
                isRunning: isRunning,
                cache: null,
              )
            : AnimatedBuilder(
                animation: cache,
                builder: (context, _) => _buildServiceContent(
                  displayIp: cache.localIp ?? '服务未启动',
                  port: currentSettings.port,
                  isLoading: isLoading,
                  isRunning: isRunning,
                  cache: cache,
                ),
              );

        return ControlCenterShell(
          serviceChild: serviceChild,
          backupFilesChild: const BackupFilesPage(),
          devicesChild: const DeviceManagementPage(),
          settingsChild: SettingsPage(settingsCubit: _settingsCubit),
        );
      },
    );
  }

  Widget _buildServiceContent({
    required String displayIp,
    required int port,
    required bool isLoading,
    required bool isRunning,
    required SystemStatusCache? cache,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > 1036
            ? 1036.0
            : constraints.maxWidth;
        final useTwoColumns = contentWidth >= 900;
        final cardSpacing = 24.0;
        final cardWidth = useTwoColumns
            ? (contentWidth - cardSpacing) / 2
            : contentWidth;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_shouldShowBackgroundPermissionReminder) ...[
                    _buildBackgroundPermissionReminder(),
                    const SizedBox(height: 16),
                  ],
                  if (useTwoColumns && cache != null)
                    SizedBox(
                      height: _wideOverviewCardHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildBasicInfoCard(
                              ipAddress: displayIp,
                              port: port,
                              isLoading: isLoading,
                              isRunning: isRunning,
                              uptime: _currentUptime(),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(child: _buildStatusCard(cache)),
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: cardSpacing,
                      runSpacing: 24,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: _buildBasicInfoCard(
                            ipAddress: displayIp,
                            port: port,
                            isLoading: isLoading,
                            isRunning: isRunning,
                            uptime: _currentUptime(),
                          ),
                        ),
                        if (cache != null)
                          SizedBox(
                            width: cardWidth,
                            child: _buildStatusCard(cache),
                          ),
                      ],
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBasicInfoCard({
    required String ipAddress,
    required int port,
    required bool isLoading,
    required bool isRunning,
    required Duration uptime,
  }) {
    return Container(
      decoration: _moduleDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '基本信息',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.lightCardForeground,
                  ),
                ),
                const SizedBox(height: 24),
                _buildDetailRow('设备名称', _uiDeviceName.isEmpty ? '--' : _uiDeviceName),
                _buildDetailDivider(),
                _buildDetailRow('IP 地址', ipAddress, monospace: true),
                _buildDetailDivider(),
                _buildDetailRow('端口', port.toString(), monospace: true),
                _buildDetailDivider(),
                _buildDetailRow(
                  '共享目录',
                  ServiceLocator.storageRootPath,
                  monospace: true,
                ),
                _buildDetailDivider(),
                _buildDetailRow(
                  '运行时长',
                  isRunning ? _formatUptime(uptime) : '--',
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            decoration: const BoxDecoration(
              color: Color(0xFFFFFEFD),
              border: Border(
                top: BorderSide(color: AppTheme.lightDivider, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Text(
                  '服务状态',
                  style: TextStyle(fontSize: 14, color: AppTheme.lightCardForeground),
                ),
                const SizedBox(width: 12),
                if (isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Transform.scale(
                    scale: 1.04,
                    child: Switch(
                      value: isRunning,
                      activeThumbColor: Colors.white,
                      activeTrackColor: const Color(0xFF22C55E),
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: AppTheme.lightDivider,
                      onChanged: (_) {
                        final cubit = context.read<ServerCubitImpl>();
                        if (isRunning) {
                          cubit.stopServer();
                        } else {
                          cubit.startServer();
                        }
                      },
                    ),
                  ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: isRunning ? _showPairingQrDialog : null,
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text('配对二维码'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: const BorderSide(
                      color: AppTheme.lightDivider,
                      width: 1,
                    ),
                    minimumSize: const Size(140, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool monospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.lightSecondaryText,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: monospace ? 13 : 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.lightCardForeground,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailDivider() {
    return const Divider(height: 1, color: AppTheme.surfaceContainerHigh);
  }

  Widget _buildStatusCard(SystemStatusCache cache) {
    final tiles = [
      _MetricTileData(
        icon: Icons.computer_rounded,
        iconColor: AppTheme.infoColor,
        label: '设备名称',
        value: _uiDeviceName.isNotEmpty ? _uiDeviceName : '--',
      ),
      _MetricTileData(
        icon: Icons.devices_rounded,
        iconColor: AppTheme.successColor,
        label: '在线设备',
        value: '${cache.connectedClients}',
      ),
      _MetricTileData(
        icon: Icons.storage_rounded,
        iconColor: AppTheme.diskIconColor,
        label: '磁盘占用',
        value: cache.totalStorage > 0
            ? '${_formatBytes(cache.usedStorage)}/${_formatBytes(cache.totalStorage)}'
            : '--/--',
      ),
      _MetricTileData(
        icon: Icons.memory_rounded,
        iconColor: AppTheme.memoryIconColor,
        label: '内存占用',
        value: cache.totalMemory > 0
            ? '${_formatBytes(cache.usedMemory)}/${_formatBytes(cache.totalMemory)}'
            : '--/--',
      ),
    ];

    return Container(
      decoration: _moduleDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '服务器状态',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.lightCardForeground,
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 420;
                final tileWidth = isWide
                    ? (constraints.maxWidth - 20) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: tiles
                      .map(
                        (tile) => SizedBox(
                          width: tileWidth,
                          child: _buildMetricTile(tile),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(_MetricTileData tile) {
    return Container(
      constraints: const BoxConstraints(minHeight: 170),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBright,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE5F6), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(tile.icon, size: 24, color: tile.iconColor),
          const SizedBox(height: 14),
          Text(
            tile.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.lightSecondaryText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tile.value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: tile.details == null ? 16 : 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.lightCardForeground,
              fontFamily: tile.label == '上次刷新' ? 'monospace' : null,
            ),
          ),
          if (tile.details != null && tile.details!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tile.details!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                letterSpacing: 0.2,
                color: AppTheme.lightSecondaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBackgroundPermissionReminder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.warningContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: AppTheme.warningColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppTheme.lightCardForeground,
                ),
                children: [
                  const TextSpan(
                    text: '为保证本应用在后台或熄屏后仍能提供服务，请在“设置->应用->应用管理->当前 APP->耗电管理”里',
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: _openAppManagementSettings,
                      child: const Text(
                        '开启',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.warningColor,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: '“完全允许后台行为”。'),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _dismissBackgroundPermissionReminder,
            child: const Icon(
              Icons.close,
              size: 18,
              color: AppTheme.lightSecondaryText,
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _moduleDecoration() {
    return BoxDecoration(
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
    );
  }
}

class _MetricTileData {
  const _MetricTileData({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.details,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? details;
}
