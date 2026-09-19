import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { DatabaseSync } from "node:sqlite";

const mode = process.argv[2];
const root = process.argv[3] ? path.resolve(process.argv[3]) : "";
if (mode !== "game" || !root) {
  throw new Error("Usage: node build-indexes.mjs game <snapshotRoot>");
}

const indexRoot = path.join(root, "indexes");
fs.mkdirSync(indexRoot, { recursive: true });

function walk(directory) {
  if (!fs.existsSync(directory)) return [];
  const output = [];
  const pending = [directory];
  while (pending.length) {
    const current = pending.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const target = path.join(current, entry.name);
      if (entry.isDirectory()) pending.push(target);
      else if (entry.isFile()) output.push(target);
    }
  }
  return output.sort((a, b) => a.localeCompare(b));
}

function sha256(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}

function jsonLine(value) {
  return `${JSON.stringify(value)}\n`;
}

const files = [];
const symbols = [];
const events = [];
const protocols = [];
const definitions = [];
const requirements = [];
const documents = [];
const textExtensions = new Set([".lua", ".txt", ".xml", ".json", ".csv", ".ini", ".properties", ".md", ".html", ".css", ".info", ".animstates", ".tbx", ".iml"]);

function addTextFile(scope, kind, base, file) {
  const data = fs.readFileSync(file);
  const content = data.toString("utf8");
  const relative = path.relative(base, file).replaceAll("\\", "/");
  const record = {
    scope, kind, path: relative, bytes: data.length, sha256: sha256(data),
    lines: content.length ? content.split(/\r?\n/).length : 0,
  };
  files.push(record);
  documents.push({ scope, kind, path: relative, symbol: "", content });
  return { content, relative };
}

