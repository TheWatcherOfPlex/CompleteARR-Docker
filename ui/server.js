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

app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.listen(PORT, () => {
  console.log(`CompleteARR UI listening on port ${PORT}`);
});