// 文件输入：无
// 文件职责：定义 WebDAV 资源能力描述
// 文件对外接口：DavCapability
// 文件包含：DavCapability
class DavCapability {
  final bool readable;
  final bool writable;
  final bool listable;

  const DavCapability({
    required this.readable,
    required this.writable,
    required this.listable,
  });

  static const readableOnly = DavCapability(
    readable: true,
    writable: false,
    listable: false,
  );
  static const listableOnly = DavCapability(
    readable: false,
    writable: false,
    listable: true,
  );
  static const fullAccess = DavCapability(
    readable: true,
    writable: true,
    listable: true,
  );
  static const noAccess = DavCapability(
    readable: false,
    writable: false,
    listable: false,
  );
}
