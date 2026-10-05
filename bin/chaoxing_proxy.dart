import 'dart:convert';
import 'dart:io';

const _port = 8787;
Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
  stdout.writeln(
    'Schedule and grades proxy listening on http://localhost:$_port',
  );
  await for (final request in server) {
    _handle(request);
  }
}

Future<void> _handle(HttpRequest request) async {
  final response = request.response;
  _cors(response);
  if (request.method == 'OPTIONS') {
    response.statusCode = HttpStatus.noContent;
    await response.close();
    return;
  }
  final client = HttpClient();
  try {
    final jw = request.uri.path.startsWith('/jw/');
    final path = jw ? request.uri.path.substring(3) : request.uri.path;
    if (jw &&
        !['/Logon.do', '/jsxsd/'].any((prefix) => path.startsWith(prefix)) &&
        path != '/') {
      response.statusCode = 400;
      await response.close();
      return;
    }
    final host = jw ? 'jwglxt.sdust.edu.cn' : 'kb.chaoxing.com';
    final target = Uri.https(host, path, request.uri.queryParametersAll);
    final upstream = await client.openUrl(request.method, target);
    upstream.followRedirects = !jw;
    upstream.headers
      ..set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 Flutter Dio Proxy')
      ..set(
        HttpHeaders.refererHeader,
        jw
            ? 'https://$host/jsxsd/framework/xsrxkz.html'
            : 'https://$host/res/pc/curriculum/schedule.html',
      );
    if (jw) {
      upstream.headers.set(
        HttpHeaders.cookieHeader,
        request.headers.value('x-jw-cookie') ?? '',
      );
      upstream.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
    }
    await upstream.addStream(request);
    final incoming = await upstream.close();
    // Browser fetch follows redirects automatically. Relay the location explicitly.
    response.statusCode = jw && incoming.isRedirect ? 200 : incoming.statusCode;
    response.headers.contentType =
        incoming.headers.contentType ?? ContentType.text;
    if (jw) {
      response.headers.set(
        'x-jw-set-cookie',
        jsonEncode(incoming.headers[HttpHeaders.setCookieHeader] ?? []),
      );
      final location = incoming.headers.value(HttpHeaders.locationHeader);
      if (location != null) response.headers.set('x-jw-location', location);
    }
    await incoming.pipe(response);
  } catch (_) {
    response.statusCode = 502;
    response.write(jsonEncode({'code': -1, 'msg': '教务系统连接失败'}));
    await response.close();
  } finally {
    client.close(force: true);
  }
}

void _cors(HttpResponse response) {
  response.headers
    ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
    ..set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, POST, OPTIONS')
    ..set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'content-type, x-jw-cookie',
    )
    ..set('Access-Control-Expose-Headers', 'x-jw-set-cookie, x-jw-location');
}
