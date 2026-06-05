import 'dart:io';

String? getPlatformEnv(String key) {
  try {
    return Platform.environment[key];
  } catch (e) {
    return null;
  }
}
