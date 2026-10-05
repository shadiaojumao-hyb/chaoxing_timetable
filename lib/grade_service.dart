import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class LoginRequired implements Exception {}

class GradeService {
  GradeService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );
  final Dio _dio;
  final Map<String, ({String name, String value, String path})> _cookies = {};
  bool get hasSession => _cookies.isNotEmpty;
  static const host = 'https://jwglxt.sdust.edu.cn';

  static String encodeLogin(
    String account,
    String password,
    String scode,
    String sxh,
  ) {
    final code = '$account%%%$password%%% ';
    final digits = sxh.replaceAll(RegExp(r'\D'), '');
    final result = StringBuffer();
    for (var i = 0; i < code.length; i++) {
      if (i >= 55 || i >= digits.length) {
        result.write(code.substring(i));
        break;
      }
      final step = int.parse(digits[i]).clamp(0, scode.length);
      result.write(code[i]);
      result.write(scode.substring(0, step));
      scode = scode.substring(step);
    }
    return result.toString();
  }

  Future<Response<String>> _request(
    String path, {
    Map<String, String>? data,
    int redirects = 0,
  }) async {
    final uri = Uri.parse(host).resolve(path);
    if (uri.origin != host || redirects > 8) {
      throw const FormatException('教务系统重定向异常');
    }
    final cookies =
        _cookies.values
            .where(
              (c) =>
                  uri.path == c.path ||
                  uri.path.startsWith(
                    c.path.endsWith('/') ? c.path : '${c.path}/',
                  ),
            )
            .toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));
    final cookie = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    final response = await _dio.request<String>(
      kIsWeb
          ? 'http://localhost:8787/jw${uri.path}?${uri.query}'
          : uri.toString(),
      data: data,
      options: Options(
        method: data == null ? 'GET' : 'POST',
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 500,
        contentType: Headers.formUrlEncodedContentType,
        headers: kIsWeb
            ? {'X-JW-Cookie': cookie}
            : {
                'Cookie': cookie,
                'Referer': '$host/jsxsd/framework/xsrxkz.html',
              },
      ),
    );
    final rawCookies = kIsWeb
        ? (jsonDecode(response.headers.value('x-jw-set-cookie') ?? '[]')
                  as List)
              .cast<String>()
        : response.headers['set-cookie'] ?? <String>[];
    for (final raw in rawCookies) {
      final parts = raw.split(';');
      final pair = parts.first.split('=');
      if (pair.length < 2) continue;
      final pathAttr = parts
          .skip(1)
          .map((p) => p.trim())
          .where((p) => p.toLowerCase().startsWith('path='))
          .firstOrNull;
      final cookiePath =
          pathAttr?.substring(5) ??
          uri.path.substring(0, uri.path.lastIndexOf('/') + 1);
      _cookies['${pair.first}|$cookiePath'] = (
        name: pair.first,
        value: pair.skip(1).join('='),
        path: cookiePath,
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw LoginRequired();
    }
    final location = response.headers.value(
      kIsWeb ? 'x-jw-location' : 'location',
    );
    if (location != null && (response.statusCode! >= 300 || kIsWeb)) {
      return _request(
        uri.resolve(location).toString(),
        redirects: redirects + 1,
      );
    }
    return response;
  }

  Future<void> login(String account, String password) async {
    _cookies.clear();
    final key =
        (await _request(
          '/Logon.do?method=logon&flag=sess',
          data: {},
        )).data?.trim().split('#') ??
        [];
    if (key.length < 2) throw const FormatException('获取登录密钥失败，请稍后重试');
    await _request(
      '/Logon.do?method=logon',
      data: {
        'loginMethod': 'logon',
        'userlanguage': '0',
        'userAccount': account,
        'userPassword': '',
        'encoded': encodeLogin(account, password, key[0], key[1]),
      },
    );
    // The grades endpoint validates the subsystem session, not just a redirect.
  }

  Future<Map<String, dynamic>> fetchGrades() async {
    final rows = <dynamic>[];
    Map<String, dynamic>? result;
    for (var page = 1; page <= 500; page++) {
      final query = Uri(
        queryParameters: {
          'pageNum': '$page',
          'pageSize': '100',
          'kksj': '',
          'kcxz': '',
          'kcsx': '',
          'kcmc': '',
          'xsfs': 'all',
          'sfxsbcxq': '1',
        },
      ).query;
      final text = (await _request('/jsxsd/kscj/cjcx_list?$query')).data ?? '';
      if (text.contains('请先登录') ||
          RegExp(
            r'logon|userAccount|type\s*=\s*["\x27]password',
            caseSensitive: false,
          ).hasMatch(text)) {
        throw LoginRequired();
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        throw const FormatException('成绩接口未返回有效数据，请稍后刷新');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('成绩数据格式异常');
      }
      if ('${decoded['code']}' != '0') {
        final message = '${decoded['msg'] ?? '获取成绩失败'}';
        if (RegExp('登录|会话|超时|认证').hasMatch(message)) throw LoginRequired();
        throw FormatException(message);
      }
      if (decoded['data'] is! List) throw const FormatException('成绩列表格式异常');
      result ??= decoded;
      final batch = decoded['data'] as List;
      rows.addAll(batch);
      final count = int.tryParse('${decoded['count']}');
      if ((count != null && rows.length >= count) ||
          (count == null && batch.length < 100)) {
        return {
          ...result,
          'data': rows,
          'savedAt': DateTime.now().toIso8601String(),
        };
      }
      if (batch.isEmpty) throw const FormatException('成绩分页不完整，请重试');
    }
    throw const FormatException('成绩分页数量异常');
  }
}
