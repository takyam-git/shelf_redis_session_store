library shelf_cookie;

import "dart:io";
import "package:shelf/shelf.dart";

part "src/shelf_cookie_impl.dart";

/**
 * [cookieMiddleware] is simple cookie parser for shelf.
 * note:  This middleware does NOT add to request.headers (Because, Shelf's headers is [Map<String,String>]).
 *        You can use 'cookies' (or argument contextKey) in request.context.
 *        And 'cookies' type is [Map<String, Cookie>] (Not <String,String>). See detail 'example usage'.
 * example usage:
 *        var handler = const shelf.Pipeline()
 *            .addMiddleware(cookieMiddleware())
 *            .addHandler(someHandler);
 *
 *        shelf.Response someHandler(shelf.Request request){
 *            Map<String,Cookie> cookies = request.context['cookies'];
 *            String sessionID = null;
 *            if (cookies.containsKey('session') ) {
 *                sessionID = cookies['session'].value
 *            }
 *        }
 */
Middleware cookieMiddleware({String contextKey: 'cookies'}) {
  return (Handler innerHandler) {
    return (Request request) {
      return innerHandler(ShelfCookieParser.updateRequest(request, contextKey: contextKey));
    };
  };
}
