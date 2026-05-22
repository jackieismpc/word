import { createReadStream, existsSync, readFileSync, rmSync } from "node:fs";
import { mkdir, readFile, rename, stat, writeFile } from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = Number(process.env.PORT || 12345);
const BIND_HOST = process.env.BIND_HOST || process.env.WORD_MATCH_HOST || process.env.HOST || "0.0.0.0";
const PUBLIC_DIR = path.join(__dirname, "public");
const STORAGE_DIR = path.join(__dirname, "storage");
const FALLBACK_PACKS_FILE = path.join(__dirname, "data", "fallback-packs.json");

const HELP_URL = "https://ts-danci.feishu.cn/wiki/NqlPwDn8bioFnjk5Huqc25fLnVg";
const REMOTE_LATEST_URL = "https://oss-cdn.tsdanci.com/a-json-data/dict/latest.json";
const REMOTE_PACKS_FALLBACK_URL = "https://oss-cdn.tsdanci.com/a-json-data/dict/word_match_v2.json";

const FILES = {
  settings: path.join(STORAGE_DIR, "settings.json"),
  dictionary: path.join(STORAGE_DIR, "dictionary.json"),
  packs: path.join(STORAGE_DIR, "packs.json"),
  gameHistory: path.join(STORAGE_DIR, "game-history.json"),
};

const DEFAULT_SETTINGS = {
  soundEnabled: true,
  pronunciationEnabled: true,
  displayOrder: "mixed",
  difficulty: "easy",
};

function nowIso() {
  return new Date().toISOString();
}

function sendJson(res, statusCode, body, headers = {}) {
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    ...headers,
  });
  res.end(JSON.stringify(body, null, 2));
}

function sendText(res, statusCode, body, headers = {}) {
  res.writeHead(statusCode, {
    "Content-Type": "text/plain; charset=utf-8",
    ...headers,
  });
  res.end(body);
}

