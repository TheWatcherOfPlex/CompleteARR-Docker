const express = require("express");
const path = require("path");
const fs = require("fs");
const yaml = require("js-yaml");
const axios = require("axios");

const app = express();
const PORT = process.env.UI_PORT || 3005;

const APP_ROOT = process.env.APP_ROOT || "/app";

const SONARR_SETTINGS =
  process.env.SONARR_SETTINGS || path.join(APP_ROOT, "CompleteARR_Settings", "CompleteARR_SONARR_Settings.yml");
const RADARR_SETTINGS =
  process.env.RADARR_SETTINGS || path.join(APP_ROOT, "CompleteARR_Settings", "CompleteARR_RADARR_Settings.yml");

const LOGS_BASE = process.env.LOGS_BASE || path.join(APP_ROOT, "CompleteARR_Logs");
const FULL_LOGS_DIR = process.env.FULL_LOGS_DIR || path.join(LOGS_BASE, "Full Logs");
const ERROR_LOGS_DIR = process.env.ERROR_LOGS_DIR || path.join(LOGS_BASE, "Error Logs");
const STATUS_FILE = process.env.STATUS_FILE || path.join(LOGS_BASE, "run_status.json");
const RUN_LOCK_DIR = process.env.RUN_LOCK_DIR || path.join(LOGS_BASE, "run.lock");
// LOGS_ROOT is where the UI reads *full* logs for summaries.
const LOGS_ROOT = process.env.LOGS_ROOT || FULL_LOGS_DIR;
const MS_IN_DAY = 24 * 60 * 60 * 1000;

for (const dir of [LOGS_BASE, FULL_LOGS_DIR, ERROR_LOGS_DIR]) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function writeStatus(status, startedAt, finishedAt, nextRun) {
  const payload = {
    status,
    startedAt: startedAt || null,
    finishedAt: finishedAt || null,
    nextRun: nextRun || null
  };
  // Atomic write: write to temp file then rename to avoid partial reads.
  const tmpFile = STATUS_FILE + ".tmp." + Date.now() + "." + Math.random().toString(36).slice(2);
  fs.writeFileSync(tmpFile, JSON.stringify(payload));
  fs.renameSync(tmpFile, STATUS_FILE);
}

function tryAcquireLock() {
  try {
    fs.mkdirSync(RUN_LOCK_DIR);
    return true;
  } catch (error) {
    if (error && error.code === "EEXIST") {
      return false;
    }
    throw error;
  }
}

function releaseLock() {
  try {
    fs.rmdirSync(RUN_LOCK_DIR);
  } catch (error) {
    // ignore
  }
}

app.use(express.json({ limit: "1mb" }));
app.use(express.static(path.join(__dirname, "public")));
app.use(
  "/vendor",
  express.static(path.join(__dirname, "node_modules", "react", "umd"))
);
app.use(
  "/vendor",
  express.static(path.join(__dirname, "node_modules", "react-dom", "umd"))
);
app.use(
  "/vendor",
  express.static(path.join(__dirname, "node_modules", "htm", "dist"))
);

function readYaml(filePath) {
  if (!fs.existsSync(filePath)) {
    return { raw: "", data: null };
  }
  const raw = fs.readFileSync(filePath, "utf8");
  const data = yaml.load(raw);
  return { raw, data };
}

function parseSummary(lines, markers) {
  const summary = {};
  for (const line of lines) {
    for (const [key, label] of Object.entries(markers)) {
      if (line.includes(label)) {
        const parts = line.split(":");
        const value = parts[parts.length - 1].trim();
        const number = Number(value);
        summary[key] = Number.isFinite(number) ? number : value;
      }
    }
  }
  return summary;
}

function parseLogTimestampFromName(name) {
  const match = name.match(/_(\d{4}-\d{2}-\d{2})_(\d{4})\.log$/);
  if (!match) return null;
  const datePart = match[1];
  const timePart = match[2];
  const iso = `${datePart}T${timePart.slice(0, 2)}:${timePart.slice(2)}:00Z`;
  const parsed = Date.parse(iso);
  return Number.isNaN(parsed) ? null : parsed;
}

