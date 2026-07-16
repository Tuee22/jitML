// Sprint 13.13 — minimal WebSocket FFI for the demo's live-frame bridge.
// Resolves the path against the current origin (ws/wss per page protocol),
// forwards each text frame to the PureScript callback, and reports failures
// through the panel's typed error action.
export function openWebSocket(path) {
  return function (callback) {
    return function (onFailure) {
      return function () {
        var active = true;
        var ws = null;
        try {
          var loc = window.location;
          var proto = loc.protocol === "https:" ? "wss:" : "ws:";
          var url = proto + "//" + loc.host + path;
          ws = new WebSocket(url);
          ws.onmessage = function (event) {
            if (active) {
              callback(String(event.data))();
            }
          };
          ws.onerror = function () {
            if (active) {
              onFailure("websocket error: " + path)();
            }
          };
          ws.onclose = function (event) {
            if (active && !event.wasClean) {
              onFailure("websocket closed: " + path)();
            }
          };
        } catch (e) {
          if (active) {
            onFailure(String(e && e.message ? e.message : e))();
          }
        }
        return function () {
          if (!active) {
            return {};
          }
          active = false;
          if (ws !== null) {
            ws.onmessage = null;
            ws.onerror = null;
            ws.onclose = null;
            if (ws.readyState === 0 || ws.readyState === 1) {
              try {
                ws.close(1000, "component disposed");
              } catch (_closeError) {
                // The server-side peer watcher still observes abrupt teardown.
              }
            }
          }
          return {};
        };
      };
    };
  };
}
