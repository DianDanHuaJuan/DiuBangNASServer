// 文件输入：无
// 文件职责：解析 HTTP Range 请求头
// 文件对外接口：RangeParser, RangeResult
// 文件包含：RangeParser, RangeResult
class RangeParser {
  const RangeParser();

  RangeResult? parse(String header, int totalSize) {
    if (totalSize <= 0) {
      return null;
    }

    final trimmed = header.trim();
    final match = RegExp(r'^bytes=(.+)$').firstMatch(trimmed);
    if (match == null) {
      return null;
    }

    final rawRanges = match.group(1);
    if (rawRanges == null) {
      return null;
    }

    final ranges = rawRanges
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (ranges.length != 1) {
      return null;
    }

    final parts = ranges.first.split('-');
    if (parts.length != 2) {
      return null;
    }

    final startPart = parts[0].trim();
    final endPart = parts[1].trim();
    if (startPart.isEmpty && endPart.isEmpty) {
      return null;
    }

    late final int start;
    late final int end;

    if (startPart.isEmpty) {
      final suffixLength = int.tryParse(endPart);
      if (suffixLength == null || suffixLength <= 0) {
        return null;
      }

      final safeLength = suffixLength > totalSize ? totalSize : suffixLength;
      start = totalSize - safeLength;
      end = totalSize - 1;
    } else {
      start = int.tryParse(startPart) ?? -1;
      if (start < 0 || start >= totalSize) {
        return null;
      }

      if (endPart.isEmpty) {
        end = totalSize - 1;
      } else {
        final parsedEnd = int.tryParse(endPart);
        if (parsedEnd == null || parsedEnd < start) {
          return null;
        }
        end = parsedEnd >= totalSize ? totalSize - 1 : parsedEnd;
      }
    }

    if (end < start) {
      return null;
    }

    return RangeResult(start: start, end: end, totalSize: totalSize);
  }
}

class RangeResult {
  final int start;
  final int end;
  final int totalSize;
  const RangeResult({
    required this.start,
    required this.end,
    required this.totalSize,
  });
}
