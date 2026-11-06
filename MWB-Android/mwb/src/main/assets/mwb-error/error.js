// 页面只依赖错误页专用协议，不注册业务桥或插件。
(() => {
  const retry = document.getElementById('retry');
  const home = document.getElementById('home');
  const message = document.getElementById('message');
  function render() {
    const state = window.mwbErrorPage?.context;
    if (!state) return;
    message.textContent = state.message;
    retry.disabled = !state.canRetry || state.isRetrying;
    retry.textContent = state.isRetrying ? '正在重新加载…' : '重新加载';
    home.hidden = !state.canGoHome;
  }
  retry.addEventListener('click', () => window.mwbErrorPage?.retry());
  home.addEventListener('click', () => window.mwbErrorPage?.goHome());
  window.addEventListener('mwb-error-ready', render);
  window.addEventListener('mwb-error-state-change', render);
  render();
})();
