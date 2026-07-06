import 'package:flutter/foundation.dart';

import '../storage/key_value_store.dart';
import 'local_network_resolution.dart';
import 'network_info_helper.dart';
import 'network_interface_candidate.dart';

class LocalNetworkAddressService extends ChangeNotifier {
  LocalNetworkAddressService({
    required KeyValueStore keyValueStore,
    required NetworkInfoHelper networkInfoHelper,
  }) : _keyValueStore = keyValueStore,
       _networkInfoHelper = networkInfoHelper;

  static const preferredLocalIpv4Key = 'preferred_local_ipv4';

  final KeyValueStore _keyValueStore;
  final NetworkInfoHelper _networkInfoHelper;

  List<NetworkInterfaceCandidate> _candidates = const [];
  String? _selectedIp;

  List<NetworkInterfaceCandidate> get candidates =>
      List.unmodifiable(_candidates);

  String? get selectedIp => _selectedIp;

  String? get effectiveIp => _selectedIp;

  Future<void> initialize() async {
    _selectedIp = _keyValueStore.getString(preferredLocalIpv4Key);
    await refreshCandidates();
  }

  Future<List<NetworkInterfaceCandidate>> refreshCandidates() async {
    _candidates = await _networkInfoHelper.listIpv4Candidates();
    notifyListeners();
    return candidates;
  }

  Future<void> setSelectedIp(String ip) async {
    final normalized = ip.trim();
    if (normalized.isEmpty) {
      return;
    }
    if (_selectedIp == normalized) {
      return;
    }
    _selectedIp = normalized;
    await _keyValueStore.setString(preferredLocalIpv4Key, normalized);
    notifyListeners();
  }

  Future<LocalNetworkResolution> resolveForServerStart() async {
    await refreshCandidates();

    if (_candidates.isEmpty) {
      return const LocalNetworkUnavailable();
    }

    final savedIp = _selectedIp?.trim();
    if (savedIp != null && savedIp.isNotEmpty) {
      if (_candidates.any((candidate) => candidate.address == savedIp)) {
        return LocalNetworkResolved(savedIp);
      }
      return LocalNetworkNeedsSelection(_candidates);
    }

    if (_candidates.length == 1) {
      final ip = _candidates.first.address;
      await setSelectedIp(ip);
      return LocalNetworkResolved(ip);
    }

    return LocalNetworkNeedsSelection(_candidates);
  }

  bool isSavedIpStillAvailable() {
    final savedIp = _selectedIp?.trim();
    if (savedIp == null || savedIp.isEmpty) {
      return false;
    }
    return _candidates.any((candidate) => candidate.address == savedIp);
  }
}
