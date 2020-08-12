/**
 * Created by tong on 2019/10/11.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ub_socket/retry.dart';
import 'package:web_socket_channel/io.dart';

import 'config.dart';
import 'log_util.dart';
import 'protocol.dart';

//------------------------同步命令号-----------------------------------

/*
 * 登录
 */
const int CMD_LOGIN = 8888;

/*
 * 心跳
 */
const int CMD_HEARTBEAT = 3101;

/*
 * 行情快照
 */
const int CMD_GET_SNAPSHOT = 13001;

/*
 * 现金购买
 */
const int CMD_CREATE_MARKET_ORDER_BY_CASH = 12001;

/*
 * 赠金购买
 */
const int CMD_CREATE_MARKET_ORDER_BY_ZJ = 12007;

/*
 * 平仓
 */
const int CMD_CLOSE_ORDER = 12003;

///
///自动平仓推送
const int CMD_PUSH_AUTO_CLOSE_ORDER = 12501;


//------------------------同步命令号-----------------------------------

//------------------------推送命令号-----------------------------------

/*
 * 最新行情推送
 */
const int CMD_PUSH_QUOTE = 13501;

/*
 * 踢人
 */
const int CMD_PUSH_LOGIN_CONFLICT = 11501;

/// 限价单成交
const int CMD_PUSH_LIMIT_ORDER_DEAL = 12506;

//------------------------推送命令号-----------------------------------

class NotVerifiedException implements Exception {}

// If set, the socket is connected
const int _kConnected = 1 << 0;

// If set, the connect is authenticated
const int _kConnectAuthenticated = 1 << 1;

// If set, the socket is reconnecting
const int _kReconnecting = 1 << 2;

// If set, the token is expired
const int _kTokenExpired = 1 << 3;

class DFSocket {
  //超过这个时间没有收到新包断开连接重连
  static const int _MAX_RECEIVE_PACKET_INTERVAL_MILLISECONDS = 30000;

  //心跳包发送间隔时间
  static const int _HEARTBEAT_INTERVAL_MILLISECONDS = 15000;

  static const int _SEQ_HEARTBEAT = 0;

  static const int _SEQ_LOGIN = 1;

  int _flags = 0;

  Socket _socket;
  IOWebSocketChannel _channel;
  StreamSubscription<List<int>> _subscription;
  List<int> _buffer = List();
  Packet _currentPacket;
  var _fragmentMap = Map<int, List<Packet>>();

  String host = Config.getSocketHost();
  int port = 9001;
  Map<String, dynamic> loginParams;

  bool reconnectionEnabled = true;
  Duration timeout = const Duration(seconds: 15);

  Timer _heartbeatTimer, _connectCheckerTimer;

  DateTime _lastReceivePacketTime;

  StreamController<Packet> _packetStreamController =
  StreamController.broadcast();

  StreamController<bool> _connectStatusStreamController =
  StreamController.broadcast();

  Function tokenExpiredCallback = () {};

  int get flag => _flags;

  DFSocket() {
//    packetStream().where((p) => p.wCmd == CMD_LOGIN).listen((packet) {
//      this._flags |= _kConnectAuthenticated;
//
//      //连接成功并且接收到登陆包以后对外发送socket连接成功的状态
//      _connectStatusStreamController.add(true);
//    });
//    packetStream().listen((packet) {
//      _lastReceivePacketTime = DateTime.now();
//      _debug("receive last packet time: " + _lastReceivePacketTime.toString());
//    });
  }

  Future<Packet> connect(Map<String, dynamic> loginParams,
      {Duration timeout = const Duration(seconds: 30), reconnectionEnabled = false}) async {
    try {
      disconnect();
      var url = Config.getConfig(CONFIG_WS_URL);
      _info('connect $url');

      _channel = IOWebSocketChannel.connect(url);
      await _channel.stream.first.timeout(timeout);
      await _didConnect(url, loginParams);
      var packet = await _request(CMD_LOGIN, params: loginParams, seq: _SEQ_LOGIN);

      var json = packet.toJson();
      if (CODE_ERROR_TOKEN_EXPIRED.toString() != getResCode(json)) {
        this._flags &= ~_kTokenExpired;
      }
      //心跳
      _startHeartbeat();

      this.reconnectionEnabled = reconnectionEnabled;
      if (reconnectionEnabled) {
        bindConnectChecker();
      }
      return packet;
    } catch (e) {
      _info("connect error: " + e.toString());
      //disconnect();
      rethrow;
    }
  }

