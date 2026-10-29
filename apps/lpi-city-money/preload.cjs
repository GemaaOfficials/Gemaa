const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("lpiUpdater", {
  downloadReleaseAsset: (url, filename) =>
    ipcRenderer.invoke("lpi:download-release-asset", { url, filename }),
  onProgress: (callback) => {
    if (typeof callback !== "function") return () => {};
    const listener = (_event, progress) => callback(progress);
    ipcRenderer.on("lpi:update-progress", listener);
    return () => ipcRenderer.removeListener("lpi:update-progress", listener);
  },
  showDownloadedFile: () => ipcRenderer.invoke("lpi:show-downloaded-file")
});
