import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_redis_session_store/shelf_redis_session_store.dart';
import 'package:shelf_redis_session_store/shelf_cookie.dart';

main() async {
  var redisSessionStore = new RedisSessionStore(
      await new RedisConnection().connect('localhost', 6379),
      "SOMETHING_SALT",
      sessionExpireTime: const Duration(hours:4),
      cookieName: 'mysessionkey'
  );

  var handler = const shelf.Pipeline()
  .addMiddleware(shelf.logRequests())
  .addMiddleware(cookieMiddleware())
  .addMiddleware(redisSessionMiddleware(redisSessionStore))
  .addHandler(_echoRequest);

  io.serve(handler, 'localhost', 8080).then((server) {
    print('Serving at http://${server.address.host}:${server.port}');
  });
}

shelf.Response _echoRequest(shelf.Request request) {
  RedisSession session = request.context['session'];
  session['now'] = new DateTime.now();
  session['str'] = "a";
  session['int'] = 1;
  session['double'] = 1.0;
  session['num'] = -1.8;
  session['bool'] = true;
  session['list'] = [1, 2, "3", 4];
  session['map'] = {"a": 'A', 'b': 3};
  session['set'] = new Set.from(["1", "2"]);
  session['nested_list'] = [[1, 2], [3, 4], [5, 6]];
  session['nested_map'] = {"map": {"a":'A'}, "list": [1, 2, 3], "set": new Set.from([1, 2, 3])};
  session['duration'] = new Duration(seconds: 800);
  return new shelf.Response.ok('Session data : ${request.context["session"]}');
}
