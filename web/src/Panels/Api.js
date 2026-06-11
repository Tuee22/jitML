export function requestTextImpl(method) {
  return function (path) {
    return function (body) {
      return function (onSuccess) {
        return function (onFailure) {
          return function () {
            fetch(path, {
              method: method,
              headers: { "content-type": "text/plain; charset=utf-8" },
              body: method === "GET" ? undefined : body
            })
              .then(function (response) {
                return response.text().then(function (text) {
                  if (response.ok) {
                    onSuccess(text)();
                  } else {
                    onFailure(text || response.statusText)();
                  }
                });
              })
              .catch(function (error) {
                onFailure(String(error && error.message ? error.message : error))();
              });
            return {};
          };
        };
      };
    };
  };
}
