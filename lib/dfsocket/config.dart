import 'env.dart';
import 'log_util.dart';

/// http服务地址
const CONFIG_SERVER_BASE_URL = "server_base_url";

/// 行情Http服务
const CONFIG_QUOTE_BASE_URL = "quote_base_url";

/// socket服务主机名
const CONFIG_SOCKET_HOST = "socket_host";

/// web服务地址
const CONFIG_WEB_BASE_URL = "web_base_url";

/// ws
const CONFIG_WS_URL = "ws";

Map<String, dynamic> _defaultConfig = {
};

Map<String, dynamic> _devConfig = {
  CONFIG_SOCKET_HOST: "47.90.62.21",
  CONFIG_SERVER_BASE_URL: "http://47.90.62.21:9003/",
  CONFIG_WS_URL: "ws://test.trade.idefiex.com:9002/",
  CONFIG_QUOTE_BASE_URL: "http://47.90.62.21:9003/",
  CONFIG_WEB_BASE_URL: "http://192.168.31.24:5080/",
};

Map<String, dynamic> _previewConfig = {
  CONFIG_SOCKET_HOST: "pro.trade.idefiex.com",
  CONFIG_SERVER_BASE_URL: "http://pro.trade.idefiex.com/",
  CONFIG_QUOTE_BASE_URL: "http://pro.trade.idefiex.com/",
  CONFIG_WEB_BASE_URL: "http://pro.app.idefiex.com/",
};

Map<String, dynamic> _prodConfig = {
  CONFIG_SOCKET_HOST: "trade.idefiex.com",
  CONFIG_SERVER_BASE_URL: "https://trade.idefiex.com/",
  CONFIG_QUOTE_BASE_URL: "https://trade.idefiex.com/",
  CONFIG_WEB_BASE_URL: "https://app.idefiex.com/",
};

var _config = {
  Env.DEV: _devConfig,
  Env.PREVIEW: _previewConfig,
  Env.PROD: _prodConfig,
};

class Config {
  static Env _bootEnv;

  static Env _env;

  static Map<String, dynamic> _currentConfig;

  static get env => _env;

  static get bootEnv => _bootEnv;

  static get config => _currentConfig;

  static void setBootEnv(Env env) {
    _bootEnv = env;
  }

  static void setEnv(Env env) {
    LogUtil.v("use env: $env");
    Config._env = env;

    Map<String, dynamic> currentConfig = {};
    currentConfig.addAll(_defaultConfig);
    currentConfig.addAll(_config[env]);
    Config._currentConfig = currentConfig;
  }

  static String getServerBaseUrl() {
    return _currentConfig[CONFIG_SERVER_BASE_URL];
  }

  static String getSocketHost() {
    return _currentConfig[CONFIG_SOCKET_HOST];
  }

  static String getWebBaseUrl() {
    return _currentConfig[CONFIG_WEB_BASE_URL];
  }

  static void setConfig(String key, dynamic value) {
    if (null == value) {
      _currentConfig.remove(key);
      _defaultConfig.remove(key);
      return;
    }
    if (!(value is String || value is int || value is double)) {
      throw Exception("type error, [String, int, double]");
    }
    _currentConfig[key] = value;
    _defaultConfig[key] = value;
  }

  static dynamic getConfig(String key) {
    return _currentConfig[key];
  }
}

///  Telegram
class Telegram {
  static const OFFICIAL = "https://t.me/DefiexOfficial";
  static const BOT = "https://t.me/DefiexBot";
  static const EMAIL = "pr@idefiex.com";
  static const MEDIUM = "https://medium.com/@defiex";
  static const FACEBOOK = "https://www.facebook.com/DefiEx-114628376924900/";
  static const TWITTER = "https://twitter.com/defiexofficial";
}