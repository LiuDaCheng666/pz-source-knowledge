import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

const root = path.resolve(process.argv[2]);
const query = process.argv[3];
const scope = process.argv[4] || "all";
const limit = Math.max(1, Math.min(100, Number(process.argv[5]) || 20));
if (!query) throw new Error("query is required");
const current = JSON.parse(fs.readFileSync(path.join(root, "current.json"), "utf8"));
if (!["all", "game"].includes(scope)) throw new Error(`unsupported scope: ${scope}`);
const targets = [["game", path.resolve(root, current.gameSnapshot)]];
const rows = [];
for (const [name, target] of targets) {
  const db = new DatabaseSync(path.join(target, "indexes", "search.sqlite"), { readOnly: true });
  const statement = db.prepare("SELECT path, kind, snippet(documents, 4, '[', ']', ' ... ', 24) AS excerpt, bm25(documents) AS rank FROM documents WHERE documents MATCH ? ORDER BY rank LIMIT ?");
  for (const row of statement.all(query, limit)) rows.push({ scope: name, ...row });
  db.close();
}
rows.sort((a, b) => a.rank - b.rank);
process.stdout.write(JSON.stringify(rows.slice(0, limit), null, 2));
