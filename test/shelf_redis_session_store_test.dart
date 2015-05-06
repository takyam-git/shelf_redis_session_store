library shelf_redis_session_store.test;

import "dart:io";
import "dart:async";

import "package:shelf/shelf.dart";
import "package:shelf_redis_session_store/shelf_redis_session_store.dart";

import "package:test/test.dart";
import "package:mockito/mockito.dart";

void main() {
  test("redisSessionMiddleware works", () {
    var req = new Request('GET', new Uri.http("example.com", "/"),
        headers: {HttpHeaders.COOKIE: "${RedisSessionStore.DEFAULT_SESSION_COOKIE_NAME}=somevalue",});
    var res = new Response(200);
    Handler handler = (Request request) {
      expect(request.context, contains('session'));
      expect(request.context['session'], contains('some'));
      return res;
    };

    var command = new RedisCommandSpy();
    var store = new RedisSessionStore(command, "__");
    when(command.send_object(argThat(contains("SETEX")))).thenReturn("ok");
    when(command.get(any)).thenReturn(r'{"id":"someid","data":{"some":"value"}}');
    redisSessionMiddleware(store)(handler)(req).then((response) {
      expect(response, new isInstanceOf<Response>());
      expect(response.headers, contains(HttpHeaders.SET_COOKIE));
      expect(response.headers[HttpHeaders.SET_COOKIE], contains(RedisSessionStore.DEFAULT_SESSION_COOKIE_NAME));
      expect(response.headers[HttpHeaders.SET_COOKIE], contains('HttpOnly'));
    });
  });

  test("RedisSession implements HttpSession and Map", () {
    var store = new RedisStoreSpy();
    var rs = new RedisSession(store, "someid", true);
    expect(rs.isNew, isTrue);
    expect(rs, hasLength(same(0)));
    rs.destroy();
    rs['something'] = 'value';
    rs['foo'] = 'bar';
    expect(rs, hasLength(same(2)));
    expect(rs, contains('something'));
    expect(rs['something'], equals('value'));
    rs.remove('something');
    expect(rs, isNot(contains('something')));
    expect(rs, hasLength(same(1)));
    rs.clear();
    expect(rs, hasLength(same(0)));
    expect(() => rs['someMap'] = {RedisSessionStore.SERIALIZED_KEY: "something"}, throwsArgumentError);
  });

  test("RedisSessionStore create session by request", () async {
    var command = new RedisCommandSpy();
    var store = new RedisSessionStore(command, "__");
    var req = new Request('GET', new Uri.http("example.com", "/"));

    when(command.send_object(argThat(contains("SETEX")))).thenReturn("ok");

    req = await store.loadSession(req);
    expect(req.context, contains('session'));
    expect(req.context['session'], new isInstanceOf<RedisSession>());
    var rs = req.context['session'];
    expect(rs.id, isNotEmpty);
  });

  test("RedisSessionStore get session if request has sessionID cookie", () async {
    var command = new RedisCommandSpy();
    var store = new RedisSessionStore(command, "__");
    var req = new Request('GET', new Uri.http("example.com", "/"),
        headers: {HttpHeaders.COOKIE: "${RedisSessionStore.DEFAULT_SESSION_COOKIE_NAME}=COOKIE_ID;",});
    when(command.get(argThat(contains("COOKIE_ID")))).thenReturn(r'{"id":"COOKIE_ID","data":{}}');

    req = await store.loadSession(req);
    expect(req.context, contains('session'));
    expect(req.context['session'], new isInstanceOf<RedisSession>());
    var rs = req.context['session'];
    expect(rs.id, equals("COOKIE_ID"));
  });

  test("RedisSessionStore store session and set-cookie before Response", () async {
    var command = new RedisCommandSpy();
    var store = new RedisSessionStore(command, "__");
    var req = new Request('GET', new Uri.http("example.com", "/"),
        context: {RedisSessionStore.SESSION_CONTEXT_KEY: new RedisSession(store, "SOME_ID", false),});
    var res = new Response(200, headers: {HttpHeaders.SET_COOKIE: "exists=somevalues",});
    when(command.send_object(argThat(contains("SETEX")))).thenReturn("OK");
    res = await store.storeSession(req, res);
    expect(res.headers[HttpHeaders.SET_COOKIE], contains('SOME_ID'));

    //if save failure
    when(command.send_object(argThat(contains("SETEX")))).thenReturn("NG");
    expect(store.storeSession(req, res), throwsA(equals("save failed")));
  });

  test("RedisSessionStore.get returns null when session does not exists", () async {
    var command = new RedisCommandSpy();
    var store = new RedisSessionStore(command, "__");

    when(command.get(any)).thenReturn(null);

    expect(store.get("SOMETHING"), completion(isNull));
  });

  test("RedisSessionStore.get throws FormatException when session stored format is not JSON", () {
    var command = new RedisCommandSpy();
    var store = new RedisSessionStore(command, "__");
    when(command.get(any)).thenReturn("NOT JSON FORMAT VALUE");
    expect(store.get("SOMETHING"), throwsFormatException);
  });

  test("RedisSessionStore.create throws 'creation failed' when redis update failed", () {
    var command = new RedisCommandSpy();
    var store = new RedisSessionStore(command, "__");
    when(command.send_object(argThat(contains("SETEX")))).thenReturn("FAILED");
    expect(store.create("SOMETHING"), throwsA(equals("creation failed")));
  });

  test("RedisSessionStore.remove returns bool", () {
    var command = new RedisCommandSpy();
    var store = new RedisSessionStore(command, "__");
    expect(store.remove("SOMETHING"), completion(isFalse));
  });

  test("RedisSessionStore.serializeData serialize some type data", () {
    var command = new RedisCommandSpy();
    var store = new RedisSessionStore(command, "__");
    var serialized = store.serializeData({
      'dateTime': new DateTime.now(),
      'set': new Set(),
      'duration': new Duration(),
      'inMap': {"inMapDateTime": new DateTime.now()},
      'inList': [new DateTime.now(), new Duration()],
      "premitive": 1,
    });
    expect(serialized['dateTime'], isNot(new isInstanceOf<DateTime>()));
    expect(serialized['set'], isNot(new isInstanceOf<Set>()));
    expect(serialized['duration'], isNot(new isInstanceOf<Duration>()));
    expect(serialized['inMap']['inMapDateTime'], isNot(new isInstanceOf<DateTime>()));
    expect(serialized['inList'][0], isNot(new isInstanceOf<DateTime>()));
    expect(serialized['inList'][1], isNot(new isInstanceOf<Duration>()));
    expect(serialized['premitive'], equals(1));
  });

  test("RedisSessionStore.deserializeData deserialize some type data", () {
    var command = new RedisCommandSpy();
    var store = new RedisSessionStore(command, "__");
    var deserialized = store.deserializeData({
      'dateTime': {RedisSessionStore.SERIALIZED_KEY: "DateTime", RedisSessionStore.SERIALIZED_VALUE_KEY: 1},
      'duration': {RedisSessionStore.SERIALIZED_KEY: "Duration", RedisSessionStore.SERIALIZED_VALUE_KEY: 1},
      'set': {RedisSessionStore.SERIALIZED_KEY: "Set", RedisSessionStore.SERIALIZED_VALUE_KEY: ["1", "2"]},
      'inMap': {
        "inMapDateTime": {RedisSessionStore.SERIALIZED_KEY: "DateTime", RedisSessionStore.SERIALIZED_VALUE_KEY: 1}
      },
      'inList': [{RedisSessionStore.SERIALIZED_KEY: "DateTime", RedisSessionStore.SERIALIZED_VALUE_KEY: 1}],
      "premitive": "str",
    });
    expect(deserialized['dateTime'], new isInstanceOf<DateTime>());
    expect(deserialized['set'], new isInstanceOf<Set>());
    expect(deserialized['duration'], new isInstanceOf<Duration>());
    expect(deserialized['inMap']['inMapDateTime'], new isInstanceOf<DateTime>());
    expect(deserialized['inList'][0], new isInstanceOf<DateTime>());
    expect(deserialized['premitive'], equals("str"));
  });
}

class RedisCommandSpy extends Mock implements Command {}

class RedisStoreSpy extends Mock implements RedisSessionStore {}
