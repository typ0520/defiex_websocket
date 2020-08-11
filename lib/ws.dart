import 'package:web_socket_channel/io.dart';

class DFWebsocket {
  void start() {
    //ws://echo.websocket.org
    //new WebSocket('ws://test.trade.idefiex.com:9002')
    final channel = IOWebSocketChannel.connect('ws://test.trade.idefiex.com:9002/');

    channel.stream.listen((event) {
      print(event);
    });
    //channel.sink.add('{"cmd":"8888","seq":"1","data":{}}');
  }
}