import { callAsync } from "../bridge";
import type { MWBJSSDK } from "../types";

/** 图片、扫码、权限及文件能力。 */
export const mediaPlugin = {
  name: "media",
  methods: {
    compressImage(param) { return callAsync("compressImage", param); },
    scanCode(param) { return callAsync("scanCode", param); },
    saveImageToPhotosAlbum(param) { return callAsync("saveImageToPhotosAlbum", param); },
    chooseImage(param) { return callAsync("chooseImage", param); },
    openFile(param) { return callAsync("openFile", param); },
    checkRequestCameraPermissions(param) { return callAsync("checkRequestCameraPermissions", param); },
    convertImagePathToBase64(param) { return callAsync("convertImagePathToBase64", param); }
  } satisfies Pick<MWBJSSDK,
    "compressImage" | "scanCode" | "saveImageToPhotosAlbum" | "chooseImage" |
    "openFile" | "checkRequestCameraPermissions" |
    "convertImagePathToBase64">
} as const;
