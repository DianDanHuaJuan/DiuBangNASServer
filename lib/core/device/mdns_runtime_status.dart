enum MdnsRuntimeState { idle, active, failed }

class MdnsRuntimeStatus {
  const MdnsRuntimeStatus._({
    required this.state,
    required this.summary,
    this.details,
  });

  const MdnsRuntimeStatus.idle({String summary = '未广播', String? details})
    : this._(state: MdnsRuntimeState.idle, summary: summary, details: details);

  const MdnsRuntimeStatus.active({String summary = '广播中', String? details})
    : this._(
        state: MdnsRuntimeState.active,
        summary: summary,
        details: details,
      );

  const MdnsRuntimeStatus.failed({String summary = '广播失败', String? details})
    : this._(
        state: MdnsRuntimeState.failed,
        summary: summary,
        details: details,
      );

  final MdnsRuntimeState state;
  final String summary;
  final String? details;

  bool get isActive => state == MdnsRuntimeState.active;
  bool get isFailed => state == MdnsRuntimeState.failed;
}
