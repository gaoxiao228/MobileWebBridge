// 示例执行器把参数编辑、事件回调和 SDK 调用分开，页面只负责展示结果。
const placeholders = {
  '{{imageBase64}}': ['imageBase64', '请先选择图片。'],
  '{{imagePath}}': ['imagePath', '请先执行“选择图片”。'],
  '{{currentURL}}': ['currentURL', '当前示例页地址不可用。'],
  '{{phoneNumber}}': ['phoneNumber', '请在参数中填写要拨打的电话号码。'],
  '{{pdfURL}}': ['pdfURL', '请在参数中填写可访问的 HTTPS PDF 地址。']
};

export function resolveArgs(example, input, context = {}) {
  let values;
  try {
    values = JSON.parse(input);
  } catch {
    throw new Error('参数不是有效的 JSON，请检查逗号和引号。');
  }
  if (!Array.isArray(values)) throw new Error('参数必须是 JSON 数组，例如 [{"msg":"你好"}]。');

  function replace(value) {
    if (Array.isArray(value)) return value.map(replace);
    if (value && typeof value === 'object') {
      return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, replace(entry)]));
    }
    if (value === '{{nativePageName}}') return context.platform === 'android' ? 'sample' : 'demo';
    if (typeof value === 'string' && placeholders[value]) {
      const [field, message] = placeholders[value];
      if (!context[field]) throw new Error(message);
      return context[field];
    }
    return value;
  }

  const args = values.map(replace);
  const first = args[0];
  const requiredString = (field, description) => {
    if (!first || typeof first !== 'object' || typeof first[field] !== 'string' || !first[field].trim()) {
      throw new Error(`${description}是必填参数。`);
    }
  };
  // 编辑器允许删除整段 JSON，调用原生前仍要守住示例所需的关键输入。
  if (['compressImage', 'saveImageToPhotosAlbum'].includes(example.name)) requiredString('base64Image', '图片 Base64');
  if (example.name === 'convertImagePathToBase64') requiredString('path', '图片路径');
  if (example.name === 'openFile') requiredString('url', 'PDF 地址');
  if (example.name === 'makePhoneCall') requiredString('phoneNumber', '电话号码');
  if (example.name === 'navigateTo') requiredString('url', '页面地址');
  if (example.name === 'openNativePage') requiredString('pageName', '原生页面名称');
  return args;
}

export function createRunner(sdk, emit) {
  const callbacks = new Map();
  const jsHandlers = new Map();

  async function run(example, input, context = {}) {
    if (!sdk) throw new Error('MWB SDK 未加载，请检查 mwb.iife.js。');
    const args = resolveArgs(example, input, context);
    const { name } = example;

    if (name === 'registerHandler') {
      const handlerName = args[0];
      if (!handlerName || typeof handlerName !== 'string') throw new Error('请填写 JS 句柄名称。');
      if (jsHandlers.has(handlerName)) return '该 JS 句柄已注册。';
      const handler = message => {
        emit({ method: name, data: message });
      };
      sdk.registerHandler(handlerName, handler);
      jsHandlers.set(handlerName, handler);
      return `已注册 ${handlerName}，等待原生调用。`;
    }
    if (name === 'unRegisterHandler') {
      const handler = jsHandlers.get(args[0]);
      if (!handler) return '当前页面尚未注册该句柄。';
      sdk.unRegisterHandler(args[0], handler);
      jsHandlers.delete(args[0]);
      return `已解绑 ${args[0]} 的示例回调。`;
    }
    if (name === 'unRegisterHandlers') {
      sdk.unRegisterHandlers(args[0]);
      jsHandlers.delete(args[0]);
      return `已解绑 ${args[0]} 的全部回调。`;
    }
    if (name === 'onBackBtnPressed') {
      const handler = () => { emit({ method: name, data: '已交给原生继续返回' }); return false; };
      sdk.onBackBtnPressed(handler);
      callbacks.set(name, handler);
      return '已注册返回键回调；返回 false 时由原生继续处理。';
    }
    if (name === 'offBackBtnPressed') {
      sdk.offBackBtnPressed();
      callbacks.delete('onBackBtnPressed');
      return '已取消返回键回调。';
    }
    if (name.startsWith('on')) {
      if (callbacks.has(name)) return '当前事件已经订阅。';
      const handler = data => emit({ method: name, data });
      sdk[name](handler);
      callbacks.set(name, handler);
      return '已订阅，等待原生事件。';
    }
    if (name.startsWith('off')) {
      const onName = `on${name.slice(3)}`;
      const handler = callbacks.get(onName);
      if (!handler) return '当前页面尚未订阅该事件。';
      sdk[name](handler);
      callbacks.delete(onName);
      return '已取消订阅。';
    }
    if (typeof sdk[name] !== 'function') throw new Error(`当前 SDK 不包含 ${name} 方法。`);
    return await sdk[name](...args);
  }

  return { run };
}