async function readJsonFile(filePath, fallback) {
  try {
    const raw = await readFile(filePath, "utf8");
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

async function writeJsonFile(filePath, value) {
  const tmp = `${filePath}.tmp`;
  await writeFile(tmp, JSON.stringify(value, null, 2), "utf8");
  await rename(tmp, filePath);
}

function createId(prefix) {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function normalizeEnglish(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9' -]/g, "")
    .replace(/\s+/g, " ");
}

function readFirstString(record, keys) {
  for (const key of keys) {
    const value = record?.[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return "";
}

function normalizeDictionaryEntry(record) {
  if (!record || typeof record !== "object" || Array.isArray(record)) {
    return null;
  }

  const word = normalizeEnglish(readFirstString(record, ["word", "en", "english", "text"]));
  const chinese = readFirstString(record, ["chinese", "zh", "translation", "meaning", "cn"]);
  if (!word || !chinese) {
    return null;
  }

  return {
    word,
    chinese,
    chinesePos: readFirstString(record, ["chinesePos", "pos", "partOfSpeech"]),
    us: readFirstString(record, ["us", "phoneticUs", "phonetic"]),
    uk: readFirstString(record, ["uk", "phoneticUk"]),
  };
}

function dedupeDictionary(entries) {
  const map = new Map();
  for (const item of entries) {
    if (!item?.word || map.has(item.word)) {
      continue;
    }
    map.set(item.word, item);
  }
  return [...map.values()].sort((a, b) => a.word.localeCompare(b.word));
}

function normalizeDictionaryPayload(payload) {
  const candidates = [];
  if (Array.isArray(payload)) {
    candidates.push(...payload);
  } else if (payload && typeof payload === "object") {
    for (const key of ["items", "data", "words", "dictionary", "entries"]) {
      if (Array.isArray(payload[key])) {
        candidates.push(...payload[key]);
      }
    }
  }
  return dedupeDictionary(candidates.map(normalizeDictionaryEntry).filter(Boolean));
}

function normalizePackWord(record) {
  if (!record || typeof record !== "object" || Array.isArray(record)) {
    return null;
  }
  const en = normalizeEnglish(readFirstString(record, ["en", "word", "english", "text"]));
  const zh = readFirstString(record, ["zh", "chinese", "translation", "meaning", "cn"]);
  if (!en || !zh) {
    return null;
  }
  return { en, zh };
}

function dedupePackWords(words) {
  const map = new Map();
  for (const word of words) {
    if (!word?.en || map.has(word.en)) {
      continue;
    }
    map.set(word.en, word);
  }
  return [...map.values()];
}

function normalizePack(record, index = 0) {
  if (!record || typeof record !== "object" || Array.isArray(record)) {
    return null;
  }

  const wordsSource = Array.isArray(record.words)
    ? record.words
    : Array.isArray(record.items)
      ? record.items
      : Array.isArray(record.data)
        ? record.data
        : [];
  const words = dedupePackWords(wordsSource.map(normalizePackWord).filter(Boolean));
  if (!words.length) {
    return null;
  }

  return {
    id: typeof record.id === "string" && record.id.trim() ? record.id.trim() : createId("pack"),
    name: readFirstString(record, ["name", "title"]) || `词包 ${index + 1}`,
    source: readFirstString(record, ["source"]) || "导入词库",
    createdAt: Number(record.createdAt) || Date.now(),
    createdAtLabel:
      readFirstString(record, ["createdAtLabel"]) ||
      new Date(Number(record.createdAt) || Date.now()).toLocaleString("zh-CN"),
    words,
  };
}

function normalizePackCollection(payload) {
  const packs = [];
  const list = [];

  if (Array.isArray(payload)) {
    list.push(...payload);
  } else if (payload && typeof payload === "object") {
    for (const key of ["historyItems", "importHistory", "packs", "records", "data", "examples"]) {
      if (Array.isArray(payload[key])) {
        list.push(...payload[key]);
      }
    }
    if (Array.isArray(payload.words)) {
      list.push({ name: "导入词库", source: "导入词库", words: payload.words });
    }
  }

  list.forEach((item, index) => {
    const pack = normalizePack(item, index);
    if (pack) {
      packs.push(pack);
    }
  });

  return packs;
}

function mergePacks(preferred, existing) {
  const map = new Map();

  for (const item of preferred) {
    if (item?.id) {
      map.set(item.id, item);
    }
  }

  for (const item of existing) {
    if (item?.id && !map.has(item.id)) {
      map.set(item.id, item);
    }
  }

  return [...map.values()];
}

async function fetchJson(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        "User-Agent": "word-match-local/1.0",
        Accept: "application/json,text/plain,*/*",
      },
    });
    if (!response.ok) {
      throw new Error(`request_failed:${response.status}`);
    }
    return response.json();
  } finally {
    clearTimeout(timer);
  }
}

async function ensureStorage() {
  await mkdir(STORAGE_DIR, { recursive: true });

  if (!existsSync(FILES.settings)) {
    await writeJsonFile(FILES.settings, DEFAULT_SETTINGS);
  }
  if (!existsSync(FILES.dictionary)) {
    await writeJsonFile(FILES.dictionary, {
      version: 0,
      updatedAt: null,
      lastCheckedAt: null,
      sourceUrl: null,
      items: [],
    });
  }
  if (!existsSync(FILES.packs)) {
    const fallback = await readJsonFile(FALLBACK_PACKS_FILE, { historyItems: [] });
    const items = normalizePackCollection(fallback);
    await writeJsonFile(FILES.packs, {
      activePackId: items[0]?.id || null,
      items,
    });
  }
  if (!existsSync(FILES.gameHistory)) {
    await writeJsonFile(FILES.gameHistory, []);
  }
}

async function getSettings() {
  return {
    ...DEFAULT_SETTINGS,
    ...(await readJsonFile(FILES.settings, DEFAULT_SETTINGS)),
  };
}

async function getDictionary() {
  const dictionary = await readJsonFile(FILES.dictionary, null);
  return dictionary || {
    version: 0,
    updatedAt: null,
    lastCheckedAt: null,
    sourceUrl: null,
    items: [],
  };
}

async function getPacks() {
  const packs = await readJsonFile(FILES.packs, null);
  if (!packs) {
    return { activePackId: null, items: [] };
  }
  return {
    activePackId: packs.activePackId || packs.items?.[0]?.id || null,
    items: Array.isArray(packs.items) ? packs.items : [],
  };
}

async function getGameHistory() {
  const history = await readJsonFile(FILES.gameHistory, []);
  return Array.isArray(history) ? history : [];
}

async function saveSettings(settings) {
  await writeJsonFile(FILES.settings, settings);
  return settings;
}

async function saveDictionary(dictionary) {
  await writeJsonFile(FILES.dictionary, dictionary);
  return dictionary;
}

async function savePacks(packs) {
  await writeJsonFile(FILES.packs, packs);
  return packs;
}

async function saveGameHistory(history) {
  await writeJsonFile(FILES.gameHistory, history);
  return history;
}

async function buildBootstrap() {
  const [settings, dictionary, packs, gameHistory] = await Promise.all([
    getSettings(),
    getDictionary(),
    getPacks(),
    getGameHistory(),
  ]);

  return {
    helpUrl: HELP_URL,
    settings,
    dictionary: {
      version: dictionary.version || 0,
      updatedAt: dictionary.updatedAt,
      lastCheckedAt: dictionary.lastCheckedAt,
      sourceUrl: dictionary.sourceUrl,
      totalCount: Array.isArray(dictionary.items) ? dictionary.items.length : 0,
      items: dictionary.items || [],
    },
    packs,
    gameHistory,
    setup: {
      dictionaryReady: Array.isArray(dictionary.items) && dictionary.items.length > 0,
      packsReady: Array.isArray(packs.items) && packs.items.length > 0,
    },
  };
}

async function checkDictionaryUpdate() {
  const latest = await fetchJson(REMOTE_LATEST_URL);
  const dictionary = await getDictionary();
  const checked = nowIso();

  await saveDictionary({
    ...dictionary,
    lastCheckedAt: checked,
  });

  return {
    currentVersion: Number(dictionary.version || 0),
    latestVersion: Number(latest.version || 0),
    hasUpdate: Number(latest.version || 0) > Number(dictionary.version || 0),
    downloadUrl: latest.downloadUrl || null,
    wordMatchUrl: latest.wordMatchUrl || null,
    checkedAt: checked,
  };
}

async function updateDictionaryFromRemote() {
  const latest = await fetchJson(REMOTE_LATEST_URL);
  const payload = await fetchJson(latest.downloadUrl);
  const items = normalizeDictionaryPayload(payload);
  if (!items.length) {
    throw new Error("dictionary_empty");
  }

  const dictionary = {
    version: Number(latest.version || 0),
    updatedAt: nowIso(),
    lastCheckedAt: nowIso(),
    sourceUrl: latest.downloadUrl || null,
    items,
  };
  await saveDictionary(dictionary);
  return dictionary;
}

async function loadRemotePacks() {
  let remoteUrl = REMOTE_PACKS_FALLBACK_URL;
  try {
    const latest = await fetchJson(REMOTE_LATEST_URL);
    if (typeof latest.wordMatchUrl === "string" && latest.wordMatchUrl.trim()) {
      remoteUrl = latest.wordMatchUrl.trim();
    }
  } catch {
    // Ignore and use the fallback URL below.
  }

  try {
    const payload = await fetchJson(remoteUrl);
    const remotePacks = normalizePackCollection(payload);
    if (remotePacks.length) {
      return remotePacks;
    }
  } catch {
    // Ignore and use bundled fallback packs below.
  }

  const fallback = await readJsonFile(FALLBACK_PACKS_FILE, { historyItems: [] });
  return normalizePackCollection(fallback);
}

async function runOneClickPrepare(options = {}) {
  const force = Boolean(options.force);
  const [dictionary, packs] = await Promise.all([getDictionary(), getPacks()]);
  let dictionaryChanged = false;
  let packsChanged = false;

  if (force || !dictionary.items?.length) {
    await updateDictionaryFromRemote();
    dictionaryChanged = true;
  }

  if (force || !packs.items?.length) {
    const remoteItems = await loadRemotePacks();
    const items = force ? mergePacks(remoteItems, packs.items || []) : remoteItems;
    const nextActivePackId = items.some((item) => item.id === packs.activePackId)
      ? packs.activePackId
      : items[0]?.id || null;
    await savePacks({
      activePackId: nextActivePackId,
      items,
    });
    packsChanged = true;
  }

  return {
    dictionaryChanged,
    packsChanged,
    bootstrap: await buildBootstrap(),
  };
}

const MAX_BODY_SIZE = 10 * 1024 * 1024; // 10MB

async function readRequestBody(req) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > MAX_BODY_SIZE) {
      throw Object.assign(new Error("payload_too_large"), { statusCode: 413 });
    }
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  if (!raw) {
    return {};
  }
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error("invalid_json");
  }
}

