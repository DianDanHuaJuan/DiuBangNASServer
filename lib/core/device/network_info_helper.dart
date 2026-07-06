import 'dart:io';

import 'network_interface_candidate.dart';

class NetworkInfoHelper {
  Future<List<NetworkInterfaceCandidate>> listIpv4Candidates() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        includeLoopback: false,
        type: InternetAddressType.any,
      );

      final candidates = <NetworkInterfaceCandidate>[];
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
            continue;
          }
          candidates.add(
            NetworkInterfaceCandidate(
              address: address.address,
              interfaceName: interface.name,
              isPrivate: _isPrivateIpv4(address.address),
            ),
          );
        }
      }

      candidates.sort((a, b) {
        final nameCompare = a.interfaceName.compareTo(b.interfaceName);
        if (nameCompare != 0) {
          return nameCompare;
        }
        return a.address.compareTo(b.address);
      });

      return candidates;
    } catch (_) {
      return const [];
    }
  }

  @Deprecated('Use LocalNetworkAddressService instead.')
  Future<String?> getLocalIpv4Address() async {
    final candidates = await listIpv4Candidates();
    if (candidates.isEmpty) {
      return null;
    }
    for (final candidate in candidates) {
      if (candidate.isPrivate) {
        return candidate.address;
      }
    }
    return candidates.first.address;
  }

  Future<String?> getWifiName() async {
    return null;
  }

  bool _isPrivateIpv4(String address) {
    return address.startsWith('10.') ||
        address.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(address);
  }
}
