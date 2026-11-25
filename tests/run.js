// Runs every tests/specs/*.lua (or the files given) in a fresh Lua state with the WoW stub.
// Usage: npm test            node run.js specs/tracker.lua
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

// Self-contained TOC + XML loader (so standalone BegBuddy tests need no monorepo ../tools).
const slashes = (s) => s.replace(/\\/g, "/");
function xmlFiles(addonDir, rel) {
  const dir = path.posix.dirname(rel);
  const src = fs.readFileSync(path.join(addonDir, rel), "latin1");
  return [...src.matchAll(/<Script\s+file="([^"]+)"/g)].map((m) => path.posix.join(dir, slashes(m[1])));
}
function tocFiles(addonDir, tocName) {
  const lines = fs.readFileSync(path.join(addonDir, tocName), "latin1").split(/\r?\n/).map((l) => slashes(l.trim()));
  const out = [];
  for (const l of lines) {
    if (l.startsWith("#") || !l) continue;
    if (l.endsWith(".lua")) out.push(l);
    else if (l.endsWith(".xml")) out.push(...xmlFiles(addonDir, l));
  }
  return out.map((f) => f.slice(0, -4));
}

const addon = path.join(__dirname, "..", "BegBuddy");
const specs = process.argv.length > 2
  ? process.argv.slice(2).map((p) => path.resolve(p))
  : fs.readdirSync(path.join(__dirname, "specs")).filter((f) => f.endsWith(".lua")).sort()
      .map((f) => path.join(__dirname, "specs", f));
const harness = fs.readFileSync(path.join(__dirname, "harness.lua"), "latin1");
// The addon's files, in the TOC's order (its ZipUI copy first), so a file added there is always under test.
const files = tocFiles(addon, "BegBuddy.toc");

let failed = 0;
for (const spec of specs) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_pushstring(L, to_luastring(files.join(",")));
  lua.lua_setglobal(L, to_luastring("TOC_FILES"));
  for (const f of files) {
    lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(addon, f + ".lua"), "latin1"), true));
    lua.lua_setglobal(L, to_luastring("SRC_" + f));
  }
  console.log("-- " + path.basename(spec));
  const code = harness + "\n" + fs.readFileSync(spec, "latin1") + "\nreturn FAILED or 0";
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code, true), null, to_luastring(path.basename(spec))) !== lua.LUA_OK ||
      lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    console.log("LUA ERROR: " + lua.lua_tojsstring(L, -1));
    failed++;
    continue;
  }
  failed += lua.lua_tointeger(L, -1);
}
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);