function getMimeType(filePath) {
  if (filePath.endsWith(".html")) return "text/html; charset=utf-8";
  if (filePath.endsWith(".css")) return "text/css; charset=utf-8";
  if (filePath.endsWith(".js")) return "application/javascript; charset=utf-8";
  if (filePath.endsWith(".mjs")) return "application/javascript; charset=utf-8";
  if (filePath.endsWith(".json")) return "application/json; charset=utf-8";
  if (filePath.endsWith(".svg")) return "image/svg+xml";
  if (filePath.endsWith(".png")) return "image/png";
  return "application/octet-stream";
}

async function serveStatic(req, res, pathname) {
  const cleanPath = pathname === "/" ? "/index.html" : pathname;
  const target = path.join(PUBLIC_DIR, cleanPath);
  if (!target.startsWith(PUBLIC_DIR)) {
    sendText(res, 403, "Forbidden");
    return;
  }

  try {
    const info = await stat(target);
    if (!info.isFile()) {
      sendText(res, 404, "Not found");
      return;
    }
    const isHtml = target.endsWith(".html");
    res.writeHead(200, {
      "Content-Type": getMimeType(target),
      "Cache-Control": isHtml ? "no-store" : "max-age=3600",
    });
    createReadStream(target).pipe(res);
  } catch {
    sendText(res, 404, "Not found");
  }
}

