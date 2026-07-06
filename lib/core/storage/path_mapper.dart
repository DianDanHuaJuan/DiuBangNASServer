import 'package:path/path.dart' as p;

import 'share_internal_paths.dart';

enum ServerPathRoot { fs, library }

enum PathMappingErrorCode {
  unsupportedRoot,
  invalidEncoding,
  invalidPath,
  rootPathNotAllowed,
  nestedPathNotAllowed,
}

class PathMappingException implements Exception {
  const PathMappingException(this.code, this.message);

  final PathMappingErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class MappedServerPath {
  const MappedServerPath._({
    required this.root,
    required this.normalizedPath,
    required this.segments,
    required this.localPath,
  });

  final ServerPathRoot root;
  final String normalizedPath;
  final List<String> segments;
  final String? localPath;

  bool get isRoot => segments.isEmpty;
  bool get isFlatFile => segments.length == 1;
  String? get fileName => isFlatFile ? segments.first : null;
  String get relativePath => isRoot ? '' : '/${segments.join('/')}';
}

class PathMapper {
  const PathMapper({this.rootPath = ''});

  final String rootPath;

  MappedServerPath resolve(
    String rawPath, {
    Set<ServerPathRoot> allowedRoots = const {
      ServerPathRoot.fs,
      ServerPathRoot.library,
    },
    bool allowRoot = true,
    bool allowNestedPaths = true,
  }) {
    final normalizedInput = _normalizeRawPath(rawPath);
    final parts = normalizedInput
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    if (parts.isEmpty) {
      throw const PathMappingException(
        PathMappingErrorCode.unsupportedRoot,
        'Path must start with /fs or /library.',
      );
    }

    final root = _parseRoot(parts.first);
    if (!allowedRoots.contains(root)) {
      throw const PathMappingException(
        PathMappingErrorCode.unsupportedRoot,
        'Path must start with /fs or /library.',
      );
    }

    final decodedSegments = <String>[];
    for (final rawSegment in parts.skip(1)) {
      final decodedSegment = _decodeSegment(rawSegment);
      if (decodedSegment.isEmpty ||
          decodedSegment == '.' ||
          decodedSegment == '..' ||
          isReservedShareSegment(decodedSegment) ||
          decodedSegment.contains('/') ||
          decodedSegment.contains(r'\')) {
        throw const PathMappingException(
          PathMappingErrorCode.invalidPath,
          'Path contains invalid or unsafe segments.',
        );
      }
      decodedSegments.add(decodedSegment);
    }

    if (!allowRoot && decodedSegments.isEmpty) {
      throw const PathMappingException(
        PathMappingErrorCode.rootPathNotAllowed,
        'Path must target a file, not the root collection.',
      );
    }

    if (!allowNestedPaths && decodedSegments.length > 1) {
      throw const PathMappingException(
        PathMappingErrorCode.nestedPathNotAllowed,
        'Subdirectories are not allowed for this operation.',
      );
    }

    final normalizedPath = decodedSegments.isEmpty
        ? '/${root.segment}'
        : '/${root.segment}/${decodedSegments.join('/')}';

    String? localPath;
    if (root == ServerPathRoot.fs && rootPath.isNotEmpty) {
      final normalizedRootPath = p.normalize(rootPath);
      final candidatePath = decodedSegments.isEmpty
          ? normalizedRootPath
          : p.normalize(p.joinAll([normalizedRootPath, ...decodedSegments]));

      if (candidatePath != normalizedRootPath &&
          !p.isWithin(normalizedRootPath, candidatePath)) {
        throw const PathMappingException(
          PathMappingErrorCode.invalidPath,
          'Path escapes the configured storage root.',
        );
      }

      localPath = candidatePath;
    }

    return MappedServerPath._(
      root: root,
      normalizedPath: normalizedPath,
      segments: List.unmodifiable(decodedSegments),
      localPath: localPath,
    );
  }

  String _normalizeRawPath(String rawPath) {
    final trimmedPath = rawPath.trim();
    if (trimmedPath.isEmpty) {
      return '/';
    }

    if (trimmedPath.contains(r'\')) {
      throw const PathMappingException(
        PathMappingErrorCode.invalidPath,
        'Path cannot contain backslashes.',
      );
    }

    return trimmedPath.startsWith('/') ? trimmedPath : '/$trimmedPath';
  }

  ServerPathRoot _parseRoot(String value) {
    return switch (value) {
      'fs' => ServerPathRoot.fs,
      'library' => ServerPathRoot.library,
      _ => throw const PathMappingException(
        PathMappingErrorCode.unsupportedRoot,
        'Path must start with /fs or /library.',
      ),
    };
  }

  String _decodeSegment(String segment) {
    if (!segment.contains('%')) {
      return segment;
    }

    try {
      return Uri.decodeComponent(segment);
    } on FormatException {
      throw const PathMappingException(
        PathMappingErrorCode.invalidEncoding,
        'Path contains invalid percent-encoding.',
      );
    }
  }
}

extension on ServerPathRoot {
  String get segment => switch (this) {
    ServerPathRoot.fs => 'fs',
    ServerPathRoot.library => 'library',
  };
}
