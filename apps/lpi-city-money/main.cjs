const { app, BrowserWindow, shell, ipcMain, net } = require("electron");
const path = require("node:path");
const fs = require("node:fs");
const { pipeline } = require("node:stream/promises");
const { Readable } = require("node:stream");

let lastDownloadedPath = null;

function safeUpdateUrl(rawUrl) {
  let parsed;
  try { parsed = new URL(String(rawUrl || "")); } catch { throw new Error("Invalid update URL."); }
  if (parsed.protocol !== "https:" ||
      parsed.hostname !== "github.com" ||
      !parsed.pathname.startsWith("/GemaaOfficials/Gemaa/releases/download/")) {
    throw new Error("Only official LPI release downloads are allowed.");
  }
  return parsed.href;
}

function safeFilename(rawName) {
  const filename = path.basename(String(rawName || ""));
  if (!/^[a-zA-Z0-9._-]{1,120}\.(exe|apk|zip)$/i.test(filename)) {
    throw new Error("Unsupported update filename.");
  }
  return filename;
}

ipcMain.handle("lpi:download-release-asset", async (event, payload) => {
  if (!event.senderFrame || !String(event.senderFrame.url || "").startsWith("file://")) {
    throw new Error("Update request did not come from the app window.");
  }
  const url = safeUpdateUrl(payload && payload.url);
  let filename = safeFilename(payload && payload.filename);
  const downloadsDir = app.getPath("downloads");
  let target = path.join(downloadsDir, filename);
  if (fs.existsSync(target)) {
    const ext = path.extname(filename);
    const base = path.basename(filename, ext);
    filename = base + "-" + Date.now() + ext;
    target = path.join(downloadsDir, filename);
  }
  const response = await net.fetch(url);
  if (!response.ok || !response.body) {
    throw new Error("Update server returned HTTP " + response.status + ".");
  }
  const total = Number(response.headers.get("content-length")) || 0;
  let received = 0;
  const source = Readable.fromWeb(response.body);
  source.on("data", (chunk) => {
    received += chunk.length;
    try {
      event.sender.send("lpi:update-progress", {
        received,
        total,
        percent: total ? Math.min(100, received / total * 100) : null
      });
    } catch {}
  });
  try {
    await pipeline(source, fs.createWriteStream(target));
  } catch (error) {
    try { fs.unlinkSync(target); } catch {}
    throw error;
  }
  lastDownloadedPath = target;
  try { event.sender.send("lpi:update-progress", { received, total, percent: 100, complete: true }); } catch {}
  return { ok: true, filename, path: target };
});

ipcMain.handle("lpi:show-downloaded-file", (event) => {
  if (!event.senderFrame || !String(event.senderFrame.url || "").startsWith("file://")) return false;
  if (!lastDownloadedPath || !fs.existsSync(lastDownloadedPath)) return false;
  shell.showItemInFolder(lastDownloadedPath);
  return true;
});

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 900,
    minWidth: 360,
    minHeight: 640,
    backgroundColor: "#061921",
    autoHideMenuBar: true,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  win.loadFile(path.join(__dirname, "index.html"));
  win.once("ready-to-show", () => win.show());
  win.webContents.setWindowOpenHandler(({ url }) => {
    // LPI updates use the in-app downloader; block external navigation from the renderer.
    if (url.startsWith("https://github.com/GemaaOfficials/Gemaa/releases/")) return { action: "deny" };
    if (url.startsWith("https://")) shell.openExternal(url);
    return { action: "deny" };
  });
}

app.whenReady().then(() => {
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
