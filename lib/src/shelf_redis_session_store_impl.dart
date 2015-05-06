part of shelf_redis_session_store;

/**
 * [RedisSession] is stored session object in Redis stored by [RedisSessionStore].
 * Create for management [shelf] session.
 * You can use this like Map object.
 *
 * Do not create [RedisSession] instance yourself.
 * Please read usage of [redisSessionMiddleware].
 *
 * For example:
 *
 *      RedisSession session = request.context['sessions'];
 *      var userID = session['userID']; //get (from memory)
 *      session['lastLoginAt'] = new DateTime.now(); //modified (to memory. A timing of save to Redis is response process)
 *
 *      //Note: [RedisSessionStore.SERIALIZED_KEY] (__serialized__) is reserved key of Map value.
 *      //You can use about this
 *      session['__serialized__'] = foo;
 *
 *      //But you can NOT use about this ( throws ArgumentError )
 *      session['foo'] = { '__serialized__': bar }
 */
class RedisSession extends Object with MapMixin<String, Object> implements HttpSession {
  final RedisSessionStore _store;
  String _id;
  bool _isNew;
  Map<String, Object> _data;

  /**
   * Do not create RedisSession yourself.
   * You can create this by [RedisSessionStore.create()] or [redisSessionMiddleware].
   */
  RedisSession(this._store, this._id, this._isNew, {Map<String, Object> data}) {
    if (data is! Map<String, Object>) {
      data = new Map<String, Object>();
    }
    this._data = data;
  }

  Map<String, Object> get data => this._data;

  /**
   * Gets the id for the current session.
   */
  String get id => this._id;

  /**
   * Destroys the session. This will terminate the session and any further
   * connections with this id will be given a new id and session.
   */
  void destroy() {
    this._store.remove(this.id);
  }

  /**
   * Sets a callback that will be called when the session is timed out.
   */
  void set onTimeout(_) {
    //do nothing. because timeout management by Redis expires.
  }

  /**
   * Is true if the session has not been sent to the client yet.
   */
  bool get isNew => this._isNew;

  //for MapMixin methods
  Iterable<String> get keys => this._data.keys;

  Object operator [](String key) => this._data[key];

  operator []=(String key, Object value) {
    if (value is Map && (value as Map).containsKey(RedisSessionStore.SERIALIZED_KEY)) {
      throw new ArgumentError("${RedisSessionStore.SERIALIZED_KEY} is reserved Map key for session.");
    }
    this._data[key] = value;
  }

  Object remove(String key) => this._data.remove(key);

  void clear() => this._data.clear();
}

/**
 * [RedisSessionStore] has 4 tasks on request start.
 * 1. read (and parse) request cookie for get session ID.
 * 2. get session data from Redis
 * 3. deserialize to Dart Map object
 * 4. create [RedisSession] instance
 *
 * And has 3 tasks before send response.
 * 1. serialize session data from [RedisSession] instance
 * 2. store serialized session data to Redis
 * 3. add session-id cookie to response cookies
 *
 * [redisSessionMiddleware] requires [RedisSessionStore] instance.
 *
 */
class RedisSessionStore {
  static const SERIALIZED_KEY = "__serialized__";
  static const SERIALIZED_VALUE_KEY = "__value__";

  static const SESSION_CONTEXT_KEY = "session";
  static const DEFAULT_SESSION_COOKIE_NAME = "DARTREDISSESSION";
  static const SESSION_IDS_INCREMENT_KEY = "dartredissessionid";
  static const STORED_SESSION_ID_PREFIX = "dart_";

  Command _redisCommand;
  String _sessionIdSalt;
  Duration _sessionExpireTime;
  String _sessionCookieName;
  String _redisSessionIncrementKey;
  String _storedSessionIdPrefix;

  Function _serialize;
  Function _deserialize;

