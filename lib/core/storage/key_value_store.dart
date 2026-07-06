// 文件输入：shared_preferences
// 文件职责：封装 SharedPreferences，提供类型安全的键值读写
// 文件对外接口：KeyValueStore
// 文件包含：KeyValueStore
import 'package:shared_preferences/shared_preferences.dart';

class KeyValueStore {
  KeyValueStore({required SharedPreferences sharedPreferences})
    : _prefs = sharedPreferences;

  final SharedPreferences _prefs;

  Future<void> reload() async {
    await _prefs.reload();
  }

  String? getString(String key) {
    return _prefs.getString(key);
  }

  Future<bool> setString(String key, String value) {
    return _prefs.setString(key, value);
  }

  int? getInt(String key) {
    return _prefs.getInt(key);
  }

  Future<bool> setInt(String key, int value) {
    return _prefs.setInt(key, value);
  }

  bool? getBool(String key) {
    return _prefs.getBool(key);
  }

  Future<bool> setBool(String key, bool value) {
    return _prefs.setBool(key, value);
  }

  Future<bool> remove(String key) {
    return _prefs.remove(key);
  }

  bool containsKey(String key) {
    return _prefs.containsKey(key);
  }
}
