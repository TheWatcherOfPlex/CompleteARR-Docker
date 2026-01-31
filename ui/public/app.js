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

function Toggle({ label, description, value, onChange }) {
  return html`
    <div>
      <label>${label}</label>
      <div className="toggle">
        <label className="switch">
          <input type="checkbox" checked=${!!value} onChange=${(event) => onChange(event.target.checked)} />
          <span className="slider"></span>
        </label>
        <span>${value ? "Enabled" : "Disabled"}</span>
      </div>
      ${description ? html`<div className="help">${description}</div>` : ""}
    </div>
  `;
}

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

  const toggleValue = (setter, path) => () => {
    setter((prev) => {
      const next = JSON.parse(JSON.stringify(prev || {}));
      const keys = path.split(".");
      let cursor = next;
      keys.slice(0, -1).forEach((key) => {
        if (!cursor[key]) cursor[key] = {};
        cursor = cursor[key];
      });
      const lastKey = keys[keys.length - 1];
      cursor[lastKey] = !cursor[lastKey];
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
  const sonarrMoveVerify = sonarrApi.data?.Behavior?.MoveVerification || {};
  const radarrMoveVerify = radarrApi.data?.Behavior?.MoveVerification || {};

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
                <div className="help">Base URL for your Sonarr instance (no trailing slash).</div>
              </div>
              <div>
                <label>Sonarr API Key</label>
                <input value=${sonarrApi.data?.Sonarr?.ApiKey || ""} onInput=${handleInput(sonarrApi.setData, "Sonarr.ApiKey")} />
                <div className="help">Find this in Sonarr → Settings → General.</div>
              </div>
            </div>
          </div>
          <div className="card">
            <h2>Sonarr Behavior</h2>
            <div className="grid">
              ${Toggle({
                label: "Dry Run",
                description: "When enabled, no changes are sent to Sonarr. Use this to test safely.",
                value: sonarrApi.data?.Behavior?.DryRun,
                onChange: (val) => handleInput(sonarrApi.setData, "Behavior.DryRun")({ target: { value: val } })
              })}
              <div>
                <label>Grace Days</label>
                <input type="number" value=${sonarrApi.data?.Behavior?.GraceDays ?? 15} onInput=${handleInput(sonarrApi.setData, "Behavior.GraceDays")} />
                <div className="help">Days after air date before a show is considered incomplete.</div>
              </div>
              <div>
                <label>Preflight Seconds</label>
                <input type="number" value=${sonarrApi.data?.Behavior?.PreflightSeconds ?? 0} onInput=${handleInput(sonarrApi.setData, "Behavior.PreflightSeconds")} />
                <div className="help">Delay before starting work (useful for throttling on startup).</div>
              </div>
              <div>
                <label>Post Move Wait</label>
                <input type="number" value=${sonarrApi.data?.Behavior?.PostMoveWaitSeconds ?? 2} onInput=${handleInput(sonarrApi.setData, "Behavior.PostMoveWaitSeconds")} />
                <div className="help">Wait time after a move to let Sonarr settle.</div>
              </div>
              ${Toggle({
                label: "Monitor Non-Specials",
                description: "Always monitor seasons and episodes that are not specials.",
                value: sonarrApi.data?.Behavior?.MonitorNonSpecials,
                onChange: (val) => handleInput(sonarrApi.setData, "Behavior.MonitorNonSpecials")({ target: { value: val } })
              })}
              ${Toggle({
                label: "Unmonitor Specials When Incomplete",
                description: "When in an incomplete profile, specials will be unmonitored.",
                value: sonarrApi.data?.Behavior?.UnmonitorSpecialsWhenIncomplete,
                onChange: (val) => handleInput(sonarrApi.setData, "Behavior.UnmonitorSpecialsWhenIncomplete")({ target: { value: val } })
              })}
              ${Toggle({
                label: "Monitor Specials When Complete",
                description: "When in a complete profile, specials will be monitored.",
                value: sonarrApi.data?.Behavior?.MonitorSpecialsWhenComplete,
                onChange: (val) => handleInput(sonarrApi.setData, "Behavior.MonitorSpecialsWhenComplete")({ target: { value: val } })
              })}
              ${Toggle({
                label: "Specials Do Not Block Completion",
                description: "Ignore specials when deciding if a show is complete.",
                value: sonarrApi.data?.Behavior?.SpecialsDoNotBlockCompletion,
                onChange: (val) => handleInput(sonarrApi.setData, "Behavior.SpecialsDoNotBlockCompletion")({ target: { value: val } })
              })}
            </div>
          </div>
          <div className="card">
            <h2>Sonarr Move Verification</h2>
            <div className="grid">
              ${Toggle({
                label: "Enable Verification",
                description: "Verify move operations after Sonarr updates.",
                value: sonarrMoveVerify.MoveVerifyEnabled,
                onChange: (val) => handleInput(sonarrApi.setData, "Behavior.MoveVerification.MoveVerifyEnabled")({ target: { value: val } })
              })}
              <div>
                <label>Mode</label>
                <select value=${sonarrMoveVerify.MoveVerifyMode || "sonarr"} onInput=${handleInput(sonarrApi.setData, "Behavior.MoveVerification.MoveVerifyMode")}>
                  ${["sonarr", "filesystem", "both"].map((mode) => html`<option key=${mode} value=${mode}>${mode}</option>`)}
                </select>
              </div>
              <div>
                <label>Retries</label>
                <input type="number" value=${sonarrMoveVerify.MoveVerifyRetries ?? 3} onInput=${handleInput(sonarrApi.setData, "Behavior.MoveVerification.MoveVerifyRetries")} />
              </div>
              <div>
                <label>Delay (sec)</label>
                <input type="number" value=${sonarrMoveVerify.MoveVerifyDelaySeconds ?? 5} onInput=${handleInput(sonarrApi.setData, "Behavior.MoveVerification.MoveVerifyDelaySeconds")} />
              </div>
              <div>
                <label>Backoff (sec)</label>
                <input type="number" value=${sonarrMoveVerify.MoveVerifyBackoffSeconds ?? 2} onInput=${handleInput(sonarrApi.setData, "Behavior.MoveVerification.MoveVerifyBackoffSeconds")} />
              </div>
              ${Toggle({
                label: "Reattempt Move",
                description: "Retry the move if verification fails.",
                value: sonarrMoveVerify.MoveVerifyReattemptMove,
                onChange: (val) => handleInput(sonarrApi.setData, "Behavior.MoveVerification.MoveVerifyReattemptMove")({ target: { value: val } })
              })}
              ${Toggle({
                label: "Revert On Failure",
                description: "Revert to the original path if verification fails.",
                value: sonarrMoveVerify.MoveVerifyRevertOnFailure,
                onChange: (val) => handleInput(sonarrApi.setData, "Behavior.MoveVerification.MoveVerifyRevertOnFailure")({ target: { value: val } })
              })}
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
                <div className="help">Base URL for your Radarr instance (no trailing slash).</div>
              </div>
              <div>
                <label>Radarr API Key</label>
                <input value=${radarrApi.data?.Radarr?.ApiKey || ""} onInput=${handleInput(radarrApi.setData, "Radarr.ApiKey")} />
                <div className="help">Find this in Radarr → Settings → General.</div>
              </div>
            </div>
          </div>
          <div className="card">
            <h2>Radarr Behavior</h2>
            <div className="grid">
              ${Toggle({
                label: "Dry Run",
                description: "When enabled, no changes are sent to Radarr. Use this to test safely.",
                value: radarrApi.data?.Behavior?.DryRun,
                onChange: (val) => handleInput(radarrApi.setData, "Behavior.DryRun")({ target: { value: val } })
              })}
              <div>
                <label>Preflight Seconds</label>
                <input type="number" value=${radarrApi.data?.Behavior?.PreflightSeconds ?? 0} onInput=${handleInput(radarrApi.setData, "Behavior.PreflightSeconds")} />
                <div className="help">Delay before starting work (useful for throttling on startup).</div>
              </div>
              <div>
                <label>Post Move Wait</label>
                <input type="number" value=${radarrApi.data?.Behavior?.PostMoveWaitSeconds ?? 0} onInput=${handleInput(radarrApi.setData, "Behavior.PostMoveWaitSeconds")} />
                <div className="help">Wait time after a move to let Radarr settle.</div>
              </div>
            </div>
          </div>
          <div className="card">
            <h2>Radarr Move Verification</h2>
            <div className="grid">
              ${Toggle({
                label: "Enable Verification",
                description: "Verify move operations after Radarr updates.",
                value: radarrMoveVerify.MoveVerifyEnabled,
                onChange: (val) => handleInput(radarrApi.setData, "Behavior.MoveVerification.MoveVerifyEnabled")({ target: { value: val } })
              })}
              <div>
                <label>Mode</label>
                <select value=${radarrMoveVerify.MoveVerifyMode || "radarr"} onInput=${handleInput(radarrApi.setData, "Behavior.MoveVerification.MoveVerifyMode")}>
                  ${["radarr", "filesystem", "both"].map((mode) => html`<option key=${mode} value=${mode}>${mode}</option>`)}
                </select>
              </div>
              <div>
                <label>Retries</label>
                <input type="number" value=${radarrMoveVerify.MoveVerifyRetries ?? 3} onInput=${handleInput(radarrApi.setData, "Behavior.MoveVerification.MoveVerifyRetries")} />
              </div>
              <div>
                <label>Delay (sec)</label>
                <input type="number" value=${radarrMoveVerify.MoveVerifyDelaySeconds ?? 5} onInput=${handleInput(radarrApi.setData, "Behavior.MoveVerification.MoveVerifyDelaySeconds")} />
              </div>
              <div>
                <label>Backoff (sec)</label>
                <input type="number" value=${radarrMoveVerify.MoveVerifyBackoffSeconds ?? 2} onInput=${handleInput(radarrApi.setData, "Behavior.MoveVerification.MoveVerifyBackoffSeconds")} />
              </div>
              ${Toggle({
                label: "Reattempt Move",
                description: "Retry the move if verification fails.",
                value: radarrMoveVerify.MoveVerifyReattemptMove,
                onChange: (val) => handleInput(radarrApi.setData, "Behavior.MoveVerification.MoveVerifyReattemptMove")({ target: { value: val } })
              })}
              ${Toggle({
                label: "Revert On Failure",
                description: "Revert to the original path if verification fails.",
                value: radarrMoveVerify.MoveVerifyRevertOnFailure,
                onChange: (val) => handleInput(radarrApi.setData, "Behavior.MoveVerification.MoveVerifyRevertOnFailure")({ target: { value: val } })
              })}
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
              <div className="help">Base name for all log files (timestamps are appended).</div>
            </div>
            <div>
              <label>Minimum Log Level</label>
              <select value=${sharedLogging.MinLevel || "Debug"} onInput=${handleInput(sonarrApi.setData, "Logging.MinLevel")}>
                ${["Debug", "Info", "Warning", "Error", "Success"].map((level) => html`<option key=${level} value=${level}>${level}</option>`)}
              </select>
              <div className="help">Controls the verbosity of logging output.</div>
            </div>
            <div>
              <label>Throttle (ms)</label>
              <input type="number" value=${sharedLogging.ThrottleMs ?? 200} onInput=${handleInput(sonarrApi.setData, "Logging.ThrottleMs")} />
              <div className="help">Delay between API calls to avoid overwhelming Sonarr/Radarr.</div>
            </div>
            ${Toggle({
              label: "Log to Console",
              description: "Write colored logs to the console output.",
              value: sharedLogging.LogToConsole,
              onChange: (val) => handleInput(sonarrApi.setData, "Logging.LogToConsole")({ target: { value: val } })
            })}
            ${Toggle({
              label: "Log to File",
              description: "Write detailed logs to the CompleteARR_Logs folder.",
              value: sharedLogging.LogToFile,
              onChange: (val) => handleInput(sonarrApi.setData, "Logging.LogToFile")({ target: { value: val } })
            })}
            ${Toggle({
              label: "Use Colors",
              description: "Enable colored log output in the console.",
              value: sharedLogging.UseColors,
              onChange: (val) => handleInput(sonarrApi.setData, "Logging.UseColors")({ target: { value: val } })
            })}
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