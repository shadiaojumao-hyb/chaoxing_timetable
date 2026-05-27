import 'dart:io';

const _targetHost = 'kb.chaoxing.com';
const _port = 8787;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
  print('Chaoxing proxy listening on http://localhost:$_port');

  await for (final request in server) {
    if (request.method == 'OPTIONS') {
      _writeCorsHeaders(request.response).statusCode = HttpStatus.noContent;
      await request.response.close();
      continue;
    }

    try {
      final targetUri = Uri.https(
        _targetHost,
        request.uri.path,
        request.uri.queryParametersAll,
      );
      final client = HttpClient();
      final upstreamRequest = await client.openUrl(request.method, targetUri);
      upstreamRequest.headers
        ..set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 Flutter Dio Proxy')
        ..set(
          HttpHeaders.refererHeader,
          'https://kb.chaoxing.com/res/pc/curriculum/schedule.html',
        );

      final upstreamResponse = await upstreamRequest.close();
      final response = request.response;
      _writeCorsHeaders(response)
        ..statusCode = upstreamResponse.statusCode
        ..headers.contentType = ContentType.json;

      await upstreamResponse.pipe(response);
      client.close();
    } catch (error) {
      final response = _writeCorsHeaders(request.response)
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json;
      response.write('{"result":0,"msg":"proxy error: $error"}');
      await response.close();
    }
  }
}

HttpResponse _writeCorsHeaders(HttpResponse response) {
  response.headers
    ..set(HttpHeaders.accessControlAllowOriginHeader, '*')
    ..set(HttpHeaders.accessControlAllowMethodsHeader, 'GET, OPTIONS')
    ..set(HttpHeaders.accessControlAllowHeadersHeader, 'content-type');
  return response;
}
