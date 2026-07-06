import 'network_interface_candidate.dart';

sealed class LocalNetworkResolution {
  const LocalNetworkResolution();
}

class LocalNetworkUnavailable extends LocalNetworkResolution {
  const LocalNetworkUnavailable();
}

class LocalNetworkNeedsSelection extends LocalNetworkResolution {
  const LocalNetworkNeedsSelection(this.candidates);

  final List<NetworkInterfaceCandidate> candidates;
}

class LocalNetworkResolved extends LocalNetworkResolution {
  const LocalNetworkResolved(this.ip);

  final String ip;
}
