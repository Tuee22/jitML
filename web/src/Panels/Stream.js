// Sprint 13.13 — minimal WebSocket FFI for the demo's live-frame bridge.
// Resolves the path against the current origin (ws/wss per page protocol),
// forwards each text frame to the PureScript callback, and reports failures
// through the panel's typed error action.
export function openWebSocket(path) {
  return function (callback) {
    return function (onFailure) {
      return function () {
        try {
          var loc = window.location;
          var proto = loc.protocol === "https:" ? "wss:" : "ws:";
          var url = proto + "//" + loc.host + path;
          var ws = new WebSocket(url);
          ws.onmessage = function (event) {
            callback(String(event.data))();
          };
          ws.onerror = function () {
            onFailure("websocket error: " + path)();
          };
          ws.onclose = function (event) {
            if (!event.wasClean) {
              onFailure("websocket closed: " + path)();
            }
          };
        } catch (e) {
          onFailure(String(e && e.message ? e.message : e))();
        }
        return {};
      };
    };
  };
}
