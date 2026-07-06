// 文件输入：permission_handler
// 文件职责：封装 Android 权限申请逻辑，支持 Android 13+ 媒体权限
// 文件对外接口：PermissionService
// 文件包含：PermissionService
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  const PermissionService();

  Future<bool> requestLocationPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.location.request();
    return status.isGranted;
  }

  Future<bool> checkLocationPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.location.status;
    return status.isGranted;
  }

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final manageStatus = await Permission.manageExternalStorage.request();

    if (manageStatus.isGranted) {
      return true;
    }

    if (manageStatus.isPermanentlyDenied) {
      await openAppSettings();
    }

    return false;
  }

  Future<bool> checkStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final manageStatus = await Permission.manageExternalStorage.status;
    return manageStatus.isGranted;
  }

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.notification.request();

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }

    return false;
  }

  Future<bool> checkNotificationPermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.notification.status;
    return status.isGranted;
  }

  Future<bool> requestAllPermissions() async {
    final locationGranted = await requestLocationPermission();
    final storageGranted = await requestStoragePermission();
    final notificationGranted = await requestNotificationPermission();
    return locationGranted && storageGranted && notificationGranted;
  }
}
