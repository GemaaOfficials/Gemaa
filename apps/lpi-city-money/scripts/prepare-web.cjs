const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const webDir = path.join(root, "www");
fs.mkdirSync(webDir, { recursive: true });
fs.copyFileSync(path.join(root, "index.html"), path.join(webDir, "index.html"));
console.log("Prepared LPI City Money web asset for Capacitor.");