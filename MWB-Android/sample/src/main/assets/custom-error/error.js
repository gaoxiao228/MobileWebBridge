// 在主文档完成后接收原生注入的专用接口，无需引入 mwb.iife.js。
(() => {
  const retry = document.querySelector('.retry');
  const home = document.querySelector('.home');
  function render() {
    const state = window.mwbErrorPage?.context;
    if (!state) return;
    document.querySelector('.description').textContent = state.message;
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
