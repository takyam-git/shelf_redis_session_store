library shelf_cookie.test;

import "dart:io";

import "package:shelf/shelf.dart";
import "package:shelf_redis_session_store/shelf_cookie.dart";

import "package:test/test.dart";

void main() {
  test("cookieMiddleware works", () {
    var req = new Request('GET', new Uri.http("example.com", "/"), headers: {HttpHeaders.COOKIE: "a=1; b=2;",});
    Handler handler = (Request request) {
      expect(request.context, contains('cookies'));
      Map<String, Cookie> cookies = request.context['cookies'];
      expect(cookies, isMap);
      expect(cookies.length, equals(2));
      expect(cookies, contains('a'));
      expect(cookies, contains('b'));
      expect(cookies['a'], new isInstanceOf<Cookie>());
      expect(cookies['b'], new isInstanceOf<Cookie>());
      expect((cookies['a'] as Cookie).value, equals('1'));
      expect((cookies['b'] as Cookie).value, equals('2'));
      return 'expect';
    };
    expect(cookieMiddleware()(handler)(req), equals('expect'));
  });

  test("parse cookies in request header", () {
    var req = new Request('GET', new Uri.http("example.com", "/"), headers: {HttpHeaders.COOKIE: "a=1; b=2;",});
    req = ShelfCookieParser.updateRequest(req);
    expect(req.context, contains('cookies'));
    Map<String, Cookie> cookies = req.context['cookies'];
    expect(cookies, isMap);
    expect(cookies.length, equals(2));
    expect(cookies, contains('a'));
    expect(cookies, contains('b'));
    expect(cookies['a'], new isInstanceOf<Cookie>());
    expect(cookies['b'], new isInstanceOf<Cookie>());
    expect((cookies['a'] as Cookie).value, equals('1'));
    expect((cookies['b'] as Cookie).value, equals('2'));
  });

  test("if there are same keys ignore first", () {
    var req =
        new Request('GET', new Uri.http("example.com", "/"), headers: {HttpHeaders.COOKIE: "a=1; a=2; a=3; x=4",});
    req = ShelfCookieParser.updateRequest(req);
    expect(req.context, contains('cookies'));
    Map<String, Cookie> cookies = req.context['cookies'];
    expect(cookies, isMap);
    expect(cookies.length, equals(2));
    expect(cookies, contains('a'));
    expect(cookies, isNot(contains('b')));
    expect(cookies['a'], new isInstanceOf<Cookie>());
    expect((cookies['a'] as Cookie).value, equals('3'));
  });

  test("wrong format cookie do not throws exceptions", () {
    var req = new Request('GET', new Uri.http("example.com", "/"),
        headers: {HttpHeaders.COOKIE: r'{"cookies": "something"}',});
    req = ShelfCookieParser.updateRequest(req);
    expect(req.context, contains('cookies'));
    Map<String, Cookie> cookies = req.context['cookies'];
    expect(cookies, isMap);
    expect(cookies.length, equals(0));
  });

  test("skip invalid separators", () {
    var req = new Request('GET', new Uri.http("example.com", "/"), headers: {HttpHeaders.COOKIE: r'a=2  b=3  c=4',});
    req = ShelfCookieParser.updateRequest(req);
    expect(req.context, contains('cookies'));
    Map<String, Cookie> cookies = req.context['cookies'];
    expect(cookies, isMap);
    expect(cookies.length, equals(1));
    expect(cookies, contains('a'));
    expect(cookies['a'].value, equals('2'));
  });

  test("supports non whitespaces separated cookies", () {
    var req = new Request('GET', new Uri.http("example.com", "/"), headers: {HttpHeaders.COOKIE: r'a=1;b=2',});
    req = ShelfCookieParser.updateRequest(req);
    expect(req.context, contains('cookies'));
    Map<String, Cookie> cookies = req.context['cookies'];
    expect(cookies, isMap);
    expect(cookies.length, equals(2));
    expect(cookies.keys, contains("a"));
    expect(cookies.keys, contains("b"));
  });

  test("supports multiple equals in single cookie", () {
    var req =
        new Request('GET', new Uri.http("example.com", "/"), headers: {HttpHeaders.COOKIE: r'a=====1====2====;b=2',});
    req = ShelfCookieParser.updateRequest(req);
    expect(req.context, contains('cookies'));
    Map<String, Cookie> cookies = req.context['cookies'];
    expect(cookies, isMap);
    expect(cookies.length, equals(2));
    expect(cookies.keys, contains("a"));
    expect(cookies.keys, contains("b"));
    expect(cookies['a'].value, equals('====1====2===='));
    expect(cookies['b'].value, equals('2'));
  });

  test("Do not decode urlencoded", () {
    var req = new Request('GET', new Uri.http("example.com", "/"), headers: {HttpHeaders.COOKIE: 'a=x%2C5;b=2;',});
    req = ShelfCookieParser.updateRequest(req);
    expect(req.context, contains('cookies'));
    Map<String, Cookie> cookies = req.context['cookies'];
    expect(cookies, isMap);
    expect(cookies.length, equals(2));
    expect(cookies.keys, contains("a"));
    expect(cookies.keys, contains("b"));
    expect(cookies['a'].value, equals('x%2C5'));
    expect(cookies['b'].value, equals('2'));
  });
}
