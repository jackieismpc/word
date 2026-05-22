import { pinyin as toPinyin } from "/vendor/pinyin-pro.mjs";

const COLORS = [
  ["#22c55e", "#4ade80"],
  ["#06b6d4", "#38bdf8"],
  ["#3b82f6", "#60a5fa"],
  ["#8b5cf6", "#a855f7"],
  ["#ec4899", "#f472b6"],
  ["#f59e0b", "#f97316"],
  ["#eab308", "#facc15"],
];

const SOUND_URLS = {
  success: "https://d.tsdanci.com/mp3/yes.mp3",
  error: "https://d.tsdanci.com/mp3/failure.mp3",
};

const UI_STATE_KEY = "word-match-local-ui-v2";
const DEFAULT_UI = {
  helpWidth: 560,
  setupBannerCollapsed: true,
  controlsExpanded: false,
};

function loadUiState() {
  try {
    const raw = window.localStorage.getItem(UI_STATE_KEY);
    if (!raw) {
      return { ...DEFAULT_UI };
    }
    return {
      ...DEFAULT_UI,
      ...JSON.parse(raw),
    };
  } catch {
    return { ...DEFAULT_UI };
  }
}

function saveUiState() {
  try {
    window.localStorage.setItem(UI_STATE_KEY, JSON.stringify(state.ui));
  } catch {
    // Ignore local storage write failures.
  }
}

const state = {
  bootstrapped: false,
  view: "game",
  drawer: null,
  loading: false,
  setupBusy: false,
  message: null,
  helpUrl: "",
  settings: {
    soundEnabled: true,
    pronunciationEnabled: true,
    displayOrder: "mixed",
    difficulty: "easy",
  },
  dictionary: {
    version: 0,
    totalCount: 0,
    updatedAt: null,
    lastCheckedAt: null,
    sourceUrl: null,
    items: [],
  },
  packs: {
    activePackId: null,
    items: [],
  },
  gameHistory: [],
  setup: {
    dictionaryReady: false,
    packsReady: false,
  },
  addWords: {
    raw: "",
    preview: [],
    quickAdd: "",
    packName: "",
    unmatched: [],
  },
  dictionaryIndex: new Map(),
  multiModeInput: "",
  multiModePreview: [],
  multiModeUnmatched: [],
  searchQuery: "",
  ui: loadUiState(),
  game: createGameState(),
  timerHandle: null,
  globalEventsBound: false,
  delegatedEventsBound: false,
};

function createGameState() {
  return {
    mode: "single",
    tiles: [],
    selectedIds: [],
    matchedPairs: new Set(),
    totalPairs: 0,
    matchedCount: 0,
    elapsedSeconds: 0,
    remainingSeconds: null,
    status: "idle",
    packId: null,
    packName: "",
    hintPairId: null,
    hasRecorded: false,
  };
}

