const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const htmlPath = path.join(__dirname, "..", "index.html");
const html = fs.readFileSync(htmlPath, "utf8");
const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)];
const inlineScripts = scripts.filter((match) => !/\bsrc\s*=/.test(match[1]) && match[2].trim());
if (inlineScripts.length === 0) {
  throw new Error("No inline application JavaScript was found.");
}
for (let i = 0; i < inlineScripts.length; i++) {
  new vm.Script(inlineScripts[i][2], { filename: "index.html:inline-script-" + (i + 1) });
}
const appMarkup = html.slice(0, html.lastIndexOf("<script>"));
const ids = [...appMarkup.matchAll(/\bid=["']([^"']+)["']/g)].map((match) => match[1]);
const duplicates = ids.filter((id, index) => ids.indexOf(id) !== index);
if (duplicates.length) {
  throw new Error("Duplicate static HTML IDs: " + [...new Set(duplicates)].join(", "));
}
for (const expected of ["APP_VERSION", "renderMediaCards", "renderAdminSpinConfig", "checkForUpdates", "showReceipt"]) {
  if (!html.includes(expected)) throw new Error("Missing app feature: " + expected);
}
console.log("LPI HTML checks passed: " + inlineScripts.length + " inline script(s), " + ids.length + " static IDs, no duplicate IDs.");
