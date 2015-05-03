part of shelf_cookie;

/**
 * Cookie parser for shelf.
 * Do not use this class directly, let's use [cookieMiddleware] function.
 */
class ShelfCookieParser {
  static Request updateRequest(Request request, {String contextKey: 'cookies'}) {
    var cookies = CookieParser.parse(request.headers[HttpHeaders.COOKIE]);
    return request.change(context: {contextKey: cookies});
  }
}

/**
 * Parse cookies string on request/response header.
 * example usage:
 *      import "shelf_redis_session_store/shelf_cookie.dart" show CookieParser;
 *      Map<String, Cookie> cookies = CookieParser.parse(request.headers[HttpHeaders.COOKIE]);
 */
class CookieParser {
  static Map<String, Cookie> parse(String rawCookie) {
    var cookies = new Map<String, Cookie>();
    if (rawCookie is! String || rawCookie.length == 0) {
      return cookies;
    }
    var parsedCookies = _parseCookies(rawCookie);
    parsedCookies.forEach((cookie) {
      cookies[cookie.name] = cookie;
    });
    return cookies;
  }

  /**
   * This method copied from [dart.io][_HttpHeaders._parseCookies()] and little modified.
   *
   * See detail Dart sdk repository.
   * https://code.google.com/p/dart/source/browse/branches/1.10/dart/LICENSE
   * https://code.google.com/p/dart/source/browse/branches/1.10/dart/sdk/lib/io/http_headers.dart
   */
  static List<Cookie> _parseCookies(String rawCookie) {
    var cookies = new List<Cookie>();

    int index = 0;

    bool done() => index == -1 || index == rawCookie.length;

    void skipWS() {
      while (!done()) {
        if (rawCookie[index] != " " && rawCookie[index] != "\t") return;
        index++;
      }
    }

    String parseName() {
      int start = index;
      while (!done()) {
        if (rawCookie[index] == " " || rawCookie[index] == "\t" || rawCookie[index] == "=") break;
        index++;
      }
      return rawCookie.substring(start, index);
    }

    String parseValue() {
      int start = index;
      while (!done()) {
        if (rawCookie[index] == " " || rawCookie[index] == "\t" || rawCookie[index] == ";") break;
        index++;
      }
      return rawCookie.substring(start, index);
    }

    bool expect(String expected) {
      if (done()) return false;
      if (rawCookie[index] != expected) return false;
      index++;
      return true;
    }

    while (!done()) {
      skipWS();
      if (done()) break;
      String name = parseName();
      skipWS();
      if (!expect("=")) {
        index = rawCookie.indexOf(';', index);
        continue;
      }
      skipWS();
      String value = parseValue();
      try {
        cookies.add(new Cookie(name, value));
      } catch (_) {
        // Skip it, invalid cookie data.
      }
      skipWS();
      if (done()) break;
      if (!expect(";")) {
        index = rawCookie.indexOf(';', index);
        continue;
      }
    }
    return cookies;
  }
}