function formatTime(seconds) {
  const safe = Math.max(0, Number(seconds || 0));
  const mins = String(Math.floor(safe / 60)).padStart(2, "0");
  const secs = String(safe % 60).padStart(2, "0");
  return `${mins}:${secs}`;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function shuffle(items) {
  const list = [...items];
  for (let index = list.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(Math.random() * (index + 1));
    [list[index], list[swapIndex]] = [list[swapIndex], list[index]];
  }
  return list;
}

function dedupeBy(items, getKey) {
  const seen = new Set();
  return items.filter((item) => {
    const key = getKey(item);
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

function text(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function lookupDictionaryWord(word) {
  const normalized = String(word || "").trim().toLowerCase();
  return state.dictionaryIndex.get(normalized) || null;
}

function normalizeEnglishCandidate(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9' -]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeSearchText(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

function normalizeCompactText(value) {
  return normalizeSearchText(value).replace(/\s+/g, "");
}

function getPinyinTokens(value) {
  if (!value) {
    return [];
  }

  try {
    const raw = toPinyin(String(value), {
      toneType: "none",
      type: "array",
      nonZh: "removed",
    });
    const list = Array.isArray(raw) ? raw : String(raw || "").split(/\s+/);
    const tokens = list.map((item) => normalizeSearchText(item)).filter(Boolean);
    if (!tokens.length) {
      return [];
    }
    return dedupeBy(
      [
        tokens.join(" "),
        tokens.join(""),
        tokens.map((item) => item[0]).join(""),
      ].filter(Boolean),
      (item) => item,
    );
  } catch {
    return [];
  }
}

function buildTileSearchIndex(tile) {
  const terms = new Set();
  const label = normalizeSearchText(tile.label);
  const labelCompact = normalizeCompactText(tile.label);
  const pair = normalizeSearchText(tile.pairId);
  const pairCompact = normalizeCompactText(tile.pairId);

  [label, labelCompact, pair, pairCompact].filter(Boolean).forEach((item) => terms.add(item));
  getPinyinTokens(tile.label).forEach((item) => {
    terms.add(item);
    terms.add(normalizeCompactText(item));
  });

  return [...terms];
}

function rebuildDictionaryIndex() {
  state.dictionaryIndex = new Map(
    state.dictionary.items.map((item) => [String(item.word || "").toLowerCase(), item]),
  );
}

function detectStructuredPair(line) {
  const raw = String(line || "").trim();
  if (!raw) {
    return null;
  }

  // Only match explicit separators (=, -, —, :, ：), NOT plain space
  // Plain space means multiple words, not a pair
  const matchers = [/^(.+?)=(.+)$/, /^(.+?)\s*[-—:：]\s*(.+)$/];
  for (const matcher of matchers) {
    const matched = raw.match(matcher);
    if (!matched) {
      continue;
    }
    const en = normalizeEnglishCandidate(matched[1]);
    const zh = matched[2].trim();
    if (/^[a-z0-9' -]+$/i.test(en) && zh) {
      return { en, zh };
    }
  }
  return null;
}

function extractWordsFromText(raw) {
  const words = String(raw || "")
    .match(/[A-Za-z]+(?:['-][A-Za-z]+)*/g)
    ?.map((item) => item.toLowerCase()) || [];
  return dedupeBy(words, (item) => item);
}

function resolveWordsFromDictionary(raw) {
  return dedupeBy(
    extractWordsFromText(raw)
      .map((word) => lookupDictionaryWord(word))
      .filter(Boolean)
      .map((item) => ({ en: item.word, zh: item.chinese })),
    (item) => item.en,
  );
}

function refreshMultiModePreview() {
  const lines = String(state.multiModeInput || "").split(/\n/);
  const matched = [];
  const unmatched = [];
  const seen = new Set();

  for (const line of lines) {
    const structured = detectStructuredPair(line);
    if (structured && !seen.has(structured.en)) {
      seen.add(structured.en);
      matched.push(structured);
      continue;
    }
    for (const word of extractWordsFromText(line)) {
      if (seen.has(word)) continue;
      seen.add(word);
      const hit = lookupDictionaryWord(word);
      if (hit) {
        matched.push({ en: hit.word, zh: hit.chinese });
      } else {
        unmatched.push({ en: word, zh: "" });
      }
    }
  }

  state.multiModePreview = matched;
  state.multiModeUnmatched = unmatched;
}

function parsePreviewWords(raw) {
  const lines = String(raw || "").split("\n");
  const pairs = [];
  const unmatched = new Set();

  for (const line of lines) {
    const structured = detectStructuredPair(line);
    if (structured) {
      pairs.push(structured);
      continue;
    }

    const words = extractWordsFromText(line);
    for (const word of words) {
      const hit = lookupDictionaryWord(word);
      if (hit) {
        pairs.push({ en: hit.word, zh: hit.chinese });
      } else {
        unmatched.add(word);
      }
    }
  }

  if (!pairs.length && !unmatched.size) {
    for (const word of extractWordsFromText(raw)) {
      const hit = lookupDictionaryWord(word);
      if (hit) {
        pairs.push({ en: hit.word, zh: hit.chinese });
      } else {
        unmatched.add(word);
      }
    }
  }

  const matchedPreview = dedupeBy(pairs, (item) => item.en).map((item) => ({
    id: crypto.randomUUID(),
    en: item.en,
    zh: item.zh,
    unresolved: false,
  }));

  const resolvedEnglishSet = new Set(matchedPreview.map((item) => item.en));
  const unmatchedPreview = [...unmatched]
    .filter((word) => !resolvedEnglishSet.has(word))
    .map((word) => ({
      id: crypto.randomUUID(),
      en: word,
      zh: "",
      unresolved: true,
    }));

  return {
    preview: [...matchedPreview, ...unmatchedPreview],
    unmatched: unmatchedPreview.map((item) => item.en),
  };
}

function buildSuggestedPackName(preview) {
  const labels = preview
    .map((item) => normalizeEnglishCandidate(item.en))
    .filter(Boolean)
    .slice(0, 3);

  if (!labels.length) {
    return "";
  }

  return `${labels.join(" / ")} · ${new Date().toLocaleString("zh-CN")}`;
}

function syncAddWordsPreview(preview) {
  const normalizedPreview = dedupeBy(
    preview
      .map((item) => ({
        ...item,
        en: normalizeEnglishCandidate(item.en),
        zh: String(item.zh || "").trim(),
      }))
      .filter((item) => item.en),
    (item) => item.en,
  ).map((item) => ({
    ...item,
    unresolved: !item.zh,
  }));

  state.addWords.preview = normalizedPreview;
  state.addWords.unmatched = normalizedPreview.filter((item) => item.unresolved).map((item) => item.en);

  if (!state.addWords.packName.trim() && normalizedPreview.length) {
    state.addWords.packName = buildSuggestedPackName(normalizedPreview);
  }
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
    ...options,
  });

  if (!response.ok) {
    let detail = response.statusText;
    try {
      const payload = await response.json();
      detail = payload.detail || payload.error || detail;
    } catch {
      // Ignore payload decoding failures.
    }
    throw new Error(detail || `HTTP ${response.status}`);
  }

  if (response.headers.get("content-type")?.includes("application/json")) {
    return response.json();
  }
  return response.text();
}

function showToast(kind, message) {
  state.message = {
    id: crypto.randomUUID(),
    kind,
    message,
  };
  render();
  window.clearTimeout(showToast.timeoutId);
  showToast.timeoutId = window.setTimeout(() => {
    state.message = null;
    render();
  }, 2600);
}

function playToneFallback(type) {
  if (!state.settings.soundEnabled) {
    return;
  }

  const AudioCtx = window.AudioContext || window.webkitAudioContext;
  if (!AudioCtx) {
    return;
  }

  const context = new AudioCtx();
  const oscillator = context.createOscillator();
  const gain = context.createGain();
  oscillator.connect(gain);
  gain.connect(context.destination);

  oscillator.type = type === "success" ? "triangle" : "sawtooth";
  oscillator.frequency.value = type === "success" ? 660 : 220;
  gain.gain.value = 0.08;

  oscillator.start();
  oscillator.stop(context.currentTime + (type === "success" ? 0.16 : 0.2));
}

function getCachedAudio(url) {
  if (!getCachedAudio.cache.has(url)) {
    const audio = new Audio(url);
    audio.preload = "auto";
    getCachedAudio.cache.set(url, audio);
  }
  return getCachedAudio.cache.get(url);
}

getCachedAudio.cache = new Map();

function playSound(type) {
  if (!state.settings.soundEnabled) {
    return;
  }

  const url = SOUND_URLS[type];
  if (!url) {
    playToneFallback(type);
    return;
  }

  try {
    const audio = getCachedAudio(url).cloneNode();
    audio.volume = type === "success" ? 0.6 : 0.5;
    audio.play().catch(() => playToneFallback(type));
  } catch {
    playToneFallback(type);
  }
}

function pronounceWord(word) {
  if (!state.settings.pronunciationEnabled || !word) {
    return;
  }

  const remoteAudio = new Audio(
    `https://dict.youdao.com/dictvoice?audio=${encodeURIComponent(word)}&type=2`,
  );
  remoteAudio.play().catch(() => {
    if (!("speechSynthesis" in window)) {
      return;
    }
    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(word);
    utterance.lang = "en-US";
    utterance.rate = 0.9;
    window.speechSynthesis.speak(utterance);
  });
}

function assignIndependentColors(tiles) {
  const palette = shuffle(COLORS);
  tiles.forEach((tile, index) => {
    tile.color = palette[index % palette.length];
  });

  const pairColorMap = new Map();
  for (let index = 0; index < tiles.length; index += 1) {
    const tile = tiles[index];
    const existing = pairColorMap.get(tile.pairId);
    if (!existing) {
      pairColorMap.set(tile.pairId, tile.color);
      continue;
    }

    if (existing[0] === tile.color[0] && existing[1] === tile.color[1]) {
      const swapIndex = tiles.findIndex(
        (candidate, candidateIndex) =>
          candidateIndex !== index &&
          candidate.pairId !== tile.pairId &&
          (candidate.color[0] !== tile.color[0] || candidate.color[1] !== tile.color[1]),
      );
      if (swapIndex >= 0) {
        [tiles[index].color, tiles[swapIndex].color] = [tiles[swapIndex].color, tiles[index].color];
      } else {
        tiles[index].color = palette[(index + 1) % palette.length];
      }
    }
  }

  return tiles;
}

function buildSingleModeTiles(words) {
  const displayOrder = state.settings.displayOrder;
  const zhTiles = words.map((word) => ({
    id: crypto.randomUUID(),
    pairId: word.en,
    type: "zh",
    label: word.zh,
    speak: word.en,
  }));
  const enTiles = words.map((word) => ({
    id: crypto.randomUUID(),
    pairId: word.en,
    type: "en",
    label: word.en,
    speak: word.en,
  }));

  let tiles;
  if (displayOrder === "zh-first") {
    tiles = [...shuffle(zhTiles), ...shuffle(enTiles)];
  } else if (displayOrder === "en-first") {
    tiles = [...shuffle(enTiles), ...shuffle(zhTiles)];
  } else {
    tiles = shuffle([...zhTiles, ...enTiles]);
  }

  return assignIndependentColors(tiles).map((tile) => ({
    ...tile,
    searchIndex: buildTileSearchIndex(tile),
  }));
}

function currentPack() {
  return state.packs.items.find((item) => item.id === state.packs.activePackId) || state.packs.items[0] || null;
}

function currentTimerValue() {
  if (state.settings.difficulty === "hard" && state.game.remainingSeconds !== null) {
    return state.game.remainingSeconds;
  }
  return state.game.elapsedSeconds;
}

function getSingleModePairCount() {
  const width = window.innerWidth || 1440;
  if (width >= 1500) {
    return 18;
  }
  if (width >= 1200) {
    return 15;
  }
  if (width >= 900) {
    return 12;
  }
  return 9;
}

function cycleDisplayOrder() {
  const order = ["zh-first", "en-first", "mixed"];
  const currentIndex = order.indexOf(state.settings.displayOrder);
  return order[(currentIndex + 1) % order.length];
}

function toggleDifficultyValue() {
  return state.settings.difficulty === "hard" ? "easy" : "hard";
}

function displayOrderLabel(value = state.settings.displayOrder) {
  if (value === "zh-first") {
    return "中文优先";
  }
  if (value === "en-first") {
    return "英文优先";
  }
  return "中英混合";
}

function difficultyLabel(value = state.settings.difficulty) {
  return value === "hard" ? "困难模式" : "简单模式";
}

function recordGameIfNeeded(status) {
  if (state.game.mode !== "single" || state.game.hasRecorded || !state.game.packId) {
    return;
  }

  state.game.hasRecorded = true;
  api("/api/history/game", {
    method: "POST",
    body: JSON.stringify({
      packId: state.game.packId,
      packName: state.game.packName,
      mode: state.game.mode,
      difficulty: state.settings.difficulty,
      displayOrder: state.settings.displayOrder,
      matchedCount: state.game.matchedCount,
      totalCount: state.game.totalPairs,
      durationSeconds: currentTimerValue(),
      status,
    }),
  })
    .then((result) => {
      state.gameHistory = [result.entry, ...state.gameHistory].slice(0, 100);
      render();
    })
    .catch(() => {
      state.game.hasRecorded = false;
    });
}

function stopTimer() {
  if (state.timerHandle) {
    window.clearInterval(state.timerHandle);
    state.timerHandle = null;
  }
}

function startTimer() {
  stopTimer();
  state.timerHandle = window.setInterval(() => {
    if (state.game.status !== "playing") {
      stopTimer();
      return;
    }

    state.game.elapsedSeconds += 1;
    if (state.settings.difficulty === "hard") {
      state.game.remainingSeconds = clamp((state.game.remainingSeconds ?? 0) - 1, 0, 9999);
      if (state.game.remainingSeconds === 0) {
        state.game.status = "lost";
        recordGameIfNeeded("lost");
        stopTimer();
        showToast("error", "时间到了，这局结束了。");
      }
    }

    render();
  }, 1000);
}

function startSingleGame(pack = currentPack()) {
  if (!pack?.words?.length) {
    state.game = createGameState();
    render();
    return;
  }

  const sampleCount = Math.min(getSingleModePairCount(), pack.words.length);
  const selectedWords = shuffle(pack.words).slice(0, sampleCount);
  const maxSeconds = state.settings.difficulty === "hard" ? Math.max(30, selectedWords.length * 7) : null;

  state.game = {
    ...createGameState(),
    mode: "single",
    tiles: buildSingleModeTiles(selectedWords),
    totalPairs: selectedWords.length,
    status: "playing",
    packId: pack.id,
    packName: pack.name,
    remainingSeconds: maxSeconds,
  };
  state.multiModeInput = "";
  state.multiModePreview = [];
  state.searchQuery = "";
  startTimer();
  render();
}

function startMultiModeGame() {
  const matched = state.multiModePreview.length
    ? state.multiModePreview
    : resolveWordsFromDictionary(state.multiModeInput);
  const manualWords = (state.multiModeUnmatched || []).filter((item) => item.zh.trim());
  const words = [...matched, ...manualWords];

  if (!words.length) {
    showToast("error", "没有在字典里找到可匹配的英文单词。");
    return;
  }

  state.game = {
    ...createGameState(),
    mode: "multi",
    tiles: buildSingleModeTiles(words),
    totalPairs: words.length,
    status: "playing",
    packId: null,
    packName: "临时多词模式",
    remainingSeconds: null,
  };
  state.searchQuery = "";
  refreshMultiModePreview();
  startTimer();
  render();
}

function switchGameMode(mode) {
  if (mode === state.game.mode) {
    return;
  }

  stopTimer();
  if (mode === "multi") {
    state.game = {
      ...createGameState(),
      mode: "multi",
    };
    refreshMultiModePreview();
  } else {
    startSingleGame();
    return;
  }
  render();
}

function handleTileClick(tileId) {
  if (state.game.status !== "playing") {
    return;
  }

  const tile = state.game.tiles.find((item) => item.id === tileId);
  if (!tile || state.game.matchedPairs.has(tile.pairId)) {
    return;
  }

  if (state.game.selectedIds.includes(tileId)) {
    state.game.selectedIds = state.game.selectedIds.filter((id) => id !== tileId);
    render();
    return;
  }

  const selectedIds = [...state.game.selectedIds, tileId];
  state.game.selectedIds = selectedIds;
  render();

  if (selectedIds.length < 2) {
    return;
  }

  const [first, second] = selectedIds.map((id) => state.game.tiles.find((item) => item.id === id));
  const isMatch =
    first &&
    second &&
    first.pairId === second.pairId &&
    first.type !== second.type;

  window.setTimeout(() => {
    if (isMatch) {
      state.game.matchedPairs.add(first.pairId);
      state.game.matchedCount = state.game.matchedPairs.size;
      playSound("success");
      pronounceWord(first.speak);

      if (state.game.matchedPairs.size === state.game.totalPairs) {
        state.game.status = "won";
        stopTimer();
        recordGameIfNeeded("won");
        showToast("success", "全部配对完成。");
      }
    } else {
      playSound("error");
    }

    state.game.selectedIds = [];
    render();
  }, isMatch ? 180 : 520);
}

function useHint() {
  if (state.game.mode !== "single" || state.game.status !== "playing") {
    return;
  }

  const remaining = dedupeBy(
    state.game.tiles.filter((tile) => !state.game.matchedPairs.has(tile.pairId)),
    (tile) => tile.pairId,
  );
  if (!remaining.length) {
    return;
  }

  const picked = remaining[Math.floor(Math.random() * remaining.length)];
  state.game.hintPairId = picked.pairId;
  render();
  window.setTimeout(() => {
    state.game.hintPairId = null;
    render();
  }, 1500);
}

function updateSearch(query) {
  state.searchQuery = query;
  // Update bubble highlights without re-rendering the whole DOM (prevents focus loss)
  document.querySelectorAll(".bubble").forEach((el) => {
    const tileId = el.dataset.action?.replace("tile:", "");
    if (!tileId) return;
    const tile = state.game.tiles.find((t) => t.id === tileId);
    if (!tile) return;
    const hit = searchMatchesTile(tile);
    el.classList.toggle("is-hint", hit || state.game.hintPairId === tile.pairId);
  });
}

function gameStatusMessage() {
  if (state.game.status === "won") {
    return "全部完成，点击重开可以继续下一局。";
  }
  if (state.game.status === "lost") {
    return "本局超时，点击重开再试一次。";
  }
  if (state.game.selectedIds.length >= 2) {
    return "正在校验配对…";
  }
  if (state.game.selectedIds.length === 1) {
    return "已选择 1 项，请继续选择对应配对词。";
  }
  return "选择 -> 匹配";
}

function searchMatchesTile(tile) {
  const query = normalizeSearchText(state.searchQuery);
  if (!query) {
    return false;
  }
  const compactQuery = normalizeCompactText(query);
  return (tile.searchIndex || []).some(
    (item) => item.includes(query) || item.includes(compactQuery),
  );
}

function findSearchTargetTile(query) {
  const normalized = normalizeSearchText(query);
  if (!normalized) {
    return null;
  }
  const compactQuery = normalizeCompactText(normalized);
  return (
    state.game.tiles.find(
      (item) =>
        !state.game.matchedPairs.has(item.pairId) &&
        (item.searchIndex || []).some(
          (token) => token.includes(normalized) || token.includes(compactQuery),
        ),
    ) || null
  );
}

function applySetting(patch, { restartGame = false } = {}) {
  state.settings = {
    ...state.settings,
    ...patch,
  };

  api("/api/settings", {
    method: "POST",
    body: JSON.stringify(state.settings),
  }).catch(() => {
    showToast("error", "设置保存失败。");
  });

  if (restartGame && state.game.mode === "single") {
    startSingleGame();
    return;
  }
  render();
}

function exportToFile(filename, payload) {
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

async function refreshBootstrap() {
  const payload = await api("/api/bootstrap");
  state.helpUrl = payload.helpUrl;
  state.settings = payload.settings;
  state.dictionary = payload.dictionary;
  rebuildDictionaryIndex();
  state.packs = payload.packs;
  state.gameHistory = payload.gameHistory;
  state.setup = payload.setup;
  refreshMultiModePreview();
  state.bootstrapped = true;

  if (!state.game.tiles.length && state.packs.items.length) {
    startSingleGame();
    return;
  }

  render();
}

async function handleOneClickPrepare(force = false) {
  state.setupBusy = true;
  render();
  try {
    await api("/api/setup/prepare", {
      method: "POST",
      body: JSON.stringify({ force }),
    });
    await refreshBootstrap();
    showToast("success", force ? "重新配置完成。" : "一键配置完成。");
  } catch (error) {
    showToast("error", `${force ? "重新配置" : "一键配置"}失败：${error.message}`);
  } finally {
    state.setupBusy = false;
    render();
  }
}

function updateUi(patch) {
  state.ui = {
    ...state.ui,
    ...patch,
  };
  saveUiState();
  render();
}

function openDrawer(name) {
  state.drawer = name;
  render();
  if (name === "add-words") {
    requestAnimationFrame(() => document.getElementById("add-words-raw")?.focus());
  }
}

function closeDrawer() {
  state.drawer = null;
  render();
}

function beginHelpResize(startX) {
  const startWidth = state.ui.helpWidth;

  function onMove(event) {
    const next = clamp(startWidth + (startX - event.clientX), 420, window.innerWidth - 32);
    state.ui.helpWidth = next;
    render();
  }

  function onUp() {
    window.removeEventListener("mousemove", onMove);
    window.removeEventListener("mouseup", onUp);
    saveUiState();
  }

  window.addEventListener("mousemove", onMove);
  window.addEventListener("mouseup", onUp);
}

async function createPackFromPreview() {
  if (!state.addWords.preview.length && state.addWords.raw.trim()) {
    const parsed = parsePreviewWords(state.addWords.raw);
    syncAddWordsPreview(parsed.preview);

    if (!state.addWords.preview.length) {
      showToast("error", "没有识别到可导入的词条。");
      render();
      return;
    }

    if (state.addWords.unmatched.length) {
      showToast("info", "已先整理出预览，请补全中文后再导入。");
      render();
      return;
    }
  }

  if (!state.addWords.preview.length) {
    showToast("error", "没有可导入的词条。");
    return;
  }

  const validWords = state.addWords.preview
    .map((item) => ({
      en: normalizeEnglishCandidate(item.en),
      zh: String(item.zh || "").trim(),
    }))
    .filter((item) => item.en && item.zh);

  const skippedCount = state.addWords.preview.length - validWords.length;
  if (!validWords.length) {
    showToast("error", "没有可导入的完整词条，请先补全中文。");
    return;
  }

  const pack = {
    name:
      state.addWords.packName.trim() || `导入词库 · ${new Date().toLocaleString("zh-CN")}`,
    source: "导入词库",
    words: validWords,
  };

  try {
    await api("/api/packs/create", {
      method: "POST",
      body: JSON.stringify({ pack }),
    });
    state.addWords = {
      raw: "",
      preview: [],
      quickAdd: "",
      packName: "",
      unmatched: [],
    };
    closeDrawer();
    await refreshBootstrap();
    startSingleGame(currentPack());
    showToast("success", skippedCount ? `词包已导入，跳过 ${skippedCount} 个未补全词条。` : "词包已导入。");
  } catch (error) {
    showToast("error", `导入失败：${error.message}`);
  }
}

async function importPacksFromFile(file) {
  if (!file) {
    return;
  }
  const raw = await file.text();
  try {
    const parsed = JSON.parse(raw);
    await api("/api/packs/import", {
      method: "POST",
      body: JSON.stringify({ json: parsed }),
    });
    await refreshBootstrap();
    showToast("success", "导入记录已导入。");
  } catch (error) {
    showToast("error", `导入记录失败：${error.message}`);
  }
}

async function importDictionaryFromFile(file) {
  if (!file) {
    return;
  }
  const raw = await file.text();
  try {
    const parsed = JSON.parse(raw);
    await api("/api/dictionary/import", {
      method: "POST",
      body: JSON.stringify({ json: parsed }),
    });
    await refreshBootstrap();
    showToast("success", "本地字典已导入。");
  } catch (error) {
    showToast("error", `字典导入失败：${error.message}`);
  }
}

function renderToast() {
  if (!state.message) {
    return "";
  }
  return `
    <div class="toast-wrap">
      <div class="toast is-${text(state.message.kind)}">${text(state.message.message)}</div>
    </div>
  `;
}

function renderSidebar() {
  const view = state.view;
  const compact = view === "game";
  const actions = [
    ["新增单词", "drawer:add-words", "+"],
    ["导入记录", "drawer:packs", "□"],
    ["游戏历史", "drawer:history", "↺"],
    ["帮助", "drawer:help", "?"],
    ["字典配置", "view:dictionary", "⚙"],
  ];

  return `
    <aside class="sidebar ${compact ? "is-compact" : ""}">
      <div class="brand">
        <div class="brand-mark">对</div>
        <div class="brand-copy">
          <div class="brand-title">单词对对碰</div>
          <div class="brand-subtitle">Word Match Local</div>
        </div>
      </div>
      <div class="nav">
        ${actions
          .map(
            ([label, action, icon], index) => `
              <button class="nav-button ${index === 4 ? "is-accent" : ""}" data-action="${action}">
                <span class="nav-icon">${text(icon)}</span>
                <span class="nav-label">${text(label)}</span>
                <span class="nav-tooltip">${text(label)}</span>
              </button>
            `,
          )
          .join("")}
      </div>
      ${compact ? "" : `
        <div class="nav-footer">
          <button class="nav-button is-accent" data-action="action:prepare" title="一键配置">
            <span class="nav-icon">配</span>
            <span class="nav-label">一键配置</span>
          </button>
          <button class="nav-button ${view === "game" ? "is-active" : ""}" data-action="view:game" title="返回游戏">
            <span class="nav-icon">游</span>
            <span class="nav-label">返回游戏</span>
          </button>
        </div>
      `}
    </aside>
  `;
}

function renderTimer() {
  if (state.game.status === "idle") return "";
  return `
    <div class="timer timer-fixed">
      <div class="muted">当前局面</div>
      <div class="timer-value">${text(formatTime(currentTimerValue()))}</div>
      <div class="pill">${text(state.game.mode === "multi" ? "多词模式" : difficultyLabel())}</div>
    </div>
  `;
}

function renderBubbles() {
  if (!state.game.tiles.length) {
    if (state.game.mode === "multi") {
      return `
        <div class="empty-state">
          <div class="card-title">准备多词匹配内容</div>
          <div style="margin-top: 10px">在下方输入一段英文内容，点“拆分”或“开始匹配”后就能生成这一局。</div>
        </div>
      `;
    }

    return `
      <div class="empty-state">
        <div class="card-title">还没有可玩的词包</div>
        <div style="margin-top: 10px">先做一键配置，或者从“新增单词”导入一组单词。</div>
      </div>
    `;
  }

  return `
    <div class="bubbles">
      ${state.game.tiles
        .map((tile) => {
          const hidden = state.game.matchedPairs.has(tile.pairId);
          const selected = state.game.selectedIds.includes(tile.id);
          const hinted = state.game.hintPairId === tile.pairId;
          const searchHit = searchMatchesTile(tile);
          const [from, to] = tile.color || COLORS[0];
          const floatDelay = `-${((tile.id.charCodeAt(0) * 7 + tile.id.charCodeAt(1) * 3) % 20) * 0.1}s`;
          const floatDuration = `${2.5 + ((tile.id.charCodeAt(0) + tile.id.charCodeAt(2)) % 15) * 0.1}s`;
          return `
            <button
              class="bubble ${hidden ? "is-hidden" : ""} ${selected ? "is-selected" : ""} ${hinted || searchHit ? "is-hint" : ""}"
              data-action="tile:${tile.id}"
              style="background: linear-gradient(135deg, ${from}, ${to}); --float-delay: ${floatDelay}; --float-duration: ${floatDuration};"
            >
              <span class="bubble-label">${text(tile.label)}</span>
            </button>
          `;
        })
        .join("")}
    </div>
  `;
}

function renderSingleControls() {
  const pack = currentPack();
  return `
    <div class="bottom-bar">
      <div class="bottom-top">
        <div style="flex: 1">
          <input
            class="search-input"
            id="search-input"
            value="${text(state.searchQuery)}"
            placeholder="搜索单词/拼音 (Enter 选择)"
          />
        </div>
        <div class="pill">进度 ${state.game.matchedCount}/${state.game.totalPairs || 0}</div>
      </div>
      <div class="message-bar">${text(gameStatusMessage())}</div>
      <div class="control-row control-row-dock">
        <button class="control-button ${state.settings.soundEnabled ? "is-active" : ""}" data-action="toggle-sound" title="${state.settings.soundEnabled ? "关闭音效" : "开启音效"}">
          音效
        </button>
        <button class="control-button ${state.settings.pronunciationEnabled ? "is-active" : ""}" data-action="toggle-pronounce" title="${state.settings.pronunciationEnabled ? "关闭单词发音" : "开启单词发音"}">
          发音
        </button>
        <button class="control-button" data-action="display-order-next" title="切换显示顺序">
          ${text(displayOrderLabel())}
        </button>
        <button class="control-button ${state.settings.difficulty === "hard" ? "is-active" : ""}" data-action="difficulty-toggle" title="切换难度">
          ${text(difficultyLabel())}
        </button>
        <button class="control-button" data-action="hint" title="提示配对词 (Ctrl / ⌘ + /)" ${state.game.mode !== "single" ? "disabled" : ""}>提示</button>
        <button class="control-button" data-action="restart">重开</button>
        <button class="control-button" data-action="switch-mode:multi">多词模式</button>
        <div class="control-spacer"></div>
        <div class="pill">${text(pack?.name || "当前词包")}</div>
        <button class="secondary-button" data-action="drawer:help" title="使用说明 (?)">使用说明</button>
      </div>
    </div>
  `;
}

function renderMultiControls() {
  const preview = state.multiModePreview;
  const unmatched = state.multiModeUnmatched || [];
  return `
    <div class="bottom-bar">
      <textarea class="textarea" id="multi-mode-input" placeholder="输入内容，空格或回车隔开。系统会从本地字典里匹配中译。">${text(state.multiModeInput)}</textarea>
      <div class="message-bar ${preview.length ? "is-success" : ""}">
        ${
          state.multiModeInput.trim()
            ? preview.length
              ? `已识别 ${preview.length} 个词：${text(preview.map((item) => item.en).slice(0, 6).join("、"))}${preview.length > 6 ? "…" : ""}${unmatched.length ? `，还有 ${unmatched.length} 个词未识别，请手动补全中文。` : ""}`
              : "当前输入里还没有识别到可匹配词条。"
            : "输入一段英文内容，系统会先拆分再从本地字典匹配中译。"
        }
      </div>
      ${unmatched.length ? `
        <div class="preview-table">
          ${unmatched.map((item) => `
            <div class="preview-row">
              <span class="pill">${text(item.en)}</span>
              <input class="inline-input ${item.zh ? "" : "is-warning"}" data-role="multi-unmatched-zh" data-en="${text(item.en)}" placeholder="请输入中文释义" value="${text(item.zh)}" />
            </div>
          `).join("")}
        </div>
      ` : ""}
      <div class="control-row">
        <button class="secondary-button" data-action="switch-mode:single">单词模式</button>
        <button class="ghost-button" data-action="multi-split">拆分</button>
        <button class="ghost-button" data-action="multi-clear">清空所有条目</button>
        <div class="control-spacer"></div>
        <div class="pill">已识别 ${preview.length + unmatched.filter(i => i.zh).length} 词</div>
        <button class="primary-button" data-action="start-multi" ${preview.length + unmatched.filter(i => i.zh).length >= 2 ? "" : "disabled"}>开始匹配</button>
      </div>
    </div>
  `;
}

function renderMultiModePreviewOnly() {
  const preview = state.multiModePreview;
  const unmatched = state.multiModeUnmatched || [];
  const bar = document.querySelector("#multi-mode-input ~ .message-bar");
  if (!bar) {
    render();
    return;
  }
  bar.className = `message-bar ${preview.length ? "is-success" : ""}`;
  bar.textContent = state.multiModeInput.trim()
    ? preview.length
      ? `已识别 ${preview.length} 个词：${preview.map((item) => item.en).slice(0, 6).join("、")}${preview.length > 6 ? "…" : ""}${unmatched.length ? `，还有 ${unmatched.length} 个词未识别，请手动补全中文。` : ""}`
      : "当前输入里还没有识别到可匹配词条。"
    : "输入一段英文内容，系统会先拆分再从本地字典匹配中译。";
  const pill = document.querySelector(".bottom-bar .control-row .pill");
  if (pill) pill.textContent = `已识别 ${preview.length + unmatched.filter(i => i.zh).length} 词`;
  // Re-render unmatched section if needed
  const existingTable = document.querySelector("[data-role='multi-unmatched-zh']")?.closest(".preview-table");
  if (unmatched.length && !existingTable) {
    render();
  }
}

function renderGameView() {
  return `
    <section class="game-view">
      <div class="board">${renderBubbles()}</div>
      ${state.game.mode === "multi" ? renderMultiControls() : renderSingleControls()}
      ${renderTimer()}
    </section>
  `;
}

function renderDictionaryView() {
  const version = state.dictionary.version ? `v${state.dictionary.version}` : "未初始化";
  return `
    <section class="dictionary-view">
      <div class="dictionary-header">
        <div>
          <div class="page-title">字典配置</div>
          <div class="page-subtitle">本地离线词典、远程更新、JSON 备份都在这里处理。</div>
        </div>
        <div class="banner-actions">
          <button class="secondary-button" data-action="view:game">返回游戏</button>
        </div>
      </div>
      <div class="section-grid">
        <div class="card">
          <div class="muted">本地存储</div>
          <div class="metric-number">${text(String(state.dictionary.totalCount || 0))}</div>
          <div class="stats-row">
            <div class="pill">当前版本 ${text(version)}</div>
            <div class="pill">最后更新 ${text(state.dictionary.updatedAt ? new Date(state.dictionary.updatedAt).toLocaleString("zh-CN") : "暂未导入")}</div>
          </div>
          <div class="message-bar">最近检查：${text(state.dictionary.lastCheckedAt ? new Date(state.dictionary.lastCheckedAt).toLocaleString("zh-CN") : "暂未检查")}</div>
        </div>
        <div class="card">
          <div class="muted">操作</div>
          <div class="card-actions" style="margin-top: 18px">
            <button class="primary-button" data-action="dictionary-import-open">导入字典</button>
            <button class="secondary-button" data-action="dictionary-export">导出备份</button>
            <button class="secondary-button" data-action="dictionary-check">检查更新</button>
            <button class="ghost-button" data-action="dictionary-update">更新字典</button>
            <button class="danger-button" data-action="dictionary-clear" ${state.dictionary.totalCount ? "" : "disabled"}>清空数据</button>
            <input id="dictionary-file-input" type="file" accept="application/json,.json" hidden />
          </div>
          <div class="message-bar">当前实现支持远程拉取词典、手动导入 JSON、导出本地备份。</div>
        </div>
      </div>
    </section>
  `;
}

function renderAddWordsDrawer() {
  const resolvedCount = state.addWords.preview.filter((item) => item.zh.trim()).length;
  const unresolvedCount = state.addWords.preview.length - resolvedCount;
  return `
    <div class="drawer-mask" data-action="close-drawer"></div>
    <aside class="drawer drawer-form">
      <div class="drawer-header">
        <div>
          <div class="drawer-title">单词录入</div>
          <div class="drawer-subtitle">支持 english=中文、english 中文，或者直接粘贴一段英文文本自动补全。</div>
        </div>
        <button class="icon-button" data-action="close-drawer">×</button>
      </div>
      <div class="drawer-body drawer-body-scroll">
        <div class="drawer-stack">
        <input class="inline-input" id="add-words-pack-name" placeholder="词包名称（可选）" value="${text(state.addWords.packName)}" />
        <textarea class="textarea" id="add-words-raw">${text(state.addWords.raw)}</textarea>
        <div class="inline-actions">
          <button class="secondary-button" data-action="add-words-autocomplete">自动完成</button>
          <button class="ghost-button" data-action="add-words-clear">清空</button>
        </div>
        ${
          state.addWords.preview.length
            ? `
              <div class="message-bar ${unresolvedCount ? "" : "is-success"}">
                已整理 ${resolvedCount} 个完整词条${unresolvedCount ? `，还有 ${unresolvedCount} 个需要手动补全中文。` : "，可以直接导入。"}
              </div>
              ${
                state.addWords.unmatched.length
                  ? `
                    <div class="tag-list">
                      ${state.addWords.unmatched.map((item) => `<span class="tag">待补全: ${text(item)}</span>`).join("")}
                    </div>
                  `
                  : ""
              }
            `
            : ""
        }
        ${
          state.addWords.preview.length
            ? `
              <div class="drawer-card">
                <div class="card-title">预览词条（${state.addWords.preview.length}）</div>
                <div class="preview-table" style="margin-top: 14px">
                  ${state.addWords.preview
                    .map(
                      (item) => `
                        <div class="preview-row">
                          <input class="inline-input" data-role="preview-en" data-id="${item.id}" value="${text(item.en)}" />
                          <input class="inline-input ${item.unresolved ? "is-warning" : ""}" data-role="preview-zh" data-id="${item.id}" placeholder="${item.unresolved ? "请补充中文释义" : ""}" value="${text(item.zh)}" />
                          <button class="danger-button" data-action="remove-preview:${item.id}">删除</button>
                        </div>
                      `,
                    )
                    .join("")}
                </div>
                <div class="inline-actions" style="margin-top: 14px">
                  <input class="inline-input" id="quick-add-input" placeholder="快速添加：比如 market 或 market=市场" value="${text(state.addWords.quickAdd)}" />
                  <button class="secondary-button" data-action="quick-add">添加</button>
                </div>
              </div>
            `
            : `
              <div class="empty-state">先点“自动完成”，系统会把可识别词条整理成可编辑预览。</div>
            `
        }
        </div>
      </div>
      <div class="drawer-footer">
        <div class="inline-actions">
          <button class="primary-button" data-action="create-pack" ${state.addWords.preview.length ? "" : "disabled"}>导入并开始游戏</button>
        </div>
      </div>
    </aside>
  `;
}

function renderPackDrawer() {
  return `
    <div class="drawer-mask" data-action="close-drawer"></div>
    <aside class="drawer">
      <div class="drawer-header">
        <div>
          <div class="drawer-title">导入记录</div>
          <div class="drawer-subtitle">这里管理所有词包，支持导入、导出、改名、开始和删除。</div>
        </div>
        <div class="inline-actions">
          <button class="secondary-button" data-action="packs-import-open">导入</button>
          <button class="secondary-button" data-action="packs-export">导出</button>
          <button class="danger-button" data-action="packs-clear" ${state.packs.items.length ? "" : "disabled"}>清空记录</button>
          <button class="icon-button" data-action="close-drawer">×</button>
          <input id="packs-file-input" type="file" accept="application/json,.json" hidden />
        </div>
      </div>
      ${
        state.packs.items.length
          ? `
            <div class="pack-list">
              ${state.packs.items
                .map((pack) => {
                  const preview = pack.words.slice(0, 4).map((word) => word.en);
                  const active = pack.id === state.packs.activePackId;
                  return `
                    <div class="drawer-card">
                      <div class="card-title-row">
                        <input class="inline-input" data-role="pack-name" data-id="${pack.id}" value="${text(pack.name)}" />
                        <div class="pill">${pack.words.length} 单词</div>
                      </div>
                      <div class="muted" style="margin-top: 10px">${text(pack.source)} · ${text(pack.createdAtLabel)}</div>
                      <div class="tag-list">
                        ${preview.map((word) => `<span class="tag">${text(word)}</span>`).join("")}
                        ${pack.words.length > 4 ? `<span class="tag">+${pack.words.length - 4}</span>` : ""}
                      </div>
                      <div class="card-actions" style="margin-top: 14px">
                        <button class="${active ? "primary-button" : "secondary-button"}" data-action="activate-pack:${pack.id}">${active ? "进行中" : "开始这一组单词"}</button>
                        <button class="danger-button" data-action="delete-pack:${pack.id}">删除</button>
                      </div>
                    </div>
                  `;
                })
                .join("")}
            </div>
          `
          : `<div class="empty-state">还没有导入记录。你可以先从“新增单词”生成一组，或者导入一份 JSON。</div>`
      }
    </aside>
  `;
}

function renderHistoryDrawer() {
  return `
    <div class="drawer-mask" data-action="close-drawer"></div>
    <aside class="drawer">
      <div class="drawer-header">
        <div>
          <div class="drawer-title">历史记录</div>
          <div class="drawer-subtitle">这里只记录完成或失败的正式游戏局。</div>
        </div>
        <div class="inline-actions">
          <button class="danger-button" data-action="clear-history" ${state.gameHistory.length ? "" : "disabled"}>清空历史</button>
          <button class="icon-button" data-action="close-drawer">×</button>
        </div>
      </div>
      ${
        state.gameHistory.length
          ? `
            <div class="history-list">
              ${state.gameHistory
                .map(
                  (item) => `
                    <div class="drawer-card">
                      <div class="card-title-row">
                        <div class="card-title">${text(item.packName)}</div>
                        <div class="pill">${text(item.status === "won" ? "完成" : "失败")}</div>
                      </div>
                      <div class="muted" style="margin-top: 10px">
                        ${text(new Date(item.completedAt).toLocaleString("zh-CN"))} · ${text(item.mode)} · ${text(item.difficulty)}
                      </div>
                      <div class="progress-strip">
                        <span class="progress-chip">进度 ${item.matchedCount}/${item.totalCount}</span>
                        <span class="progress-chip">时长 ${formatTime(item.durationSeconds)}</span>
                        <span class="progress-chip">${text(item.displayOrder)}</span>
                      </div>
                      <div class="card-actions" style="margin-top: 14px">
                        <button class="danger-button" data-action="delete-history:${item.id}">删除</button>
                      </div>
                    </div>
                  `,
                )
                .join("")}
            </div>
          `
          : `<div class="empty-state">还没有游戏历史。先开始一局吧，记录你的学习旅程。</div>`
      }
    </aside>
  `;
}

function renderHelpDrawer() {
  return `
    <div class="drawer-mask" data-action="close-drawer"></div>
    <aside class="drawer drawer-help">
      <div class="drawer-header">
        <div>
          <div class="drawer-title">使用帮助</div>
        </div>
        <button class="icon-button" data-action="close-drawer">×</button>
      </div>
      <div class="drawer-body" style="display:flex;align-items:center;justify-content:center;font-size:18px;color:var(--muted);">
        遇到Bug请联系master进行维护！
      </div>
    </aside>
  `;
}

function renderDrawer() {
  if (state.drawer === "add-words") {
    return renderAddWordsDrawer();
  }
  if (state.drawer === "packs") {
    return renderPackDrawer();
  }
  if (state.drawer === "history") {
    return renderHistoryDrawer();
  }
  if (state.drawer === "help") {
    return renderHelpDrawer();
  }
  return "";
}

function renderSetupBanner() {
  if (state.drawer) {
    return "";
  }

  const needsSetup = !state.setup.dictionaryReady || !state.setup.packsReady;
  if (state.view === "game" && !needsSetup) {
    return "";
  }

  if (!needsSetup && state.ui.setupBannerCollapsed) {
    return `
      <div class="banner banner-compact">
        <div class="banner-row">
          <div>
            <div class="card-title">配置完成</div>
            <div class="page-subtitle">本地字典和导入记录已就绪，可随时展开后重新配置。</div>
          </div>
          <div class="banner-actions">
            <button class="secondary-button" data-action="setup-expand">展开</button>
          </div>
        </div>
      </div>
    `;
  }

  if (!needsSetup && !state.ui.setupBannerCollapsed) {
    return `
      <div class="banner">
        <div class="banner-row">
          <div>
            <div class="card-title">配置已完成</div>
            <div class="page-subtitle">当前字典和导入记录已经准备好。需要时可以重新拉取远程字典和示例词包。</div>
          </div>
          <div class="banner-actions">
            <button class="secondary-button" data-action="drawer:packs">查看导入记录</button>
            <button class="primary-button" data-action="action:reprepare" ${state.setupBusy ? "disabled" : ""}>
              ${state.setupBusy ? "正在重新配置..." : "重新配置"}
            </button>
            <button class="ghost-button" data-action="setup-collapse">收起</button>
          </div>
        </div>
        <div class="progress-strip">
          <span class="progress-chip is-done">✓ 本地字典</span>
          <span class="progress-chip is-done">✓ 导入记录</span>
          <span class="progress-chip is-done">✓ 自动完成（可选）</span>
        </div>
      </div>
    `;
  }

  if (!needsSetup) {
    return "";
  }

  const steps = [
    { label: "本地字典", done: state.setup.dictionaryReady },
    { label: "导入记录", done: state.setup.packsReady },
    { label: "自动完成（可选）", done: state.setup.dictionaryReady },
  ];

  return `
    <div class="banner">
      <div class="banner-row">
        <div>
          <div class="card-title">一键准备字典与导入记录</div>
          <div class="page-subtitle">自动初始化本地字典，并加载示例词包；没有远程数据时会回退到内置模板。</div>
        </div>
        <div class="banner-actions">
          <button class="secondary-button" data-action="drawer:packs">查看导入记录</button>
          <button class="primary-button" data-action="action:prepare" ${state.setupBusy ? "disabled" : ""}>
            ${state.setupBusy ? "正在配置..." : "一键配置"}
          </button>
          <button class="ghost-button" data-action="setup-collapse">收起</button>
        </div>
      </div>
      <div class="progress-strip">
        ${steps
          .map(
            (step) => `
              <span class="progress-chip ${step.done ? "is-done" : ""}">
                ${step.done ? "✓" : "○"} ${text(step.label)}
              </span>
            `,
          )
          .join("")}
      </div>
    </div>
  `;
}

function render() {
  const app = document.getElementById("app");
  app.innerHTML = `
    ${renderToast()}
    <div class="shell ${state.view === "game" ? "is-game-shell" : ""}">
      ${renderSidebar()}
      <main class="main">
        ${state.view === "dictionary" ? renderDictionaryView() : renderGameView()}
        ${renderSetupBanner()}
      </main>
    </div>
    ${renderDrawer()}
  `;
}

function bindDelegatedEvents() {
  if (state.delegatedEventsBound) {
    return;
  }

  document.addEventListener("click", async (event) => {
    const actionNode = event.target.closest("[data-action]");
    if (!actionNode) {
      return;
    }

    const action = actionNode.dataset.action;

    if (action === "close-drawer") {
      closeDrawer();
      return;
    }
    if (action === "action:prepare") {
      await handleOneClickPrepare(false);
      return;
    }
    if (action === "action:reprepare") {
      await handleOneClickPrepare(true);
      return;
    }
    if (action === "setup-collapse") {
      updateUi({ setupBannerCollapsed: true });
      return;
    }
    if (action === "setup-expand") {
      updateUi({ setupBannerCollapsed: false });
      return;
    }
    if (action === "view:dictionary") {
      state.view = "dictionary";
      render();
      return;
    }
    if (action === "view:game") {
      state.view = "game";
      render();
      return;
    }
    if (action.startsWith("drawer:")) {
      openDrawer(action.split(":")[1]);
      return;
    }
    if (action.startsWith("tile:")) {
      handleTileClick(action.split(":")[1]);
      return;
    }
    if (action === "toggle-sound") {
      applySetting({ soundEnabled: !state.settings.soundEnabled });
      return;
    }
    if (action === "toggle-pronounce") {
      applySetting({ pronunciationEnabled: !state.settings.pronunciationEnabled });
      return;
    }
    if (action === "display-order-next") {
      applySetting({ displayOrder: cycleDisplayOrder() }, { restartGame: true });
      return;
    }
    if (action === "difficulty-toggle") {
      applySetting({ difficulty: toggleDifficultyValue() }, { restartGame: true });
      return;
    }
    if (action === "toggle-controls") {
      updateUi({ controlsExpanded: !state.ui.controlsExpanded });
      return;
    }
    if (action.startsWith("display-order:")) {
      applySetting({ displayOrder: action.split(":")[1] }, { restartGame: true });
      return;
    }
    if (action.startsWith("difficulty:")) {
      applySetting({ difficulty: action.split(":")[1] }, { restartGame: true });
      return;
    }
    if (action === "hint") {
      useHint();
      return;
    }
    if (action === "restart") {
      state.game.mode === "single" ? startSingleGame() : startMultiModeGame();
      return;
    }
    if (action === "switch-mode:multi") {
      switchGameMode("multi");
      return;
    }
    if (action === "switch-mode:single") {
      switchGameMode("single");
      return;
    }
    if (action === "multi-clear") {
      state.multiModeInput = "";
      state.multiModePreview = [];
      state.multiModeUnmatched = [];
      render();
      return;
    }
    if (action === "multi-split") {
      refreshMultiModePreview();
      render();
      const total = state.multiModePreview.length + (state.multiModeUnmatched || []).length;
      showToast(
        total ? "success" : "info",
        total
          ? `已整理出 ${state.multiModePreview.length} 个匹配词条${state.multiModeUnmatched.length ? `，${state.multiModeUnmatched.length} 个未识别，请手动补全中文。` : "。"}`
          : "当前没有识别到可匹配词条。",
      );
      return;
    }
    if (action === "start-multi") {
      refreshMultiModePreview();
      startMultiModeGame();
      return;
    }
    if (action === "add-words-clear") {
      state.addWords = { raw: "", preview: [], quickAdd: "", packName: "", unmatched: [] };
      render();
      return;
    }
    if (action === "add-words-autocomplete") {
      const activeId = document.activeElement?.id;
      const parsed = parsePreviewWords(state.addWords.raw);
      syncAddWordsPreview(parsed.preview);
      render();
      if (activeId) document.getElementById(activeId)?.focus();
      if (!state.addWords.preview.length) {
        showToast("error", "没有识别到可用词条，请先准备本地字典。");
      } else if (state.addWords.unmatched.length) {
        showToast("info", `已识别 ${state.addWords.preview.length} 个词条，请补全 ${state.addWords.unmatched.length} 个中文释义。`);
      }
      return;
    }
    if (action.startsWith("remove-preview:")) {
      const id = action.split(":")[1];
      syncAddWordsPreview(state.addWords.preview.filter((item) => item.id !== id));
      render();
      return;
    }
    if (action === "quick-add") {
      const added = parsePreviewWords(state.addWords.quickAdd);
      syncAddWordsPreview([...state.addWords.preview, ...added.preview]);
      state.addWords.quickAdd = "";
      render();
      return;
    }
    if (action === "create-pack") {
      await createPackFromPreview();
      return;
    }
    if (action === "packs-import-open") {
      document.getElementById("packs-file-input")?.click();
      return;
    }
    if (action === "packs-export") {
      exportToFile(`word-match-packs-${Date.now()}.json`, { historyItems: state.packs.items });
      return;
    }
    if (action === "packs-clear") {
      if (!window.confirm("确定要清空全部导入记录吗？")) {
        return;
      }
      await api("/api/packs/clear", { method: "POST", body: JSON.stringify({}) });
      await refreshBootstrap();
      showToast("success", "导入记录已清空。");
      return;
    }
    if (action.startsWith("activate-pack:")) {
      const packId = action.split(":")[1];
      await api(`/api/packs/${packId}/activate`, { method: "POST", body: JSON.stringify({}) });
      await refreshBootstrap();
      startSingleGame(currentPack());
      closeDrawer();
      showToast("success", "已切换词包。");
      return;
    }
    if (action.startsWith("delete-pack:")) {
      const packId = action.split(":")[1];
      await api(`/api/packs/${packId}`, { method: "DELETE" });
      await refreshBootstrap();
      startSingleGame(currentPack());
      showToast("success", "词包已删除。");
      return;
    }
    if (action === "clear-history") {
      if (!window.confirm("确定要清空全部游戏历史吗？")) {
        return;
      }
      await api("/api/history/game/clear", { method: "POST", body: JSON.stringify({}) });
      await refreshBootstrap();
      showToast("success", "游戏历史已清空。");
      return;
    }
    if (action.startsWith("delete-history:")) {
      const historyId = action.split(":")[1];
      await api(`/api/history/game/${historyId}`, { method: "DELETE" });
      await refreshBootstrap();
      showToast("success", "历史记录已删除。");
      return;
    }
    if (action === "dictionary-import-open") {
      document.getElementById("dictionary-file-input")?.click();
      return;
    }
    if (action === "dictionary-export") {
      exportToFile(`word-match-dictionary-${Date.now()}.json`, {
        version: state.dictionary.version,
        items: state.dictionary.items,
      });
      return;
    }
    if (action === "dictionary-check") {
      try {
        const result = await api("/api/dictionary/check-update", {
          method: "POST",
          body: JSON.stringify({}),
        });
        showToast(
          "info",
          result.hasUpdate ? `发现新版本 v${result.latestVersion}` : "当前已是最新版本。",
        );
        await refreshBootstrap();
      } catch (error) {
        showToast("error", `检查更新失败：${error.message}`);
      }
      return;
    }
    if (action === "dictionary-update") {
      try {
        await api("/api/dictionary/update", {
          method: "POST",
          body: JSON.stringify({}),
        });
        await refreshBootstrap();
        showToast("success", "字典更新成功。");
      } catch (error) {
        showToast("error", `字典更新失败：${error.message}`);
      }
      return;
    }
    if (action === "dictionary-clear") {
      if (!window.confirm("确定要清空本地字典吗？")) {
        return;
      }
      await api("/api/dictionary/clear", { method: "POST", body: JSON.stringify({}) });
      await refreshBootstrap();
      showToast("success", "本地字典已清空。");
    }
  });

  document.addEventListener("input", (event) => {
    const target = event.target;
    if (target.id === "search-input") {
      updateSearch(target.value);
      return;
    }
    if (target.id === "multi-mode-input") {
      state.multiModeInput = target.value;
      refreshMultiModePreview();
      renderMultiModePreviewOnly();
      return;
    }
    if (target.id === "add-words-raw") {
      state.addWords.raw = target.value;
      return;
    }
    if (target.id === "quick-add-input") {
      state.addWords.quickAdd = target.value;
      return;
    }
    if (target.id === "add-words-pack-name") {
      state.addWords.packName = target.value;
      return;
    }
    if (target.dataset.role === "preview-en") {
      const item = state.addWords.preview.find((entry) => entry.id === target.dataset.id);
      if (item) {
        item.en = normalizeEnglishCandidate(target.value);
        if (!String(item.zh || "").trim()) {
          const hit = lookupDictionaryWord(item.en);
          if (hit) {
            item.zh = hit.chinese;
          }
        }
        item.unresolved = !String(item.zh || "").trim();
        state.addWords.unmatched = state.addWords.preview
          .filter((entry) => entry.unresolved)
          .map((entry) => entry.en);
      }
      return;
    }
    if (target.dataset.role === "preview-zh") {
      const item = state.addWords.preview.find((entry) => entry.id === target.dataset.id);
      if (item) {
        item.zh = target.value;
        item.unresolved = !String(item.zh || "").trim();
        state.addWords.unmatched = state.addWords.preview
          .filter((entry) => entry.unresolved)
          .map((entry) => entry.en);
      }
      return;
    }
    if (target.dataset.role === "multi-unmatched-zh") {
      const en = target.dataset.en;
      const item = (state.multiModeUnmatched || []).find((entry) => entry.en === en);
      if (item) {
        item.zh = target.value;
        const pill = document.querySelector(".bottom-bar .control-row .pill");
        if (pill) {
          const total = state.multiModePreview.length + state.multiModeUnmatched.filter(i => i.zh).length;
          pill.textContent = `已识别 ${total} 词`;
        }
        const btn = document.querySelector("[data-action='start-multi']");
        if (btn) {
          const total = state.multiModePreview.length + state.multiModeUnmatched.filter(i => i.zh).length;
          btn.disabled = total < 2;
        }
      }
    }
  });

  document.addEventListener("change", async (event) => {
    const target = event.target;

    if (target.dataset.role === "pack-name") {
      const id = target.dataset.id;
      try {
        await api(`/api/packs/${id}`, {
          method: "PATCH",
          body: JSON.stringify({ name: target.value }),
        });
        await refreshBootstrap();
        showToast("success", "词包名称已更新。");
      } catch (error) {
        showToast("error", `更新失败：${error.message}`);
      }
      return;
    }

    if (target.id === "packs-file-input") {
      await importPacksFromFile(target.files?.[0]);
      target.value = "";
      return;
    }

    if (target.id === "dictionary-file-input") {
      await importDictionaryFromFile(target.files?.[0]);
      target.value = "";
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.target?.id === "search-input" && event.key === "Enter") {
      const query = state.searchQuery.trim();
      if (!query) {
        return;
      }
      const tile = findSearchTargetTile(query);
      if (tile) {
        handleTileClick(tile.id);
      }
    }
  });

  document.addEventListener("mousedown", (event) => {
    const target = event.target.closest("[data-role='help-resizer']");
    if (target) {
      beginHelpResize(event.clientX);
    }
  });

  state.delegatedEventsBound = true;
}

async function init() {
  document.getElementById("app").innerHTML = `
    <div class="toast-wrap">
      <div class="toast is-info">正在加载本地版单词对对碰…</div>
    </div>
  `;
  try {
    await refreshBootstrap();
  } catch (error) {
    document.getElementById("app").innerHTML = `
      <div class="toast-wrap">
        <div class="toast is-error">应用初始化失败：${text(error.message)}</div>
      </div>
    `;
  }
}

function bindGlobalEvents() {
  if (state.globalEventsBound) {
    return;
  }

  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && state.drawer) {
      closeDrawer();
      return;
    }

    if ((event.ctrlKey || event.metaKey) && event.key === "/") {
      event.preventDefault();
      useHint();
      return;
    }

    if (!event.ctrlKey && !event.metaKey && event.key === "?") {
      event.preventDefault();
      openDrawer("help");
    }
  });

  state.globalEventsBound = true;
}

init();
bindGlobalEvents();
bindDelegatedEvents();
