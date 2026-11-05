import { mwb } from "./index";

// 浏览器脚本入口只挂载 MWB；ESM 使用者可直接导入 mwb。
window.mwb = mwb;
