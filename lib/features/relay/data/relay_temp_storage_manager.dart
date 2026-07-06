import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../../core/streams/buffered_byte_stream_transformer.dart';
import '../../../core/transfer/server_transfer_tuning.dart';
import '../domain/relay_models.dart';
import '../relay_contract.dart';

class RelayTempStorageManager {
  RelayTempStorageManager({required String rootPath}) : _rootPath = rootPath;

  final String _rootPath;

  String get relayRootPath => p.join(_rootPath, relayStorageDirectoryName);

  String transferDirectoryPath(String transferId) {
    return p.join(relayRootPath, transferId);
  }

  String stagingFilePath(String transferId) {
    return p.join(transferDirectoryPath(transferId), 'upload.part');
  }

  String sealedFilePath(String transferId) {
    return p.join(transferDirectoryPath(transferId), 'payload.bin');
  }

  String thumbnailFilePath(String transferId) {
    return p.join(transferDirectoryPath(transferId), 'thumbnail.jpg');
  }

  String thumbnailStagingFilePath(String transferId) {
    return p.join(transferDirectoryPath(transferId), 'thumbnail.part');
  }

  Future<void> initialize() async {
    await Directory(relayRootPath).create(recursive: true);
  }

  Future<RelaySealedArtifact> writeUploadStream({
    required RelayTransferRecord transfer,
    required Stream<List<int>> source,
    FutureOr<void> Function(int receivedBytes)? onProgress,
  }) async {
    final transferDirectory = Directory(
      transferDirectoryPath(transfer.transferId),
    );
    await transferDirectory.create(recursive: true);
    final stagingFile = File(stagingFilePath(transfer.transferId));
    final sealedFile = File(sealedFilePath(transfer.transferId));
    await _deleteIfExists(stagingFile);
    await _deleteIfExists(sealedFile);

    final sink = stagingFile.openWrite();
    final hashSink = transfer.checksum == null || transfer.checksum!.isEmpty
        ? null
        : Sha256().toSync().newHashSink();
    var receivedBytes = 0;
    try {
      await for (final chunk in bufferByteStream(
        source,
        ServerTransferTuning.uploadStreamBufferSize,
      )) {
        receivedBytes += chunk.length;
        if (receivedBytes > transfer.fileSize) {
          throw RelayStorageException(
            code: 'TRANSFER_SIZE_MISMATCH',
            message:
                'Expected ${transfer.fileSize} bytes but received more than declared',
          );
        }
        sink.add(chunk);
        hashSink?.add(chunk);
        await onProgress?.call(receivedBytes);
      }
    } on RelayStorageException {
      rethrow;
    } on Object {
      throw const RelayStorageException(
        code: 'TRANSFER_STREAM_FAILED',
        message: 'Relay upload stream failed before completion',
      );
    } finally {
      await sink.close();
    }

    if (receivedBytes != transfer.fileSize) {
      await _deleteIfExists(stagingFile);
      throw RelayStorageException(
        code: 'TRANSFER_SIZE_MISMATCH',
        message:
            'Expected ${transfer.fileSize} bytes but received $receivedBytes bytes',
      );
    }
    if (hashSink != null) {
      hashSink.close();
      final digest = await hashSink.hash();
      final encodedDigest = _toHex(digest.bytes);
      if (encodedDigest != transfer.checksum!.toLowerCase()) {
        await _deleteIfExists(stagingFile);
        throw const RelayStorageException(
          code: 'TRANSFER_CHECKSUM_MISMATCH',
          message: 'Transfer checksum does not match the uploaded content',
        );
      }
    }

    final sealedFileResult = await stagingFile.rename(sealedFile.path);

    return RelaySealedArtifact(
      sealedPath: sealedFileResult.path,
      chunkCount: transfer.fileSize > 0 ? 1 : 0,
      receivedBytes: receivedBytes,
    );
  }

  Future<void> deleteTransferData(String transferId) async {
    final directory = Directory(transferDirectoryPath(transferId));
    if (!await directory.exists()) {
      return;
    }
    await directory.delete(recursive: true);
  }

  Future<void> deleteThumbnailFile(String transferId) async {
    await _deleteIfExists(File(thumbnailFilePath(transferId)));
    await _deleteIfExists(File(thumbnailStagingFilePath(transferId)));
  }

  String _toHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final value in bytes) {
      buffer.write(value.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class RelaySealedArtifact {
  const RelaySealedArtifact({
    required this.sealedPath,
    required this.chunkCount,
    required this.receivedBytes,
  });

  final String sealedPath;
  final int chunkCount;
  final int receivedBytes;
}

class RelayStorageException implements Exception {
  const RelayStorageException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
