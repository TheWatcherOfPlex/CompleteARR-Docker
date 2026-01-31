const express = require("express");
const path = require("path");
const fs = require("fs");
const yaml = require("js-yaml");
const axios = require("axios");

const app = express();
const PORT = process.env.UI_PORT || 3005;

const SONARR_SETTINGS = process.env.SONARR_SETTINGS || "/app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml";
const RADARR_SETTINGS = process.env.RADARR_SETTINGS || "/app/CompleteARR_Settings/CompleteARR_RADARR_Settings.yml";
const STATUS_FILE = process.env.STATUS_FILE || "/app/CompleteARR_Logs/run_status.json";
const LOGS_ROOT = process.env.LOGS_ROOT || "/app/CompleteARR_Logs";
const MS_IN_DAY = 24 * 60 * 60 * 1000;

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

function collectLogSummaries(prefix, markers, days = 7) {
  if (!fs.existsSync(LOGS_ROOT)) {
    return [];
  }
  const cutoff = Date.now() - days * MS_IN_DAY;
  const files = fs
    .readdirSync(LOGS_ROOT)
    .filter((name) => name.startsWith(prefix) && name.endsWith(".log"))
    .sort();

  return files
    .map((name) => {
      const fullPath = path.join(LOGS_ROOT, name);
      const stats = fs.statSync(fullPath);
      if (stats.mtimeMs < cutoff) {
        return null;
      }
      const raw = fs.readFileSync(fullPath, "utf8");
      const lines = raw.split(/\r?\n/);
      const summary = parseSummary(lines, markers);
      if (!Object.keys(summary).length) {
        return null;
      }
      return {
        file: name,
        timestamp: stats.mtime.toISOString(),
        summary
      };
    })
    .filter(Boolean)
    .sort((a, b) => (a.timestamp < b.timestamp ? 1 : -1));
}

function writeYaml(filePath, data) {
  const content = yaml.dump(data, { lineWidth: 120, noRefs: true });
  fs.writeFileSync(filePath, content, "utf8");
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

app.get("/api/status", (req, res) => {
  if (!fs.existsSync(STATUS_FILE)) {
    return res.json({ status: "unknown", startedAt: null, finishedAt: null, nextRun: null });
  }
  const raw = fs.readFileSync(STATUS_FILE, "utf8");
  return res.json(JSON.parse(raw));
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
  res.json({ content });
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

  res.json({
    radarr,
    sonarr
  });
});

app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.listen(PORT, () => {
  console.log(`CompleteARR UI listening on port ${PORT}`);
});