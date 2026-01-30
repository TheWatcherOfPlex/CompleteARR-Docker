const { useEffect, useMemo, useState } = React;
const html = htm.bind(React.createElement);

const DEFAULT_STATUS = { status: "unknown", startedAt: null, finishedAt: null, nextRun: null };
const DEFAULT_OPTIONS = { profiles: [], rootFolders: [] };

function useApi(path, fallback) {
  const [data, setData] = useState(fallback);
  const [error, setError] = useState(null);

  useEffect(() => {
    let isMounted = true;
    fetch(path)
      .then((res) => res.json())
      .then((payload) => {
        if (isMounted) {
          setData(payload);
          setError(null);
        }
      })
      .catch((err) => {
        if (isMounted) {
          setError(err.message);
        }
      });
    return () => {
      isMounted = false;
    };
  }, [path]);

  return { data, setData, error };
}

const formatDate = (value) => (value ? new Date(value).toLocaleString() : "—");

const NAV_ITEMS = [
  { key: "home", label: "Home" },
  { key: "sonarr", label: "Sonarr" },
  { key: "radarr", label: "Radarr" },
  { key: "shared", label: "Shared" },
  { key: "about", label: "About" }
];

function App() {
  const [view, setView] = useState("home");
  const [message, setMessage] = useState("");

  const statusApi = useApi("/api/status", DEFAULT_STATUS);
  const sonarrApi = useApi("/api/settings/sonarr", {});
  const radarrApi = useApi("/api/settings/radarr", {});
  const sonarrOptionsApi = useApi("/api/options/sonarr", DEFAULT_OPTIONS);
  const radarrOptionsApi = useApi("/api/options/radarr", DEFAULT_OPTIONS);
  const aboutApi = useApi("/api/about", { content: "" });

  const handleInput = (setter, path) => (event) => {
    const value = event.target.type === "number" ? Number(event.target.value) : event.target.value;
    setter((prev) => {
      const next = JSON.parse(JSON.stringify(prev || {}));
      const keys = path.split(".");
      let cursor = next;
      keys.slice(0, -1).forEach((key) => {
        if (!cursor[key]) cursor[key] = {};
        cursor = cursor[key];
      });
      cursor[keys[keys.length - 1]] = value;
      return next;
    });
  };

  const saveSettings = async (path, payload, label) => {
    await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    setMessage(`${label} saved successfully.`);
    setTimeout(() => setMessage(""), 3000);
  };

  const addSet = () => {
    sonarrApi.setData((prev) => {
      const next = JSON.parse(JSON.stringify(prev || {}));
      if (!next.Sets) next.Sets = [];
      next.Sets.push({
        "Media Type": "",
        "Incomplete Profile Name": "",
        "Incomplete Root Folder": "",
        "Complete Profile Name": "",
        "Complete Root Folder": ""
      });
      return next;
    });
  };

  const sets = sonarrApi.data?.Sets || [];
  const sonarrProfiles = sonarrOptionsApi.data?.profiles || [];
  const sonarrRoots = sonarrOptionsApi.data?.rootFolders || [];
  const radarrProfiles = radarrOptionsApi.data?.profiles || [];
  const radarrRoots = radarrOptionsApi.data?.rootFolders || [];
  const radarrMappings = radarrApi.data?.FilmEngine?.ProfileRootMappings || {};
  const sharedLogging = sonarrApi.data?.Logging || {};

  const content = useMemo(() => {
    if (view === "home") {
      return html`
        <>
          <div className="card">
            <h2>Welcome</h2>
            <p>Use the tabs above to configure Sonarr, Radarr, and shared settings. Changes are saved to your YAML files.</p>
          </div>
          <div className="card">
            <h2>Run Status</h2>
            <div className="grid">
              <div>
                <label>Status</label>
                <div className=${`pill ${statusApi.data.status === "running" ? "success" : ""}`}>${statusApi.data.status}</div>
              </div>
              <div>
                <label>Last Started</label>
                <div>${formatDate(statusApi.data.startedAt)}</div>
              </div>
              <div>
                <label>Last Finished</label>
                <div>${formatDate(statusApi.data.finishedAt)}</div>
              </div>
              <div>
                <label>Next Run</label>
                <div>${formatDate(statusApi.data.nextRun)}</div>
              </div>
            </div>
          </div>
        </>
      `;
    }

    if (view === "sonarr") {
      return html`
        <>
          <div className="card">
            <h2>Sonarr Connection</h2>
            <div className="grid">
              <div>
                <label>Sonarr URL</label>
                <input value=${sonarrApi.data?.Sonarr?.Url || ""} onInput=${handleInput(sonarrApi.setData, "Sonarr.Url")} />
              </div>
              <div>
                <label>Sonarr API Key</label>
                <input value=${sonarrApi.data?.Sonarr?.ApiKey || ""} onInput=${handleInput(sonarrApi.setData, "Sonarr.ApiKey")} />
              </div>
            </div>
          </div>
          ${sets.map((set, index) => html`
            <div className="card" key=${`set-${index}`}>
              <h2>Set ${index + 1}</h2>
              <div className="grid">
                <div>
                  <label>Set Name (Media Type)</label>
                  <input value=${set["Media Type"] || ""} onInput=${handleInput(sonarrApi.setData, `Sets.${index}.Media Type`)} />
                </div>
                <div>
                  <label>Incomplete Profile Name</label>
                  <select value=${set["Incomplete Profile Name"] || ""} onInput=${handleInput(sonarrApi.setData, `Sets.${index}.Incomplete Profile Name`)}>
                    <option value="">Select a profile</option>
                    ${sonarrProfiles.map((profile) => html`<option key=${profile} value=${profile}>${profile}</option>`)}
                  </select>
                </div>
                <div>
                  <label>Incomplete Root Folder</label>
                  <select value=${set["Incomplete Root Folder"] || ""} onInput=${handleInput(sonarrApi.setData, `Sets.${index}.Incomplete Root Folder`)}>
                    <option value="">Select a root</option>
                    ${sonarrRoots.map((root) => html`<option key=${root} value=${root}>${root}</option>`)}
                  </select>
                </div>
                <div>
                  <label>Complete Profile Name</label>
                  <select value=${set["Complete Profile Name"] || ""} onInput=${handleInput(sonarrApi.setData, `Sets.${index}.Complete Profile Name`)}>
                    <option value="">Select a profile</option>
                    ${sonarrProfiles.map((profile) => html`<option key=${profile} value=${profile}>${profile}</option>`)}
                  </select>
                </div>
                <div>
                  <label>Complete Root Folder</label>
                  <select value=${set["Complete Root Folder"] || ""} onInput=${handleInput(sonarrApi.setData, `Sets.${index}.Complete Root Folder`)}>
                    <option value="">Select a root</option>
                    ${sonarrRoots.map((root) => html`<option key=${root} value=${root}>${root}</option>`)}
                  </select>
                </div>
              </div>
            </div>
          `)}
          <div className="actions">
            <button className="ghost" onClick=${addSet}>+ Add Set</button>
            <button className="primary" onClick=${() => saveSettings("/api/settings/sonarr", sonarrApi.data, "Sonarr settings")}>Save Sonarr Settings</button>
          </div>
        </>
      `;
    }

    if (view === "radarr") {
      return html`
        <>
          <div className="card">
            <h2>Radarr Connection</h2>
            <div className="grid">
              <div>
                <label>Radarr URL</label>
                <input value=${radarrApi.data?.Radarr?.Url || ""} onInput=${handleInput(radarrApi.setData, "Radarr.Url")} />
              </div>
              <div>
                <label>Radarr API Key</label>
                <input value=${radarrApi.data?.Radarr?.ApiKey || ""} onInput=${handleInput(radarrApi.setData, "Radarr.ApiKey")} />
              </div>
            </div>
          </div>
          <div className="card">
            <h2>Profile → Root Folder Mappings</h2>
            <p>Choose the correct root folder for each Radarr quality profile.</p>
            ${radarrProfiles.map((profile) => html`
              <div className="grid" style=${{ marginBottom: "12px" }} key=${profile}>
                <div>
                  <label>Profile Name</label>
                  <input value=${profile} disabled />
                </div>
                <div>
                  <label>Root Folder</label>
                  <select
                    value=${radarrMappings[profile] || ""}
                    onInput=${handleInput(radarrApi.setData, `FilmEngine.ProfileRootMappings.${profile}`)}
                  >
                    <option value="">Select a root</option>
                    ${radarrRoots.map((root) => html`<option key=${root} value=${root}>${root}</option>`)}
                  </select>
                </div>
              </div>
            `)}
          </div>
          <div className="actions">
            <button className="primary" onClick=${() => saveSettings("/api/settings/radarr", radarrApi.data, "Radarr settings")}>Save Radarr Settings</button>
          </div>
        </>
      `;
    }

    if (view === "shared") {
      return html`
        <div className="card">
          <h2>Shared Settings</h2>
          <p>These settings apply to both Sonarr and Radarr. Update them here and then save.</p>
          <div className="grid">
            <div>
              <label>Log File Name</label>
              <input value=${sharedLogging.LogFileName || "CompleteARR.log"} onInput=${handleInput(sonarrApi.setData, "Logging.LogFileName")} />
            </div>
            <div>
              <label>Minimum Log Level</label>
              <select value=${sharedLogging.MinLevel || "Debug"} onInput=${handleInput(sonarrApi.setData, "Logging.MinLevel")}>
                ${["Debug", "Info", "Warning", "Error", "Success"].map((level) => html`<option key=${level} value=${level}>${level}</option>`)}
              </select>
            </div>
            <div>
              <label>Throttle (ms)</label>
              <input type="number" value=${sharedLogging.ThrottleMs ?? 200} onInput=${handleInput(sonarrApi.setData, "Logging.ThrottleMs")} />
            </div>
          </div>
          <div className="actions">
            <button
              className="primary"
              onClick=${() => Promise.all([
                saveSettings("/api/settings/sonarr", sonarrApi.data, "Shared settings"),
                saveSettings("/api/settings/radarr", radarrApi.data, "Shared settings")
              ])}
            >
              Save Shared Settings
            </button>
          </div>
        </div>
      `;
    }

    return html`
      <div className="card">
        <h2>About CompleteARR</h2>
        <textarea readOnly value=${aboutApi.data?.content || "README not loaded."}></textarea>
      </div>
    `;
  }, [
    view,
    statusApi.data,
    sonarrApi.data,
    radarrApi.data,
    sonarrOptionsApi.data,
    radarrOptionsApi.data,
    sharedLogging,
    radarrMappings
  ]);

  return html`
    <>
      <header>
        <h1>CompleteARR Control Center</h1>
        <nav>
          ${NAV_ITEMS.map((item) => html`
            <button key=${item.key} className=${view === item.key ? "active" : ""} onClick=${() => setView(item.key)}>
              ${item.label}
            </button>
          `)}
        </nav>
      </header>
      <main>
        ${message && html`<div className="card"><p className="success">${message}</p></div>`}
        <h2>${NAV_ITEMS.find((item) => item.key === view)?.label}</h2>
        ${content}
      </main>
    </>
  `;
}

ReactDOM.createRoot(document.getElementById("app")).render(html`<${App} />`);