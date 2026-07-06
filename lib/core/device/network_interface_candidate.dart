class NetworkInterfaceCandidate {
  const NetworkInterfaceCandidate({
    required this.address,
    required this.interfaceName,
    required this.isPrivate,
  });

  final String address;
  final String interfaceName;
  final bool isPrivate;

  @override
  bool operator ==(Object other) {
    return other is NetworkInterfaceCandidate &&
        other.address == address &&
        other.interfaceName == interfaceName;
  }

  @override
  int get hashCode => Object.hash(address, interfaceName);
}
