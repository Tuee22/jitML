// Sprint 13.13 — minimal WebSocket FFI for the demo's live-frame bridge.
// Resolves the path against the current origin (ws/wss per page protocol)
// and forwards each text frame to the PureScript callback. Best-effort:
// any failure leaves the deterministic shell rendering.
export function openWebSocket(path) {
  return function (callback) {
    return function () {
      try {
        var loc = window.location;
        var proto = loc.protocol === "https:" ? "wss:" : "ws:";
        var url = proto + "//" + loc.host + path;
        var ws = new WebSocket(url);
        ws.onmessage = function (event) {
          callback(String(event.data))();
        };
      } catch (e) {
        // ignore — demo keeps its deterministic shell
      }
      return {};
    };
  };
}