  /**
   * [_redisCommand] : [Command] (is [redis] library's class) instance
   * [_sessionIdSalt] : this salt use for create secure session ID
   * [sessionExpireTime] : This expire use for Redis key expires time
   * [cookieName] : session ID's cookie key
   * [redisSessionIncrementKey] : on generate sessionID [RedisSessionStore] uses Redis "INCR" command
   * [storeSessionIdPrefix] : key prefix for redis
   * [serialize] & [deserialize] :
   *   [RedisSessionStore] serialize & deserialize by [JSON].encode/decode.
   *   And [JSON] does not support some object, for example [DateTime], [Set].
   *   But we want to use [DateTime] for session.
   *   So we need serialize and deserialize.
   *   [RedisSessionStore]'s default serializer is [serializeData] and deserializer is [deserializeData].
   *       (Currently supports: [JSON.encode] supports object, DateTime, Set and Duration.)
   *   When you want to handle original serialize / deserialize, you can override these.
   */
  RedisSessionStore(this._redisCommand, this._sessionIdSalt, {Duration sessionExpireTime: const Duration(hours: 1),
      String cookieName, String redisSessionIncrementKey: RedisSessionStore.SESSION_IDS_INCREMENT_KEY,
      String storedSessionIdPrefix: RedisSessionStore.STORED_SESSION_ID_PREFIX,
      Function serialize(Map<String, Object> data), Function deserialize(Map<String, Object> data)}) {
    this._sessionExpireTime = sessionExpireTime;
    this._sessionCookieName = cookieName == null ? RedisSessionStore.DEFAULT_SESSION_COOKIE_NAME : cookieName;
    this._redisSessionIncrementKey = redisSessionIncrementKey;
    this._storedSessionIdPrefix = storedSessionIdPrefix;
    this._serialize = serialize is! Function ? this.serializeData : serialize;
    this._deserialize = deserialize is! Function ? this.deserializeData : deserialize;
  }

  /// for redisSessionMiddleware
  Future<Request> loadSession(Request request) async {
    var completer = new Completer();

    //Parse cookies
    if (!request.context.containsKey('cookies')) {
      request = ShelfCookieParser.updateRequest(request);
    }

    Map<String, Cookie> cookies = request.context['cookies'];

    RedisSession session;
    if (cookies.containsKey(this._sessionCookieName)) {
      session = await this.get(cookies[this._sessionCookieName].value);
    }
    if (session == null) {
      session = await this.create(request.hashCode.toString());
    }

    completer.complete(request.change(context: {RedisSessionStore.SESSION_CONTEXT_KEY: session}));

    return completer.future;
  }

  /// for redisSessionMiddleware
  Future<Response> storeSession(Request request, Response response) async {
    var completer = new Completer();
    RedisSession session = request.context[RedisSessionStore.SESSION_CONTEXT_KEY];
    bool succeed = await this.save(session);
    if (succeed) {
      var cookie = new Cookie(this._sessionCookieName, session.id);
      cookie.httpOnly = true;
      String setCookie = cookie.toString();
      if (request.headers.containsKey(HttpHeaders.SET_COOKIE)) {
        setCookie = "${request.headers[HttpHeaders.SET_COOKIE]} ${setCookie}";
      }
      completer.complete(response.change(headers: {HttpHeaders.SET_COOKIE: setCookie}));
    } else {
      completer.completeError('save failed');
    }

    return completer.future;
  }

  /// you can override this or use others
  Map<String, Object> serializeData(Map<String, Object> originalData) {
    Map<String, Object> serialized = new Map<String, Object>();
    originalData.forEach((String key, Object value) {
      serialized[key] = this._serializeData(value);
    });
    return serialized;
  }

  Object _serializeData(dynamic value) {
    if (value is DateTime) {
      return {SERIALIZED_KEY: "DateTime", SERIALIZED_VALUE_KEY: (value as DateTime).millisecondsSinceEpoch};
    } else if (value is Duration) {
      return {SERIALIZED_KEY: "Duration", SERIALIZED_VALUE_KEY: (value as Duration).inMicroseconds};
    } else if (value is Set) {
      return {SERIALIZED_KEY: "Set", SERIALIZED_VALUE_KEY: this._serializeData((value as Set).toList())};
    } else if (value is Map) {
      return (value as Map).values.map((Object val) => this._serializeData(val)).toList();
    } else if (value is Iterable) {
      return (value as Iterable).map((Object val) => this._serializeData(val)).toList();
    }
    return value;
  }

