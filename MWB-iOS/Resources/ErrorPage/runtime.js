// 原生在受限本地文档完成后注入；不向网页暴露目标 URL 或原生对象。
(() => {
  window.__mwbInstallErrorPage = (initial, dispatch) => {
    window.__mwbErrorRuntime?.dispose();
    let active = true;
    let snapshot = Object.freeze({ ...initial });
    const api = Object.freeze({
      get context() { return snapshot; },
      retry() { if (active && snapshot.canRetry && !snapshot.isRetrying) dispatch('retry'); },
      goHome() { if (active && snapshot.canGoHome) dispatch('goHome'); }
    });
    Object.defineProperty(window, 'mwbErrorPage', { value: api, configurable: true });
    const runtime = {
      update(next) {
        if (!active) return;
        snapshot = Object.freeze({ ...next });
        window.dispatchEvent(new Event('mwb-error-state-change'));
      },
      dispose() { active = false; }
    };
    window.__mwbErrorRuntime = runtime;
    window.dispatchEvent(new Event('mwb-error-ready'));
    return runtime;
  };
})();
