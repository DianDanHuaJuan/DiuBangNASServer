// 文件输入：无
// 文件职责：定义统一 WebDAV 资源模型，表达文件、目录、虚拟目录
// 文件对外接口：DavResource
// 文件包含：DavResource, DavSourceType
import 'dav_capability.dart';
import 'dav_resource_kind.dart';

enum DavSourceType { local, mediaStore }

class DavResource {
  final String davPath;
  final String name;
  final DavResourceKind kind;
  final DavCapability capability;
  final String? sourceRef;
  final DavSourceType sourceType;
  final int? size;
  final String? contentType;
  final DateTime? lastModified;

  const DavResource({
    required this.davPath,
    required this.name,
    required this.kind,
    required this.capability,
    this.sourceRef,
    required this.sourceType,
    this.size,
    this.contentType,
    this.lastModified,
  });

  bool get isDirectory => kind == DavResourceKind.collection;
  bool get isFile => kind == DavResourceKind.file;
  bool get isReadable => capability.readable;
  bool get isWritable => capability.writable;
  bool get isListable => capability.listable;

  static DavResource virtualDirectory({
    required String davPath,
    required String name,
    bool readable = true,
    bool listable = true,
  }) {
    return DavResource(
      davPath: davPath,
      name: name,
      kind: DavResourceKind.collection,
      capability: DavCapability(
        readable: readable,
        writable: false,
        listable: listable,
      ),
      sourceType: DavSourceType.local,
    );
  }

  static DavResource fsFile({
    required String davPath,
    required String name,
    required int size,
    String? contentType,
    DateTime? lastModified,
  }) {
    return DavResource(
      davPath: davPath,
      name: name,
      kind: DavResourceKind.file,
      capability: DavCapability.fullAccess,
      sourceType: DavSourceType.local,
      size: size,
      contentType: contentType,
      lastModified: lastModified,
    );
  }

  static DavResource fsDirectory({
    required String davPath,
    required String name,
  }) {
    return DavResource(
      davPath: davPath,
      name: name,
      kind: DavResourceKind.collection,
      capability: DavCapability.fullAccess,
      sourceType: DavSourceType.local,
    );
  }

  static DavResource mediaStoreFile({
    required String davPath,
    required String name,
    required String contentUri,
    required int size,
    String? contentType,
    DateTime? lastModified,
  }) {
    return DavResource(
      davPath: davPath,
      name: name,
      kind: DavResourceKind.file,
      capability: DavCapability.readableOnly,
      sourceRef: contentUri,
      sourceType: DavSourceType.mediaStore,
      size: size,
      contentType: contentType,
      lastModified: lastModified,
    );
  }

  static DavResource mediaStoreDirectory({
    required String davPath,
    required String name,
    bool listable = true,
  }) {
    return DavResource(
      davPath: davPath,
      name: name,
      kind: DavResourceKind.collection,
      capability: DavCapability(
        readable: true,
        writable: false,
        listable: listable,
      ),
      sourceType: DavSourceType.mediaStore,
    );
  }
}
