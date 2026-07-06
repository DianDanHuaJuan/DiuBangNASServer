// 文件输入：无
// 文件职责：根据文件扩展名推断 MIME Content-Type
// 文件对外接口：ContentTypeResolver
// 文件包含：ContentTypeResolver
class ContentTypeResolver {
  const ContentTypeResolver();

  static const _mimeTypes = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.bmp': 'image/bmp',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.mp4': 'video/mp4',
    '.mkv': 'video/x-matroska',
    '.avi': 'video/x-msvideo',
    '.mov': 'video/quicktime',
    '.webm': 'video/webm',
    '.wmv': 'video/x-ms-wmv',
    '.flv': 'video/x-flv',
    '.mp3': 'audio/mpeg',
    '.wav': 'audio/wav',
    '.flac': 'audio/flac',
    '.aac': 'audio/aac',
    '.ogg': 'audio/ogg',
    '.m4a': 'audio/mp4',
    '.pdf': 'application/pdf',
    '.doc': 'application/msword',
    '.docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xls': 'application/vnd.ms-excel',
    '.xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.ppt': 'application/vnd.ms-powerpoint',
    '.pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    '.zip': 'application/zip',
    '.rar': 'application/x-rar-compressed',
    '.7z': 'application/x-7z-compressed',
    '.tar': 'application/x-tar',
    '.gz': 'application/gzip',
    '.txt': 'text/plain',
    '.html': 'text/html',
    '.htm': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.json': 'application/json',
    '.xml': 'application/xml',
    '.csv': 'text/csv',
    '.ts': 'video/mp2t',
  };

  String resolve(String extension) {
    final ext = extension.toLowerCase();
    return _mimeTypes[ext] ?? 'application/octet-stream';
  }

  bool isImage(String extension) {
    final ext = extension.toLowerCase();
    return ext == '.jpg' ||
        ext == '.jpeg' ||
        ext == '.png' ||
        ext == '.gif' ||
        ext == '.webp' ||
        ext == '.bmp';
  }

  bool isVideo(String extension) {
    final ext = extension.toLowerCase();
    return ext == '.mp4' ||
        ext == '.mkv' ||
        ext == '.avi' ||
        ext == '.mov' ||
        ext == '.webm';
  }

  bool isAudio(String extension) {
    final ext = extension.toLowerCase();
    return ext == '.mp3' ||
        ext == '.wav' ||
        ext == '.flac' ||
        ext == '.aac' ||
        ext == '.ogg' ||
        ext == '.m4a';
  }
}