  /// you can override this or use others
  Map<String, Object> deserializeData(Map<String, Object> originalData) {
    Map<String, Object> deserialized = new Map<String, Object>();
    originalData.forEach((String key, Object value) {
      deserialized[key] = this._deserializeData(value);
    });
    return deserialized;
  }

  Object _deserializeData(dynamic value) {
    if (value is Map && (value as Map).containsKey(SERIALIZED_KEY)) {
      var serializedType = (value as Map)[SERIALIZED_KEY];
      var innerValue = (value as Map)[SERIALIZED_VALUE_KEY];
      if (serializedType == 'Set') {
        return new Set.from(this._deserializeData(innerValue));
      } else if (serializedType == 'DateTime') {
        return new DateTime.fromMillisecondsSinceEpoch(innerValue);
      } else if (serializedType == "Duration") {
        return new Duration(microseconds: innerValue);
      }
    } else if (value is Map) {
      return (value as Map).values.map((Object val) => this._deserializeData(val)).toList();
    } else if (value is Iterable) {
      return (value as Iterable).map((Object val) => this._deserializeData(val)).toList();
    } else {
      return value;
    }
  }

  /// Get session data from Redis by sessionID
  Future<RedisSession> get(String sessionId) async {
    var completer = new Completer();
    String rawSession = await this._redisCommand.get(this._getStoredSessionId(sessionId));
    if (rawSession == null || rawSession is! String || rawSession.length == 0) {
      completer.complete(null);
    } else {
      try {
        Map<String, Object> sessionData = JSON.decode(rawSession);
        RedisSession session =
            new RedisSession(this, (sessionData['id'] as String), false, data: this._deserialize(sessionData['data']));
        completer.complete(session);
      } on FormatException catch (error) {
        completer.completeError(error);
      }
    }
    return completer.future;
  }

  /// Create new [RedisSession] instance
  Future<RedisSession> create(String sessionIdSalt) async {
    var completer = new Completer();
    String sessionId = await this._generateSessionId(sessionIdSalt);
    var session = new RedisSession(this, sessionId, false);
    if (await this.save(session)) {
      completer.complete(session);
    } else {
      completer.completeError("creation failed");
    }
    return completer.future;
  }

  /// Remove exists session on Redis by sessionID
  Future<bool> remove(String sessionId) async {
    var completer = new Completer();
    int removedKeysCount = await this._redisCommand.send_object(['DEL', this._getStoredSessionId(sessionId)]);
    completer.complete(removedKeysCount == 1);
    return completer.future;
  }

  /// Update session by [RedisSession] instance
  Future<bool> save(RedisSession session) async {
    var completer = new Completer();
    String sessionJson = JSON.encode({'id': session.id, 'data': this._serialize(session.data),});
    String result = await this._redisCommand.send_object(
        ["SETEX", this._getStoredSessionId(session.id), this._sessionExpireTime.inSeconds.toString(), sessionJson]);
    completer.complete(result.toLowerCase() == 'ok');
    return completer.future;
  }

  /// Generate sessionID
  Future<String> _generateSessionId(String salt) async {
    var completer = new Completer();
    int uniqueID = await this._redisCommand.send_object(['INCR', this._redisSessionIncrementKey]);
    String hash = Crypt.sha256([
      this._sessionIdSalt,
      salt,
      new DateTime.now().millisecondsSinceEpoch.toString(),
      new Random().nextDouble().toString(),
    ].join(':'), salt: uniqueID.toString());
    completer.complete(hash);
    return completer.future;
  }

  /// Get sessionID which stored on Reids
  String _getStoredSessionId(String sessionId) {
    return this._storedSessionIdPrefix + sessionId;
  }
}