  void connectUtilSuccess(Map<String, dynamic> loginParams) {
    final r = RetryOptions(maxAttempts: double.maxFinite.toInt(), maxDelay: const Duration(seconds: 3));
    r.retry(() async {
      await connect(loginParams, reconnectionEnabled: true);
    });
  }

  void disconnect({unbindConnectChecker = false}) async {
    _info('disconnect');

    try {
      await this._channel?.sink?.close();
    } catch (e) {
      LogUtil.v(e);
      //do nothing
    }

    this._channel = null;
    //this._flags = 0;
    this._currentPacket = null;
    this._buffer.clear();
    this._fragmentMap.clear();

    if (_subscription != null) {
      try {
        await _subscription.cancel();
      } catch (e) {
        //do nothing
      }
      _subscription = null;
    }

    if (this._heartbeatTimer != null) {
      this._heartbeatTimer.cancel();
    }

    _flags &= ~_kConnected;
    _flags &= ~_kConnectAuthenticated;
    _connectStatusStreamController.add(false);

    // || (this._flags & _kReconnecting) == 0
    if (unbindConnectChecker) {
      unbindConnectChecker();
    }
  }

  void bindConnectChecker() {
    if (_connectCheckerTimer != null) {
      return;
    }
    _info('bindConnectChecker');
    _connectCheckerTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (this._flags & _kReconnecting == 0) {
        //正在重联时不检测包间隔事件
        var lastReceiveMilliseconds = _lastReceivePacketTime == null ? 0 : _lastReceivePacketTime.millisecondsSinceEpoch;
        var currentMilliseconds = DateTime.now().millisecondsSinceEpoch;
        var dsize = currentMilliseconds - lastReceiveMilliseconds;
        _debug("check connect, time dsize: " + dsize.toString());
        if (lastReceiveMilliseconds != 0 && dsize > _MAX_RECEIVE_PACKET_INTERVAL_MILLISECONDS) {
          _debug("heartbeat timeout");
          _triggerReconnect();
        }
      }
    });
  }

  void unbindConnectChecker() {
    _info('unbindConnectChecker');
    if (_connectCheckerTimer != null) {
      _connectCheckerTimer.cancel();
    }
    _connectCheckerTimer = null;
  }

  Future<Map<String, dynamic>> request(int command, { Map<String, dynamic> params, timeoutSeconds = 15, int seq }) {
    if (command == CMD_LOGIN) {
      throw Exception('Login is a restricted operation');
    }

    return _request(command, params: params, seq: seq).timeout(Duration(seconds: timeoutSeconds)).then((packet) async {
      var json = packet.toJson();
      if (false == isSuccessResponse(json)) {
        var code = getResCode(json);
        var msg = getRetMsg(json);
        return Future.error(BusinessError(code, msg));
      }
      return json;
    });
  }

  Stream<bool> connectStatusChangedObserver() {
    return _connectStatusStreamController.stream;
  }

  Stream<Packet> packetStream() {
    return _packetStreamController.stream
        .handleError((error) {
      _debug('stream error');
    });
  }

  StreamSubscription<Packet> subscribe(void onData(Packet packet),
      {int command}) {
    return packetStream()
        .where((packet) => command == null || packet.wCmd == command)
        .listen(onData);
  }

  Future<Packet> _request(int command, { Map<String, dynamic> params, int seq }) {
    //同一个连接只能发一次登录请求
    if (command == CMD_LOGIN && (this._flags & _kConnectAuthenticated) != 0) {
      return Future.error(Exception('Already login'));
    }
    //已认证的连接，检查token是否过期
    if ((this._flags & _kConnectAuthenticated) != 0 && (this._flags & _kTokenExpired) != 0) {
      return Future.error(BusinessError(CODE_ERROR_TOKEN_EXPIRED.toString(), 'token expired'));
    }

    int wSeq = seq ?? Packet.getAndIncreaseSerialNumber();
    var requestPacket = Packet.fromData(command, wSeq, params);

    //收到登陆包之前不允许发别的包
    if (command != CMD_LOGIN && (this._flags & _kConnectAuthenticated) == 0) {
      return packetStream()
          .where((p) => p.wCmd == CMD_LOGIN)
          .first.then((value) {
        try {
          _sendPacket(requestPacket);
        } catch (e) {
          return Future.error(e);
        }
        return packetStream()
            .where((p) => p.wCmd == command && p.wSeq == requestPacket.wSeq)
            .first;
      });
    } else {
      try {
        _sendPacket(requestPacket);
      } catch (e) {
        return Future.error(e);
      }
      return packetStream()
          .where((p) => p.wCmd == command && p.wSeq == requestPacket.wSeq)
          .first;
    }
  }

  /*
   * 发送数据包
   */
  void _sendPacket(Packet packet) {
    if (packet == null) {
      return;
    }
    _info("send ${packet.toString()}");
    if (_socket == null) {
      return;
    }
    _socket.add(packet.toBytes());
  }

  Future<void> _didConnect(String url, Map<String, dynamic> loginParams) async {
    _info("connect success");

    this._flags |= _kConnected;

    this.host = host;
    this.loginParams = loginParams;

    _lastReceivePacketTime = null;

    _subscription = _channel.stream.handleError((e) {
      _closeWithError(e);
    }).listen((buffer) {
      var str = utf8.decode(buffer);
      var json = jsonDecode(str);
      var cmd = json['cmd'];
      var seq = json['seq'];
      var data = json['data'];
      var packet = Packet.fromData(cmd, seq, data);
      _dispatch(packet);
    });
    _subscription.onError((error) {
      _debug('_subscription onError');
    });
  }

  void _triggerReconnect() {
    if (false == reconnectionEnabled) {
      _warn('reconnection disabled skip...');
      return;
    }
    if (this._flags & _kReconnecting != 0) {
      _warn('reconnecting skip...');
      return;
    }
    _debug("_triggerReconnect, flag: ${this._flags}");

    this._flags |= _kReconnecting;
//    disconnect();
//
//    if ((_flags & _kConnected) != 0 && (_flags & _kConnectAuthenticated) != 0) {
//      return;
//    }
    _debug('start reconnect, this.flags: ${this._flags}');
    var reconnectTimes = 1;
    final r = RetryOptions(maxAttempts: double.maxFinite.toInt(), maxDelay: const Duration(seconds: 3));
    r.retry(() async {
      _debug("trigger reconnect, times: ${reconnectTimes++}");
      await _reconnect();
    });
  }

  void _reconnect() async {
    _info("reconnect ...");

    if (loginParams == null) {
      return;
    }
    try {
      await connect(loginParams, reconnectionEnabled: this.reconnectionEnabled);
      this._flags &= ~_kReconnecting;

      _debug('reconnect complete');
    } catch (e) {
      LogUtil.v(e);
      _warn("reconnect fail");
      rethrow;
    }
  }

  void _dispatch(Packet packet) {
    if (packet.wCmd != CMD_HEARTBEAT
    //&& packet.wCmd != CMD_PUSH_QUOTE
    ) {
      _info("receive ${packet.toString()}");
    }

    var json = packet.toJson();
    /**
     * {
     *    code: 0,
     *    msg: '',
     *    info: {}
     *  }
     */

    var code = getResCode(json);

    if (isSuccessResponse(json)) {
      //把info这层去掉
      var info = getRetInfo(json);
      if (null != info) {
        if (info is Map) {
          var msg = getRetMsg(json);
          info[PROTOCOL_KEY_CODE] = code;
          info[PROTOCOL_KEY_MSG] = msg;
        }
        json = info;
        packet.body = utf8.encode(jsonEncode(json));
      }
    }
    if (CODE_ERROR_TOKEN_EXPIRED.toString() == code) {
      //token过期
      _info('token expired, socket');

      setTokenExpired();
//        this._flags |= _kTokenExpired;
//        tokenExpiredCallback();
    }
    _lastReceivePacketTime = DateTime.now();
    _debug("receive last packet time: " + _lastReceivePacketTime.toString());

    if (packet.wCmd == CMD_LOGIN) {
      this._flags |= _kConnectAuthenticated;
      //连接成功并且接收到登陆包以后对外发送socket连接成功的状态
      _connectStatusStreamController.add(true);
    }
    //对外分发
    _packetStreamController.add(packet);
  }

  void setTokenExpired() {
//    if (this._flags & _kTokenExpired == 0) {
//      print("liubing:--------"+ "2");
    tokenExpiredCallback();
//      print("liubing:--------"+ "4");
//    } else {
//      print("liubing:--------"+ "3");
//    }
    this._flags |= _kTokenExpired;
  }

  void _closeWithError(Exception e) {
    _error("_closeWithError msg: " + e.toString() + " reconnectionEnabled: " + reconnectionEnabled.toString());
    //reconnect
    _triggerReconnect();
  }

  void _startHeartbeat() {
    _debug("_startHeartbeat");

    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: _HEARTBEAT_INTERVAL_MILLISECONDS), (timer) async {
      try {
        _debug("heartbeat");
        await _request(CMD_HEARTBEAT, seq: _SEQ_HEARTBEAT);
      } catch (e) {
        _error("ts send heartbeat error: ${e.toString()}");
      }
    });
  }
}

