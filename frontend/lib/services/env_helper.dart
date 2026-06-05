import 'env_stub.dart' if (dart.library.io) 'env_io.dart' as env_impl;

String? getPlatformEnv(String key) => env_impl.getPlatformEnv(key);