function collectLogSummaries(prefix, markers, days = 7) {
  // Only read from Full Logs to avoid base-folder conflicts.
  const logDirs = [LOGS_ROOT]
    .filter(Boolean)
    .filter((dir) => fs.existsSync(dir));

  if (!logDirs.length) {
    return [];
  }

  const cutoff = Date.now() - days * MS_IN_DAY;
  const fileEntries = logDirs.flatMap((dir) => {
    const names = fs
      .readdirSync(dir)
      .filter((name) => name.startsWith(prefix) && name.endsWith(".log"));
    return names.map((name) => ({ name, dir, fullPath: path.join(dir, name) }));
  });

  const unique = new Map();
  fileEntries.forEach((entry) => {
    if (!unique.has(entry.fullPath)) {
      unique.set(entry.fullPath, entry);
    }
  });

  return Array.from(unique.values())
    .map((entry) => {
      const stats = fs.statSync(entry.fullPath);
      const parsedTimestamp = parseLogTimestampFromName(entry.name) || stats.mtimeMs;
      if (parsedTimestamp < cutoff) {
        return null;
      }
      const raw = fs.readFileSync(entry.fullPath, "utf8");
      const lines = raw.split(/\r?\n/);
      const summary = parseSummary(lines, markers);
      if (!Object.keys(summary).length) {
        return null;
      }
      return {
        file: entry.name,
        timestamp: new Date(parsedTimestamp).toISOString(),
        summary
      };
    })
    .filter(Boolean)
    .sort((a, b) => (a.timestamp < b.timestamp ? 1 : -1));
}

function normalizeStatsResponse(payload) {
  return {
    radarr: payload.radarr || [],
    sonarr: payload.sonarr || []
  };
}

function writeYaml(filePath, data) {
  const content = yaml.dump(data, { lineWidth: 120, noRefs: true });
  fs.writeFileSync(filePath, content, "utf8");
}

function formatAbout(content) {
  if (!content) {
    return "";
  }
  return content
    .replace(/```[\s\S]*?```/g, (block) => block.replace(/```[a-z]*\n?/gi, "").replace(/```/g, "").trim())
    .replace(/^!\[.*?\]\(.*?\)\s*$/gm, "")
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/^---\s*$/gm, "")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/__([^_]+)__/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/_([^_]+)_/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\[([^\]]+)]\([^\)]+\)/g, "$1")
    .replace(/\r/g, "")
    .split("\n")
    .map((line) => line.trimEnd())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function requireConfig(config, type) {
  if (!config?.[type]?.Url || !config?.[type]?.ApiKey) {
    const missing = !config?.[type]?.Url ? "Url" : "ApiKey";
    throw new Error(`${type} ${missing} is missing in settings.`);
  }
}

async function fetchArrOptions(config, type) {
  requireConfig(config, type);
  const baseUrl = config[type].Url.replace(/\/$/, "");
  const apiKey = config[type].ApiKey;
  const headers = { "X-Api-Key": apiKey };

  const [profiles, roots] = await Promise.all([
    axios.get(`${baseUrl}/api/v3/qualityprofile`, { headers }),
    axios.get(`${baseUrl}/api/v3/rootfolder`, { headers })
  ]);

  return {
    profiles: profiles.data.map((p) => p.name),
    rootFolders: roots.data.map((r) => r.path)
  };
}

function readStatusFile() {
  if (!fs.existsSync(STATUS_FILE)) {
    return null;
  }
  const raw = fs.readFileSync(STATUS_FILE, "utf8").trim();
  if (!raw) {
    return null;
  }
  return JSON.parse(raw);
}

function ensureIdleStatus() {
  writeStatus("idle", null, null, null);
  return { status: "idle", startedAt: null, finishedAt: null, nextRun: null };
}

app.get("/api/status", (req, res) => {
  // Failsafe: if status says "running" but child process is gone and lock is released, force idle
  const lockExists = fs.existsSync(RUN_LOCK_DIR);
  const childRunning = global.runningChild && !global.runningChild.killed;

  try {
    const data = readStatusFile();

    if (!data) {
      return res.json(ensureIdleStatus());
    }

    // If status says running but child is gone, clear lock + reset to idle.
    if (data.status === "running" && !childRunning) {
      console.log("[status] Failsafe: detected stuck 'running' status, resetting to idle");
      if (lockExists) {
        releaseLock();
      }
      writeStatus("idle", data.startedAt, new Date().toISOString(), data.nextRun);
      return res.json({ status: "idle", startedAt: data.startedAt, finishedAt: new Date().toISOString(), nextRun: data.nextRun });
    }

    // If lock exists but status says idle and no child, clear stale lock
    if (data.status !== "running" && lockExists && !childRunning) {
      releaseLock();
    }

    return res.json(data);
  } catch (error) {
    console.error("Failed to read/parse status file:", error.message);
    return res.json(ensureIdleStatus());
  }
});

