library shelf_redis_session_store;

import "dart:io";
import "dart:async";
import "dart:convert";
import "dart:math";
import "dart:collection";

import "package:redis/redis.dart";
export "package:redis/redis.dart" show RedisConnection, Command;
import "package:shelf/shelf.dart";
import "package:crypt/crypt.dart";

import "shelf_cookie.dart" show ShelfCookieParser;

part "src/shelf_redis_session_store_impl.dart";

/**
 * FIXME: My English X(
 *
 * [redisSessionMiddleware] is session management middleware for shelf.
 *
 * This library implements 2 classes, [RedisSessionStore] and [RedisSession].
 * This middleware requires [RedisSessionStore] instance.
 * Please read document of these classes.
 *
 * Note: [RedisConnection] and [Command] are [redis] library classes.
 *       See detail [here](https://pub.dartlang.org/packages/redis).
 *
 * Usage For Example:
 *      var redisSessionStore = new RedisSessionStore(
 *          await new RedisConnection().connect('localhost', 6379),
 *          "SOMETHING_SALT",
 *          sessionExpireTime: const Duration(hours:4),
 *          cookieName: 'mysessionkey'
 *      );
 *
 *      var handler = const shelf.Pipeline()
 *          .addMiddleware(cookieMiddleware()) //if not exists this, then redisSessionMiddleware parses cookies
 *          .addMiddleware(redisSessionMiddleware(redisSessionStore))
 *          .addHandler(_echoRequest);
 */
Middleware redisSessionMiddleware(RedisSessionStore redisSessionStore) {
  return (Handler innerHandler) {
    return (Request request) async {
      var sessionAddedRequest = await redisSessionStore.loadSession(request);
      Response response = await innerHandler(sessionAddedRequest);
      return redisSessionStore.storeSession(sessionAddedRequest, response);
    };
  };
}
