export function onHashChange(callback) {
  return function () {
    window.addEventListener("hashchange", function () {
      callback();
    });
  };
}
