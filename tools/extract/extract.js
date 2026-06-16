/* Anatoly veri çıkarıcı — Liftosaur repodan (AGPL v3) egzersiz + program JSON üretir.
 * Tek seferlik, app'e dahil değil. Çalıştır: node tools/extract/extract.js
 */
const fs = require("fs");
const path = require("path");

const REPO = "F:/tmp/liftosaur/repo";
const OUT = path.join(__dirname, "..", "..", "assets");

// --- TS dosyasından balanced bir obje literalini çıkar ve eval et ---
function extractObjectLiteral(src, afterMarker) {
  const idx = src.indexOf(afterMarker);
  if (idx < 0) throw new Error("marker bulunamadı: " + afterMarker);
  // marker'dan sonra ilk '{' bul
  let i = src.indexOf("{", idx + afterMarker.length);
  const start = i;
  let depth = 0;
  let inStr = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (inStr) {
      if (c === "\\") { i++; continue; }
      if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"' || c === "'" || c === "`") { inStr = c; continue; }
    if (c === "/" && src[i + 1] === "/") { // satır yorumu
      while (i < src.length && src[i] !== "\n") i++;
      continue;
    }
    if (c === "{") depth++;
    else if (c === "}") { depth--; if (depth === 0) { i++; break; } }
  }
  const objText = src.slice(start, i);
  // eslint-disable-next-line no-eval
  return eval("(" + objText + ")");
}

// --- frontmatter ayrıştır (basit YAML) ---
function parseFrontmatter(md) {
  const m = md.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!m) return { fm: {}, body: md };
  const fm = {};
  for (const line of m[1].split(/\r?\n/)) {
    const mm = line.match(/^([a-zA-Z0-9_]+):\s*(.*)$/);
    if (!mm) continue;
    let v = mm[2].trim();
    if (v.startsWith('"') && v.endsWith('"')) v = v.slice(1, -1);
    else if (v === "true") v = true;
    else if (v === "false") v = false;
    else if (v === "[]") v = [];
    else if (/^-?\d+(\.\d+)?$/.test(v)) v = Number(v);
    fm[mm[1]] = v;
  }
  return { fm, body: m[2] };
}

function main() {
  const exSrc = fs.readFileSync(path.join(REPO, "src/models/exercise.ts"), "utf8");
  const allList = extractObjectLiteral(exSrc, "allExercisesList: Record<IExerciseId, IExercise> =");
  const meta = extractObjectLiteral(exSrc, "metadata: Record<IExerciseId, IMetaExercises> =");

  // egzersiz açıklama md dosyalarını id'ye göre indeksle (dosya: <idLower>_<equip>.md)
  const exDir = path.join(REPO, "exercises");
  const mdFiles = fs.readdirSync(exDir).filter((f) => f.endsWith(".md"));
  const descByPrefix = {}; // idLower -> {equip: {video, description, instructions}}
  for (const f of mdFiles) {
    const base = f.replace(/\.md$/, "");
    const us = base.lastIndexOf("_");
    const idLower = base.slice(0, us);
    const equip = base.slice(us + 1);
    const { fm, body } = parseFrontmatter(fs.readFileSync(path.join(exDir, f), "utf8"));
    const howtoIdx = body.indexOf("<!-- howto -->");
    const instructions = (howtoIdx >= 0 ? body.slice(0, howtoIdx) : body).trim();
    (descByPrefix[idLower] ||= {})[equip] = {
      video: fm.video || null,
      description: fm.description || "",
      instructions,
    };
  }

  const exercises = [];
  for (const id of Object.keys(allList)) {
    const e = allList[id];
    const m = meta[id] || {};
    const idLower = id.toLowerCase();
    const descByEquip = descByPrefix[idLower] || {};
    // default ekipmana göre açıklama seç, yoksa ilk bulunan
    const defEquip = (e.defaultEquipment || "bodyweight").toLowerCase();
    const desc = descByEquip[defEquip] || Object.values(descByEquip)[0] || {};
    exercises.push({
      id,
      name: e.name,
      defaultEquipment: e.defaultEquipment || null,
      defaultWarmup: e.defaultWarmup || 0,
      types: e.types || [],
      startingWeightLb: e.startingWeightLb ? e.startingWeightLb.value : 0,
      startingWeightKg: e.startingWeightKg ? e.startingWeightKg.value : 0,
      targetMuscles: m.targetMuscles || [],
      synergistMuscles: m.synergistMuscles || [],
      bodyParts: m.bodyParts || [],
      equipment: m.sortedEquipment || (e.defaultEquipment ? [e.defaultEquipment] : []),
      video: desc.video || null,
      description: desc.description || "",
      instructions: desc.instructions || "",
    });
  }

  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, "exercises.json"), JSON.stringify(exercises, null, 0));
  console.log("exercises.json yazıldı:", exercises.length, "egzersiz");

  // --- programlar ---
  const progDir = path.join(REPO, "programs/builtin");
  const progFiles = fs.readdirSync(progDir).filter((f) => f.endsWith(".md"));
  const programs = [];
  for (const f of progFiles) {
    const raw = fs.readFileSync(path.join(progDir, f), "utf8");
    const { fm, body } = parseFrontmatter(raw);
    // liftoscript bloğunu çek
    const cb = body.match(/```liftoscript\r?\n([\s\S]*?)```/);
    const script = cb ? cb[1].trim() : "";
    // açıklama = ilk kod bloğundan önceki metin
    const descText = body.split("```")[0].trim();
    programs.push({
      id: fm.id || f.replace(/\.md$/, ""),
      name: fm.name || fm.id || f,
      author: fm.author || "",
      url: fm.url || "",
      shortDescription: fm.shortDescription || "",
      isMultiweek: fm.isMultiweek || false,
      frequency: fm.frequency || null,
      age: fm.age || null,
      duration: fm.duration || null,
      goal: fm.goal || null,
      tags: Array.isArray(fm.tags) ? fm.tags : [],
      description: descText,
      script,
    });
  }
  fs.mkdirSync(path.join(OUT, "programs"), { recursive: true });
  fs.writeFileSync(path.join(OUT, "programs.json"), JSON.stringify(programs, null, 0));
  console.log("programs.json yazıldı:", programs.length, "program");

  // boş script kaç tane?
  const empty = programs.filter((p) => !p.script).length;
  if (empty) console.warn("UYARI: scriptsiz program sayısı:", empty);
}

main();
