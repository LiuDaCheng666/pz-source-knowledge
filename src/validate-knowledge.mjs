import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

const root = path.resolve(process.argv[2] || path.join(import.meta.dirname, ".."));
const currentPath = process.argv[3] ? path.resolve(process.argv[3]) : path.join(root, "current.json");
if (!fs.existsSync(currentPath)) throw new Error("current.json is missing");
const current = JSON.parse(fs.readFileSync(currentPath, "utf8"));
const game = path.resolve(root, current.gameSnapshot);

function parseJsonLines(file) {
  let count = 0;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    if (!line) continue;
    JSON.parse(line);
    count += 1;
  }
  return count;
}

function validateIndex(base, expectedMode) {
  const index = path.join(base, "indexes");
  const summary = JSON.parse(fs.readFileSync(path.join(index, "summary.json"), "utf8"));
  if (summary.mode !== expectedMode) throw new Error(`${expectedMode} summary mode mismatch`);
  for (const name of ["files.jsonl", "lua-symbols.jsonl", "events.jsonl", "protocol.jsonl", "requirements.jsonl"]) {
    parseJsonLines(path.join(index, name));
  }
  const db = new DatabaseSync(path.join(index, "search.sqlite"), { readOnly: true });
  const files = Number(db.prepare("SELECT count(*) AS count FROM files").get().count);
  const docs = Number(db.prepare("SELECT count(*) AS count FROM documents").get().count);
  const search = Number(db.prepare("SELECT count(*) AS count FROM documents WHERE documents MATCH 'vehicle'").get().count);
  db.close();
  if (files !== summary.files || docs < 1 || search < 1) throw new Error(`${expectedMode} SQLite index validation failed`);
  return summary;
}

const provenance = JSON.parse(fs.readFileSync(path.join(game, "provenance.json"), "utf8"));
if (!/^\d+$/.test(String(provenance.buildId))) throw new Error("invalid game Build ID");
if (!/^[A-Fa-f0-9]{64}$/.test(provenance.jarSha256)) throw new Error("invalid JAR hash");
if (!fs.existsSync(path.join(game, "raw", "java", "projectzomboid.jar"))) throw new Error("snapshot JAR missing");
if (!fs.existsSync(path.join(game, "bytecode", "java-api.txt"))) throw new Error("javap API missing");
const gameSummary = validateIndex(game, "game");
const classRows = fs.readFileSync(path.join(game, "bytecode", "java-classes.jsonl"), "utf8")
  .split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
const topLevelClasses = classRows.filter((row) => !row.name.includes("$")).length;
if (gameSummary.luaFiles < 1300 || gameSummary.scriptFiles < 900 || gameSummary.javaSourceFiles < 1000 || gameSummary.javaSymbols < 10000) {
  throw new Error(`game coverage too low: ${JSON.stringify(gameSummary)}`);
}
if (gameSummary.translationFiles < 1200 || gameSummary.mediaMetadataFiles < 5000) {
  throw new Error(`game text-metadata coverage too low: ${JSON.stringify(gameSummary)}`);
}
if (gameSummary.javaSourceFiles < topLevelClasses) {
  throw new Error(`CFR coverage below top-level class count: sources=${gameSummary.javaSourceFiles} classes=${topLevelClasses}`);
}
process.stdout.write(JSON.stringify({ ok: true, current, classCoverage: { all: classRows.length, topLevel: topLevelClasses }, gameSummary }, null, 2));
