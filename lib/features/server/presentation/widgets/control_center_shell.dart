import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

class ControlCenterShell extends StatefulWidget {
  const ControlCenterShell({
    super.key,
    required this.serviceChild,
    required this.backupFilesChild,
    required this.devicesChild,
    required this.settingsChild,
  });

  final Widget serviceChild;
  final Widget backupFilesChild;
  final Widget devicesChild;
  final Widget settingsChild;

  @override
  State<ControlCenterShell> createState() => _ControlCenterShellState();
}

class _ControlCenterShellState extends State<ControlCenterShell> {
  static const double _desktopBreakpoint = 960;
  static const double _pinnedSidebarBreakpoint = 1180;
  static const double _pagePadding = 24;
  static const double _contentGap = 28;
  static const double _desktopSidebarWidth = 210;
  static const double _edgeTriggerWidth = 18;
  static const ValueKey<String> _sidebarPanelKey = ValueKey<String>(
    'control-center-sidebar-panel',
  );

  int _selectedIndex = 0;
  bool _isSidebarHovered = false;
  bool _isEdgeHovered = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final supportsHoverSidebar = _supportsHoverSidebar(context);
        final showDesktopLayout = constraints.maxWidth >= _desktopBreakpoint;
        final showPinnedSidebar =
            showDesktopLayout &&
            (constraints.maxWidth >= _pinnedSidebarBreakpoint ||
                !supportsHoverSidebar);
        final showHoverSidebar =
            showDesktopLayout && supportsHoverSidebar && !showPinnedSidebar;

        return Scaffold(
          backgroundColor: const Color(0xFFF7F9FF),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(_pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  Expanded(
                    child: showDesktopLayout
                        ? Stack(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showPinnedSidebar) ...[
                                    _buildSideNavigation(
                                      width: _desktopSidebarWidth,
                                    ),
                                    const SizedBox(width: _contentGap),
                                  ],
                                  Expanded(child: _buildContent()),
                                ],
                              ),
                              if (showHoverSidebar) ...[
                                _buildEdgeTrigger(),
                                _buildHoverSidebar(width: _desktopSidebarWidth),
                              ],
                            ],
                          )
                        : _buildContent(),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: showDesktopLayout
              ? null
              : _buildBottomNavigation(),
        );
      },
    );
  }

  bool _supportsHoverSidebar(BuildContext context) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  bool get _isOverlaySidebarVisible => _isSidebarHovered || _isEdgeHovered;

  void _setSidebarHovered(bool value) {
    if (_isSidebarHovered == value) {
      return;
    }
    setState(() {
      _isSidebarHovered = value;
    });
  }

  void _setEdgeHovered(bool value) {
    if (_isEdgeHovered == value) {
      return;
    }
    setState(() {
      _isEdgeHovered = value;
    });
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const _BrandMark(),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            '控制中心',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.lightCardForeground,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return IndexedStack(
      index: _selectedIndex,
      children: [
        widget.serviceChild,
        widget.backupFilesChild,
        widget.devicesChild,
        widget.settingsChild,
      ],
    );
  }

  Widget _buildSideNavigation({required double width}) {
    return MouseRegion(
      onEnter: (_) => _setSidebarHovered(true),
      onExit: (_) => _setSidebarHovered(false),
      child: SizedBox(
        key: _sidebarPanelKey,
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _buildSideNavItem(
              index: 0,
              icon: Icons.dns_outlined,
              activeIcon: Icons.dns_rounded,
              label: '服务',
            ),
            const SizedBox(height: 8),
            _buildSideNavItem(
              index: 1,
              icon: Icons.folder_copy_outlined,
              activeIcon: Icons.folder_copy_rounded,
              label: '文件',
            ),
            const SizedBox(height: 8),
            _buildSideNavItem(
              index: 2,
              icon: Icons.devices_outlined,
              activeIcon: Icons.devices_rounded,
              label: '设备',
            ),
            const SizedBox(height: 8),
            _buildSideNavItem(
              index: 3,
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings_rounded,
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoverSidebar({required double width}) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: _isOverlaySidebarVisible ? 0 : -width,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !_isOverlaySidebarVisible,
        child: Container(
          width: width,
          padding: const EdgeInsets.only(top: 2),
          color: const Color(0xFFF7F9FF),
          child: _buildSideNavigation(width: width),
        ),
      ),
    );
  }

  Widget _buildEdgeTrigger() {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: _edgeTriggerWidth,
      child: MouseRegion(
        opaque: false,
        onEnter: (_) => _setEdgeHovered(true),
        onExit: (_) => _setEdgeHovered(false),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 4,
            height: 96,
            decoration: BoxDecoration(
              color: _isOverlaySidebarVisible
                  ? Colors.transparent
                  : const Color(0xFFDDE6FA),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSideNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final selected = _selectedIndex == index;
    return InkWell(
      borderRadius: BorderRadius.circular(0),
      onTap: () {
        setState(() => _selectedIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFCFE1FF) : Colors.transparent,
          border: Border(
            right: BorderSide(
              color: selected ? AppTheme.accentColor : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? activeIcon : icon,
              size: 24,
              color: selected
                  ? AppTheme.accentColor
                  : AppTheme.lightSecondaryText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? AppTheme.accentColor
                      : AppTheme.lightCardForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return NavigationBar(
      height: 72,
      selectedIndex: _selectedIndex,
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFCFE1FF),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dns_outlined),
          selectedIcon: Icon(Icons.dns_rounded),
          label: '服务',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_copy_outlined),
          selectedIcon: Icon(Icons.folder_copy_rounded),
          label: '文件',
        ),
        NavigationDestination(
          icon: Icon(Icons.devices_outlined),
          selectedIcon: Icon(Icons.devices_rounded),
          label: '设备',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: '设置',
        ),
      ],
      onDestinationSelected: (index) {
        setState(() => _selectedIndex = index);
      },
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: const [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Icon(
              Icons.dns_rounded,
              size: 24,
              color: AppTheme.accentColor,
            ),
          ),
          Positioned(
            top: -1,
            left: 6,
            child: Icon(
              Icons.wifi_rounded,
              size: 16,
              color: AppTheme.accentColor,
            ),
          ),
        ],
      ),
    );
  }
}