function indexLua(scope, base, file) {
  const { content, relative } = addTextFile(scope, "lua", base, file);
  const lines = content.split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    let match = line.match(/^\s*(local\s+)?function\s+([A-Za-z_][A-Za-z0-9_.:]*)\s*\(([^)]*)\)/);
    if (!match) match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_.:]*)\s*=\s*function\s*\(([^)]*)\)/);
    if (match) {
      const name = match[2] ?? match[1];
      const params = match[3] ?? match[2] ?? "";
      symbols.push({ scope, language: "lua", kind: "function", name, path: relative, line: i + 1, signature: `${name}(${params.trim()})` });
    }
    for (const event of line.matchAll(/Events\.([A-Za-z_][A-Za-z0-9_]*)\.Add\s*\(([^)]+)\)/g)) {
      events.push({ scope, event: event[1], callback: event[2].trim(), path: relative, line: i + 1 });
    }
    for (const req of line.matchAll(/require\s*[\s(]*["']([^"']+)["']/g)) {
      requirements.push({ scope, module: req[1], path: relative, line: i + 1 });
    }
    if (/sendClientCommand\s*\(/.test(line)) protocols.push({ scope, direction: "C2S", command: "dynamic", path: relative, line: i + 1, expression: line.trim() });
    if (/sendServerCommand\s*\(/.test(line)) protocols.push({ scope, direction: "S2C", command: "dynamic", path: relative, line: i + 1, expression: line.trim() });
    if (/protocol\.lua$/i.test(relative)) {
      for (const command of line.matchAll(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*["']([^"']+)["']/g)) {
        protocols.push({ scope, direction: "DECL", command: command[2], key: command[1], path: relative, line: i + 1 });
      }
    }
  }
}

function indexScript(scope, base, file) {
  const { content, relative } = addTextFile(scope, "script", base, file);
  const lines = content.split(/\r?\n/);
  let moduleName = "";
  for (let i = 0; i < lines.length; i += 1) {
    const match = lines[i].match(/^\s*(module|item|recipe|model|vehicle|template|fixing|evolvedrecipe|sound|animation|entity)\s+(.+?)\s*(?:\{|$)/i);
    if (!match) continue;
    const kind = match[1].toLowerCase();
    const name = match[2].trim();
    if (kind === "module") moduleName = name;
    definitions.push({ scope, kind, name, module: moduleName, path: relative, line: i + 1 });
  }
}

function parseJavap(snapshotRoot) {
  const apiPath = path.join(snapshotRoot, "bytecode", "java-api.txt");
  if (!fs.existsSync(apiPath)) return;
  const content = fs.readFileSync(apiPath, "utf8");
  documents.push({ scope: "game", kind: "java-bytecode-api", path: "bytecode/java-api.txt", symbol: "", content });
  const lines = content.split(/\r?\n/);
  let className = "";
  let pending = null;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const classMatch = line.match(/^(?:public|protected|private|abstract|final|static|sealed|non-sealed|strictfp|\s)*\s*(?:class|interface|enum|record)\s+([A-Za-z0-9_.$]+)/);
    if (classMatch) {
      className = classMatch[1];
      symbols.push({ scope: "game", language: "java-bytecode", kind: "class", name: className, path: className.replaceAll(".", "/") + ".class", line: i + 1, signature: line.trim() });
      pending = null;
      continue;
    }
    if (/^\s{2,}\S.*[();];?$/.test(line) && !/^\s*descriptor:/.test(line)) {
      pending = line.trim();
      continue;
    }
    const descriptor = line.match(/^\s*descriptor:\s*(\S+)/);
    if (descriptor && pending && className) {
      const method = pending.match(/([A-Za-z_$][A-Za-z0-9_$<>]*)\s*\(/);
      const field = pending.match(/([A-Za-z_$][A-Za-z0-9_$]*)\s*;$/);
      symbols.push({
        scope: "game", language: "java-bytecode", kind: method ? "method" : "field",
        name: method ? method[1] : (field ? field[1] : pending), className,
        path: className.replaceAll(".", "/") + ".class", line: i, signature: pending,
        descriptor: descriptor[1],
      });
      pending = null;
    }
  }
}

const mediaRoot = path.join(root, "raw", "media");
const luaRoot = path.join(root, "raw", "media", "lua");
const scriptRoot = path.join(root, "raw", "media", "scripts");
const javaRoot = path.join(root, "java-decompiled");
for (const file of walk(luaRoot)) {
  const extension = path.extname(file).toLowerCase();
  if (extension === ".lua") indexLua("game", luaRoot, file);
  else if (textExtensions.has(extension)) addTextFile("game", extension === ".json" ? "translation" : "lua-metadata", luaRoot, file);
  else {
    const data = fs.readFileSync(file);
    files.push({ scope: "game", kind: "lua-asset", path: path.relative(luaRoot, file).replaceAll("\\", "/"), bytes: data.length, sha256: sha256(data), lines: 0 });
  }
}
for (const file of walk(scriptRoot)) indexScript("game", scriptRoot, file);
for (const file of walk(mediaRoot)) {
  if (file.startsWith(`${luaRoot}${path.sep}`) || file.startsWith(`${scriptRoot}${path.sep}`)) continue;
  const extension = path.extname(file).toLowerCase();
  if (textExtensions.has(extension)) addTextFile("game", "media-metadata", mediaRoot, file);
}
for (const file of walk(javaRoot).filter((f) => f.toLowerCase().endsWith(".java"))) addTextFile("game", "java-decompiled", javaRoot, file);
parseJavap(root);

const outputs = [
  ["files.jsonl", files], ["lua-symbols.jsonl", symbols.filter((row) => row.language === "lua")],
  ["java-symbols.jsonl", symbols.filter((row) => row.language?.startsWith("java"))],
  ["events.jsonl", events], ["protocol.jsonl", protocols],
  ["script-definitions.jsonl", definitions], ["requirements.jsonl", requirements],
];
for (const [name, rows] of outputs) fs.writeFileSync(path.join(indexRoot, name), rows.map(jsonLine).join(""));

const databasePath = path.join(indexRoot, "search.sqlite");
if (fs.existsSync(databasePath)) fs.rmSync(databasePath);
const db = new DatabaseSync(databasePath);
db.exec("PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA temp_store=MEMORY;");
db.exec("CREATE TABLE files(scope TEXT, kind TEXT, path TEXT, bytes INTEGER, sha256 TEXT, lines INTEGER);");
db.exec("CREATE TABLE symbols(scope TEXT, language TEXT, kind TEXT, name TEXT, class_name TEXT, path TEXT, line INTEGER, signature TEXT, descriptor TEXT);");
db.exec("CREATE TABLE events(scope TEXT, event TEXT, callback TEXT, path TEXT, line INTEGER);");
db.exec("CREATE TABLE protocol(scope TEXT, direction TEXT, command TEXT, key_name TEXT, path TEXT, line INTEGER, expression TEXT);");
db.exec("CREATE TABLE definitions(scope TEXT, kind TEXT, name TEXT, module TEXT, path TEXT, line INTEGER);");
db.exec("CREATE VIRTUAL TABLE documents USING fts5(scope UNINDEXED, kind UNINDEXED, path, symbol, content, tokenize='unicode61');");
const insertFile = db.prepare("INSERT INTO files VALUES (?, ?, ?, ?, ?, ?)");
const insertSymbol = db.prepare("INSERT INTO symbols VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
const insertEvent = db.prepare("INSERT INTO events VALUES (?, ?, ?, ?, ?)");
const insertProtocol = db.prepare("INSERT INTO protocol VALUES (?, ?, ?, ?, ?, ?, ?)");
const insertDefinition = db.prepare("INSERT INTO definitions VALUES (?, ?, ?, ?, ?, ?)");
const insertDocument = db.prepare("INSERT INTO documents VALUES (?, ?, ?, ?, ?)");
db.exec("BEGIN");
for (const row of files) insertFile.run(row.scope, row.kind, row.path, row.bytes, row.sha256, row.lines);
for (const row of symbols) insertSymbol.run(row.scope, row.language, row.kind, row.name, row.className ?? "", row.path, row.line, row.signature ?? "", row.descriptor ?? "");
for (const row of events) insertEvent.run(row.scope, row.event, row.callback, row.path, row.line);
for (const row of protocols) insertProtocol.run(row.scope, row.direction, row.command, row.key ?? "", row.path, row.line, row.expression ?? "");
for (const row of definitions) insertDefinition.run(row.scope, row.kind, row.name, row.module, row.path, row.line);
for (const row of documents) insertDocument.run(row.scope, row.kind, row.path, row.symbol, row.content);
db.exec("COMMIT");
db.close();

const summary = {
  mode, generatedAt: new Date().toISOString(), files: files.length,
  bytes: files.reduce((sum, row) => sum + row.bytes, 0),
  luaFiles: files.filter((row) => row.kind === "lua").length,
  scriptFiles: files.filter((row) => row.kind === "script").length,
  javaSourceFiles: files.filter((row) => row.kind === "java-decompiled").length,
  translationFiles: files.filter((row) => row.kind === "translation").length,
  mediaMetadataFiles: files.filter((row) => row.kind === "media-metadata").length,
  luaSymbols: symbols.filter((row) => row.language === "lua").length,
  javaSymbols: symbols.filter((row) => row.language?.startsWith("java")).length,
  events: events.length, protocolReferences: protocols.length,
  scriptDefinitions: definitions.length, requirements: requirements.length,
};
fs.writeFileSync(path.join(indexRoot, "summary.json"), JSON.stringify(summary, null, 2));
process.stdout.write(`${JSON.stringify(summary)}\n`);
