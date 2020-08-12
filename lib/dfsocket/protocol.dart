import 'dart:convert';

const PROTOCOL_KEY_CODE = "code";
const PROTOCOL_KEY_MSG = "msg";
const PROTOCOL_KEY_INFO = "info";

/// 接口成功的返回码
const CODE_OK = 0;

/// token过期错误码
const CODE_ERROR_TOKEN_EXPIRED = 106;

class BusinessError implements Exception {
  String errorCode;
  String msg;

  BusinessError(errorCode, msg) {
    this.errorCode = errorCode;
    this.msg = msg;
  }
}

bool isSuccessResponse(Object response) {
  return CODE_OK.toString() == getResCode(response);
}

String getResCode(Object response) => getProtocolFieldValue(response, PROTOCOL_KEY_CODE) ?? "";

String getRetMsg(Object response) => getProtocolFieldValue(response, PROTOCOL_KEY_MSG) ?? "";

dynamic getRetInfo(Object response) => getProtocolFieldValue(response, PROTOCOL_KEY_INFO);

Object getProtocolFieldValue(Object response, String key) {
  var json = toJSON(response);

  return (json ?? {})[key];
}

dynamic toJSON(Object response) {
  if (response is Map<String, dynamic> || response is List) {
    return response;
  }
  String s;
  if (response is String) {
    return jsonDecode(s);
  }

  if (s != null) {
    return jsonDecode(s);
  }
  return null;
}