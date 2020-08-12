import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'dfsocket/config.dart';
import 'dfsocket/env.dart';
import 'dfsocket/log_util.dart';
import 'dfsocket/socket.dart';

void main() {
  Config.setEnv(Env.DEV);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final title = 'WebSocket Demo';
    return MaterialApp(
      title: title,
      home: MyHomePage(
        title: title,
        channel: IOWebSocketChannel.connect('ws://echo.websocket.org'),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String title;
  final WebSocketChannel channel;

  MyHomePage({Key key, @required this.title, @required this.channel})
      : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  TextEditingController _controller = TextEditingController();

  bool connected = false;
  DFSocket dfSocket;

  @override
  void initState() {
    super.initState();
    dfSocket = DFSocket();
    dfSocket.connectStatusChangedObserver().listen((event) {
      this.setState(() {
        connected = event;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 10,
              children: [
                RaisedButton(
                  onPressed: () async {
                    var params = {
                      'deviceid': "test1",
                      'clientversion': "1",
                      'visit': 1,
                      'username': 'test1'
                    };
                    params['clienttype'] = 2;

                    var formatter = new DateFormat('yyyy-MM-dd HH:mm:ss.S');
                    params['time'] = formatter.format(DateTime.now());

                   // var packet = await dfSocket.connect(params, reconnectionEnabled: true);
                    //print(packet.toString());
                    dfSocket.connectUtilSuccess(params);
                  },
                  child: Text('连接'),
                ),
                RaisedButton(
                  onPressed: () async {
                    await dfSocket.disconnect(unbindConnectChecker: true);
                  },
                  child: Text('断开'),
                ),
                RaisedButton(
                  onPressed: () async {
                    var symbols = ['btc', 'eth', 'eos', 'ltc', 'bch', 'etc', 'xrp', 'bsv'];
                    var sub = symbols.map((item) => {
                      'symbol': item,
                      'datatype': ['snap']
                    }).toList();
                    var params = {
                      'sub': sub,
                      'unsub': [],
                    };
                    await dfSocket.request(13007, params: params);
                    LogUtil.v('订阅成功');
                  },
                  child: Text('订阅行情'),
                ),
                RaisedButton(
                  onPressed: () async {
                    var symbols = ['btc', 'eth', 'eos', 'ltc', 'bch', 'etc', 'xrp', 'bsv'];
                    var sub = symbols.map((item) => {
                      'symbol': item,
                      'datatype': ['snap']
                    }).toList();
                    var params = {
                      'sub': [],
                      'unsub': sub,
                    };
                    await dfSocket.request(13007, params: params);
                    LogUtil.v('取消订阅成功');
                  },
                  child: Text('取消订阅'),
                ),
//                RaisedButton(
//                  onPressed: () {
//                    int start = DateTime.now().millisecondsSinceEpoch;
//                    int now = DateTime.now().millisecondsSinceEpoch;
//                    while (now - start < 3000) {
//                      now = DateTime.now().millisecondsSinceEpoch;
//                    }
//                  },
//                  child: Text('延迟三秒'),
//                ),
              ],
            ),

            Text(connected ? '已连接' : '未连接'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _sendMessage,
        tooltip: 'Send message',
        child: Icon(Icons.send),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void _sendMessage() {
    if (_controller.text.isNotEmpty) {
      widget.channel.sink.add(_controller.text);
    }
  }

  @override
  void dispose() {
    widget.channel.sink.close();
    super.dispose();
  }
}
