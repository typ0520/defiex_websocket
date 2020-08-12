import 'dart:convert';

import 'package:web_socket_channel/io.dart';

class DFWebsocket {
  void start() {
    //ws://echo.websocket.org
    //new WebSocket('ws://test.trade.idefiex.com:9002')
    final channel = IOWebSocketChannel.connect('ws://test.trade.idefiex.com:9002/');

    channel.stream.listen((event) {
      var str = utf8.decode(event);
      print(str);

      var json = jsonDecode(str);

      if (json['cmd'] == 13507) {
        var now = DateTime.now();
        var quoteTime = DateTime.fromMillisecondsSinceEpoch(int.parse(json['data']['info']['T']) * 1000);
        print('延迟${now.millisecondsSinceEpoch - quoteTime.millisecondsSinceEpoch}, now: $now, quoteTime: $quoteTime');
      }
    });
    //channel.sink.add('{"cmd":"8888","seq":"1","data":{}}');

    var params = {
      'sub': [{
        'symbol': 'btc',
        'datatype': ['1seck']
      }],
      'unsub': [{
        'symbol': 'btc',
        'datatype': ['1seck']
      }],
    };

    var content = {
      'cmd': '13007',
      'seq': '2',
      'data': params,
    };
    channel.sink.add(jsonEncode(content));
  }
}