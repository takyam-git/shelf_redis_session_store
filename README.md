# shelf_redis_session_store

* This is shelf middleware that stores session data to Redis.

**TODO: write README, add examples, add coverage**


FIXME: My English X(

[redisSessionMiddleware] is session management middleware for shelf.

This library implements 2 classes, [RedisSessionStore] and [RedisSession].
This middleware requires [RedisSessionStore] instance.
Please read document of these classes.
 
Note: [RedisConnection] and [Command] are [redis] library classes.
     See detail [here](https://pub.dartlang.org/packages/redis).

```
Usage For Example:

var redisSessionStore = new RedisSessionStore(
    await new RedisConnection().connect('localhost', 6379),
    "SOMETHING_SALT",
    sessionExpireTime: const Duration(hours:4),
    cookieName: 'mysessionkey'
);

var handler = const shelf.Pipeline()
    .addMiddleware(cookieMiddleware()) //if not exists this, then redisSessionMiddleware parses cookies
    .addMiddleware(redisSessionMiddleware(redisSessionStore))
    .addHandler(_echoRequest);
```