app.post("/api/run-now", (req, res) => {
  let statusData = null;
  try {
    statusData = readStatusFile();
  } catch (error) {
    statusData = null;
  }

  const lockExists = fs.existsSync(RUN_LOCK_DIR);
  const childRunning = global.runningChild && !global.runningChild.killed;

  if (statusData?.status === "running" && !childRunning) {
    releaseLock();
    statusData = { ...statusData, status: "idle", finishedAt: new Date().toISOString() };
    writeStatus("idle", statusData.startedAt, statusData.finishedAt, statusData.nextRun);
  }

  // If lock exists but we are idle and no child is running, clear stale lock.
  if (lockExists && (!statusData || statusData.status !== "running") && !childRunning) {
    releaseLock();
  }

  if (!tryAcquireLock()) {
    return res.status(409).json({ error: "Run already in progress." });
  }

  let nextRun = statusData?.nextRun || null;

  const startedAt = new Date().toISOString();
  writeStatus("running", startedAt, null, nextRun);

  const { spawn } = require("child_process");
  const child = spawn(
    "pwsh",
    ["./CompleteARR_Launchers/CompleteARR_Launch_All_Scripts.ps1"],
    {
      cwd: APP_ROOT,
      env: { ...process.env, COMPLETEARR_NO_PAUSE: "1" },
      stdio: "ignore"
    }
  );

  // Store child process ID for stopping
  global.runningChild = child;

  child.on("exit", () => {
    global.runningChild = null;
    const finishedAt = new Date().toISOString();
    writeStatus("idle", startedAt, finishedAt, nextRun);
    releaseLock();
  });

  child.on("error", (error) => {
    global.runningChild = null;
    const finishedAt = new Date().toISOString();
    writeStatus("idle", startedAt, finishedAt, nextRun);
    releaseLock();
  });

  return res.json({ ok: true });
});

app.post("/api/stop", (req, res) => {
  if (!global.runningChild) {
    return res.status(409).json({ error: "No run in progress." });
  }

  try {
    global.runningChild.kill("SIGTERM");
    return res.json({ ok: true, message: "Stop signal sent." });
  } catch (error) {
    return res.status(500).json({ error: "Failed to stop: " + error.message });
  }
});

app.post("/api/reset-status", (req, res) => {
  // Force reset status to idle and clear lock (for when runs get stuck)
  try {
    writeStatus("idle", null, null, null);
    releaseLock();
    global.runningChild = null;
    return res.json({ ok: true, message: "Status reset." });
  } catch (error) {
    return res.status(500).json({ error: "Failed to reset: " + error.message });
  }
});

app.get("/api/settings/sonarr", (req, res) => {
  const { data } = readYaml(SONARR_SETTINGS);
  return res.json(data || {});
});

app.get("/api/settings/radarr", (req, res) => {
  const { data } = readYaml(RADARR_SETTINGS);
  return res.json(data || {});
});

app.post("/api/settings/sonarr", (req, res) => {
  writeYaml(SONARR_SETTINGS, req.body);
  return res.json({ ok: true });
});

app.post("/api/settings/radarr", (req, res) => {
  writeYaml(RADARR_SETTINGS, req.body);
  return res.json({ ok: true });
});

app.get("/api/options/sonarr", async (req, res) => {
  try {
    const { data } = readYaml(SONARR_SETTINGS);
    const options = await fetchArrOptions(data, "Sonarr");
    res.json(options);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.get("/api/options/radarr", async (req, res) => {
  try {
    const { data } = readYaml(RADARR_SETTINGS);
    const options = await fetchArrOptions(data, "Radarr");
    res.json(options);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.get("/api/about", (req, res) => {
  const readmePath = path.join(__dirname, "..", "README.md");
  if (!fs.existsSync(readmePath)) {
    return res.json({ content: "README.md not found" });
  }
  const content = fs.readFileSync(readmePath, "utf8");
  res.json({ content: formatAbout(content) });
});

app.get("/api/stats/weekly", (req, res) => {
  const radarrMarkers = {
    moviesChecked: "Movies checked",
    moviesAlreadyCorrect: "Movies already correct",
    moviesSkipped: "Movies skipped",
    rootCorrections: "Root corrections",
    errors: "Errors"
  };

  const sonarrMarkers = {
    seriesChecked: "Series checked",
    incompleteSeriesSeen: "Incomplete series seen",
    promotions: "Promotions",
    demotions: "Demotions",
    specialsMonitored: "Specials monitored",
    rootCorrections: "Root corrections",
    errors: "Errors",
    episodeMonitorChanges: "Episode monitor changes"
  };

  const radarr = collectLogSummaries("CompleteARR_RADARR_FilmEngine", radarrMarkers, 7);
  const sonarr = collectLogSummaries("CompleteARR_SONARR_SeriesEngine", sonarrMarkers, 7);

  res.json(normalizeStatsResponse({ radarr, sonarr }));
});

app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.listen(PORT, () => {
  console.log(`CompleteARR UI listening on port ${PORT}`);
});