class Packet {
  static int HEADER_SIZE = 20;

  static int START_FLAG = 0xFF;

  static int _CURRENT_SERIAL_NUMBER = 2;

  static int getAndIncreaseSerialNumber() {
    if (_CURRENT_SERIAL_NUMBER > 0xFFFFFF) {
      _CURRENT_SERIAL_NUMBER = 1;
    }
    return _CURRENT_SERIAL_NUMBER++;
  }

  //开始标记
  int bStartFlag = START_FLAG;

  //版本号
  int bVer;

  //压缩标识 '0' 表示不压缩 '1'-gzip '2'-zlib
  int bEncryptFlag;

  //1是分片的包
  int bFrag;

  //报文长度
  int wLen;

  //命令号
  int wCmd;

  //包序列包(用来关联请求和响应的关联)
  int wSeq;

  //校验和
  int wCrc;

  //会话ID
  int dwSID;

  //包分片的个数
  int wTotal;

  //分片的索引
  int wCurSeq;

  List<int> body;

  Map data;

  dynamic addition;

  Packet(
        this.wCmd,
        this.wSeq,
        this.data);

  //从服务器写入到缓冲区的数据中解析报文体
  void readBody(List<int> buffer) {
    var len = this.wLen;
    this.body = buffer.sublist(0, len - Packet.HEADER_SIZE);
    buffer.removeRange(0, len - Packet.HEADER_SIZE);
  }
  }

  //分片的索引
  int getFragmentIndex() {
    return this.wCurSeq;
  }

  List<int> toBytes() {
    var bytes = List<int>();
    bytes.add(bStartFlag);
    bytes.add(bVer);
    bytes.add(bEncryptFlag);
    bytes.add(bFrag);

    bytes.addAll(body);
    return bytes;
  }

  String utf8body() {
    return utf8.decode(body != null ? body : List<int>());
  }

  Map<String, dynamic> toJson() {
    return jsonDecode(utf8body());
  }

  @override
  String toString() {
    return 'Packet{cmd: $wCmd, seq: $wSeq, body: ${utf8body()}}';
  }

  static Packet fromData(int command, int seq, Map data) {
    return Packet(command, seq, data);
  }
}

void _info(String log) {
  LogUtil.v(log);
}

void _debug(String log) {
  //LogUtil.v(log);
}

void _warn(String warn) {
  LogUtil.v(warn);
}

void _error(String error) {
  LogUtil.v(error);
}