async function handleApi(req, res, pathname) {
  if (req.method === "GET" && pathname === "/api/bootstrap") {
    sendJson(res, 200, await buildBootstrap());
    return;
  }

  if (req.method === "POST" && pathname === "/api/settings") {
    const body = await readRequestBody(req);
    const settings = await getSettings();
    const next = {
      ...settings,
      ...body,
    };
    await saveSettings(next);
    sendJson(res, 200, next);
    return;
  }

  if (req.method === "POST" && pathname === "/api/setup/prepare") {
    const body = await readRequestBody(req);
    sendJson(res, 200, await runOneClickPrepare(body));
    return;
  }

  if (req.method === "POST" && pathname === "/api/dictionary/check-update") {
    sendJson(res, 200, await checkDictionaryUpdate());
    return;
  }

  if (req.method === "POST" && pathname === "/api/dictionary/update") {
    const dictionary = await updateDictionaryFromRemote();
    sendJson(res, 200, {
      ok: true,
      totalCount: dictionary.items.length,
      version: dictionary.version,
    });
    return;
  }

  if (req.method === "POST" && pathname === "/api/dictionary/import") {
    const body = await readRequestBody(req);
    const items = normalizeDictionaryPayload(body.json);
    if (!items.length) {
      sendJson(res, 400, { error: "empty_dictionary" });
      return;
    }
    const dictionary = await getDictionary();
    await saveDictionary({
      version: Number(body.version || dictionary.version || 0),
      updatedAt: nowIso(),
      lastCheckedAt: dictionary.lastCheckedAt,
      sourceUrl: "local-import",
      items,
    });
    sendJson(res, 200, { ok: true, totalCount: items.length });
    return;
  }

  if (req.method === "POST" && pathname === "/api/dictionary/clear") {
    await saveDictionary({
      version: 0,
      updatedAt: null,
      lastCheckedAt: null,
      sourceUrl: null,
      items: [],
    });
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "GET" && pathname === "/api/dictionary/export") {
    const dictionary = await getDictionary();
    sendJson(
      res,
      200,
      {
        version: dictionary.version || 0,
        items: dictionary.items || [],
      },
      {
        "Content-Disposition": `attachment; filename="word-match-dictionary-${Date.now()}.json"`,
      },
    );
    return;
  }

  if (req.method === "POST" && pathname === "/api/packs/import") {
    const body = await readRequestBody(req);
    const imported = normalizePackCollection(body.json);
    if (!imported.length) {
      sendJson(res, 400, { error: "empty_packs" });
      return;
    }
    const packs = await getPacks();
    const items = mergePacks(imported, packs.items);
    await savePacks({
      activePackId: imported[0]?.id || packs.activePackId,
      items,
    });
    sendJson(res, 200, { ok: true, count: imported.length });
    return;
  }

  if (req.method === "GET" && pathname === "/api/packs/export") {
    const packs = await getPacks();
    sendJson(
      res,
      200,
      {
        historyItems: packs.items,
      },
      {
        "Content-Disposition": `attachment; filename="word-match-packs-${Date.now()}.json"`,
      },
    );
    return;
  }

  if (req.method === "POST" && pathname === "/api/packs/clear") {
    await savePacks({ activePackId: null, items: [] });
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "POST" && pathname === "/api/packs/create") {
    const body = await readRequestBody(req);
    const pack = normalizePack(body.pack);
    if (!pack) {
      sendJson(res, 400, { error: "invalid_pack" });
      return;
    }
    const packs = await getPacks();
    await savePacks({
      activePackId: pack.id,
      items: [pack, ...packs.items],
    });
    sendJson(res, 200, { ok: true, pack });
    return;
  }

  if (req.method === "PATCH" && pathname.startsWith("/api/packs/")) {
    const packId = pathname.split("/").pop();
    const body = await readRequestBody(req);
    const packs = await getPacks();
    const items = packs.items.map((item) =>
      item.id === packId
        ? {
            ...item,
            name: typeof body.name === "string" && body.name.trim() ? body.name.trim() : item.name,
          }
        : item,
    );
    await savePacks({
      ...packs,
      items,
    });
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "POST" && pathname.startsWith("/api/packs/") && pathname.endsWith("/activate")) {
    const parts = pathname.split("/");
    const packId = parts[parts.length - 2];
    const packs = await getPacks();
    await savePacks({
      ...packs,
      activePackId: packId,
    });
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "DELETE" && pathname.startsWith("/api/packs/")) {
    const packId = pathname.split("/").pop();
    const packs = await getPacks();
    const items = packs.items.filter((item) => item.id !== packId);
    const activePackId = packs.activePackId === packId ? items[0]?.id || null : packs.activePackId;
    await savePacks({
      activePackId,
      items,
    });
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "POST" && pathname === "/api/history/game") {
    const body = await readRequestBody(req);
    const history = await getGameHistory();
    const entry = {
      id: createId("game"),
      packId: body.packId || null,
      packName: body.packName || "未命名词包",
      mode: body.mode || "single",
      difficulty: body.difficulty || "easy",
      displayOrder: body.displayOrder || "mixed",
      matchedCount: Number(body.matchedCount || 0),
      totalCount: Number(body.totalCount || 0),
      durationSeconds: Number(body.durationSeconds || 0),
      status: body.status || "won",
      completedAt: nowIso(),
    };
    const next = [entry, ...history];
    const truncated = next.length > 100;
    await saveGameHistory(next.slice(0, 100));
    sendJson(res, 200, { ok: true, entry, truncated });
    return;
  }

  if (req.method === "POST" && pathname === "/api/history/game/clear") {
    await saveGameHistory([]);
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "DELETE" && pathname.startsWith("/api/history/game/")) {
    const gameId = pathname.split("/").pop();
    const history = await getGameHistory();
    await saveGameHistory(history.filter((item) => item.id !== gameId));
    sendJson(res, 200, { ok: true });
    return;
  }

  sendJson(res, 404, { error: "not_found" });
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || `127.0.0.1:${PORT}`}`);
    if (url.pathname.startsWith("/api/")) {
      await handleApi(req, res, url.pathname);
      return;
    }
    await serveStatic(req, res, url.pathname);
  } catch (error) {
    const statusCode = error.statusCode || 500;
    sendJson(res, statusCode, {
      error: statusCode === 413 ? "payload_too_large" : "server_error",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
});

const PID_FILE = process.env.WORD_MATCH_PID_FILE || "";
let isShuttingDown = false;

function cleanupPidFile() {
  if (!PID_FILE) {
    return;
  }

  try {
    const raw = readFileSync(PID_FILE, "utf8");
    if (String(raw).trim() === String(process.pid)) {
      rmSync(PID_FILE, { force: true });
    }
  } catch {
    // Ignore PID file cleanup failures.
  }
}

await ensureStorage();
cleanupPidFile();
if (PID_FILE) {
  await writeFile(PID_FILE, `${process.pid}\n`, "utf8");
}

function gracefulShutdown(signal) {
  if (isShuttingDown) {
    return;
  }

  isShuttingDown = true;
  console.log(`${signal} received, shutting down server...`);

  const forceExitTimer = setTimeout(() => {
    console.error("Graceful shutdown timed out, forcing exit.");
    process.exit(1);
  }, 5000);
  forceExitTimer.unref();

  server.close((error) => {
    clearTimeout(forceExitTimer);
    if (error) {
      console.error("Server shutdown failed:", error);
      process.exit(1);
      return;
    }

    cleanupPidFile();
    console.log("Server stopped cleanly.");
    process.exit(0);
  });
}

process.on("SIGINT", () => gracefulShutdown("SIGINT"));
process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGHUP", () => gracefulShutdown("SIGHUP"));

server.listen(PORT, BIND_HOST, () => {
  console.log(`Word Match local server running at http://127.0.0.1:${PORT}`);
  if (BIND_HOST !== "127.0.0.1" && BIND_HOST !== "localhost") {
    console.log(`Listening on ${BIND_HOST}:${PORT}`);
  }
});
