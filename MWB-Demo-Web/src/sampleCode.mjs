/** 根据当前参数生成可复制的 SDK 调用代码，事件示例保留回调引用。 */
export function sampleCode(example, input) {
  const name = example.name;
  let args;
  try { args = JSON.parse(input); if (!Array.isArray(args)) throw new Error(); }
  catch { return '// 请修正参数 JSON 后查看调用代码。'; }
  const handlerName = JSON.stringify(args[0] ?? 'nativeGreeting');
  if (name === 'registerHandler') return `const handler = message => {\n  console.log("原生消息", message);\n};\nmwb.registerHandler(${handlerName}, handler);`;
  if (name === 'unRegisterHandler') return `mwb.unRegisterHandler(${handlerName}, handler); // 与注册时使用同一函数`;
  if (name === 'onBackBtnPressed') return 'mwb.onBackBtnPressed(() => false); // false 交给原生继续返回';
  if (name === 'offBackBtnPressed') return 'mwb.offBackBtnPressed();';
  if (name.startsWith('on')) return `const handler = data => console.log(data);\nmwb.${name}(handler);`;
  if (name.startsWith('off')) return `mwb.${name}(handler); // 使用订阅时的同一个回调`;
  const parameters = args.map(arg => JSON.stringify(arg, null, 2)).join(',\n');
  const isAsync = !name.endsWith('Sync') && name !== 'setEnableDebug' && name !== 'checkHandlerExist' && !name.startsWith('unRegister');
  const noResult = ['setEnableDebug', 'setStorageSync', 'removeStorageSync', 'clearStorageSync', 'unRegisterHandlers', 'unRegisterHandler'].includes(name);
  return `${noResult ? '' : 'const result = '}${isAsync ? 'await ' : ''}mwb.${name}(${parameters});`;
}
