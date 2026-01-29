![CompleteARR Logo](CompleteARR_Logos/CompleteARR_Logo_Header.png)

# CompleteARR - All or Nothing!

CompleteARR is an automated media librarian for **Sonarr** and **Radarr**. It keeps movies in the correct root folders and only promotes TV series to your “Complete” library once every episode is present. It’s designed to be **simple for new users** but **transparent for power users**, with clear logs and predictable rules.

---

## 🎪 At a Glance (Quick Overview)

### 🎬 For TV Shows (Sonarr)
- **Series Engine**: Moves completed shows from “Incomplete” to “Complete” quality profile/root folder sets and monitors special episodes.

### 🎥 For Movies (Radarr)
- **Film Engine**: Ensures movies stay in the correct root folder based on your quality profile → root folder mappings.

---

## 🚀 Getting Started (Windows / PowerShell)

### Prerequisites
- **Sonarr** (for series) and/or **Radarr** (for movies) installed and running
- **PowerShell 7.0** or newer

### Step 1: Open the Settings YMLs
Open `CompleteARR_SONARR_Settings.yml` & `CompleteARR_RADARR_Settings.yml` in the `CompleteARR_Settings` folder.

### Step 2: Fill in Your API/IP/Port
After opening the _Settings.yml files, fill in the API/IP/Port information, but don’t proceed further down the YML yet. **Save** the updated files.

### Step 3: Run the FetchInfo Tool
**Run `CompleteARR_FetchInfo_Launcher.ps1` before doing anything else!**

This tool will:
- Connect to your Sonarr and Radarr instances
- Show you all your quality profiles and root folders
- Generate a log file (`CompleteARR_Logs/`) with all the quality profile and root folder information you need to configure your _Settings.ymls

If the FetchInfo Tool cannot connect to Sonarr or Radarr then there is something wrong with the config and CompleteARR won’t work. Go back and check your IP/Port/API.

### Step 4: Configure Sets (Sonarr) & Mappings (Radarr)

#### 📺 For TV Shows (Sonarr) – Define Your “Sets”
A “Set” is a pair of **Incomplete** and **Complete** quality profiles & root folders. 
CompleteARR moves shows between them based on episode availability.

Open `CompleteARR_SONARR_Settings.yml` and fill out the `Sets:` section using the data from the FetchInfo log.

**Example configuration** for separating family and anime content can be found in `CompleteARR_SONARR_Settings.example.yml`.

**Notes:**
- `Media Type:` is for logging only. Use your Plex/Jellyfin/Emby library names to stay organized.
- Your Plex/Jellyfin/Emby series libraries should **only** include the **Complete** root folders.

**Pro Tip:**
- You could add incomplete folders to an "Incomplete" Plex/Jellyfin/Emby library if you still want to be able to access your incomplete content on Plex/Jellyfin/Emby, but don't want it mixed in with your complete series.

#### 🎬 For Movies (Radarr) – Define Profile‑to‑Root Mappings
When you match a Quality Profile to a Root Folder with CompleteARR, it automatically checks that your movies are in the right root folder. If they aren’t, CompleteARR moves them for you.

Open `CompleteARR_RADARR_Settings.yml` and fill out the `FilmEngine:` section using the data from the FetchInfo log.

**Format:** 
`Quality Profile: Root Folder`

**Example configuration** for separating family and anime content can be found in `CompleteARR_SONARR_Settings.example.yml`.

### Step 5: Run CompleteARR

**For Everything (Recommended):**
- Run `CompleteARR_Launch_All_Scripts.ps1`

**For Series Only:**
- Run `CompleteARR_SONARR_Launcher.ps1`

**For Movies Only:**
- Run `CompleteARR_RADARR_Launcher.ps1`

---

## Docker (Optional)

CompleteARR can run in Docker behind gluetun on a schedule. The container runs CompleteARR once per loop and sleeps for a configurable interval.

### Container behavior
- Runs `CompleteARR_Launch_All_Scripts.ps1` once per loop.
- Sleeps for `RUN_INTERVAL_SECONDS` (default `3600`, set to `1800` for 30 minutes).

### Required volumes
```
/srv/docker/CompleteARR/Settings:/app/CompleteARR_Settings
/srv/docker/CompleteARR/Logs:/app/CompleteARR_Logs
/mnt/win_data/Data:/data
```

### Environment
```
TZ=America/Chicago
RUN_INTERVAL_SECONDS=3600
```

### Build (on server)
```
git clone https://github.com/TheWatcherOfPlex/CompleteARR-Docker /srv/compose/CompleteARR-Docker
cd /srv/compose/CompleteARR-Docker
docker build -t completearr:latest .
```

### Settings bootstrap
```
mkdir -p /srv/docker/CompleteARR/Settings /srv/docker/CompleteARR/Logs
cp /srv/compose/CompleteARR-Docker/CompleteARR_Settings/*.example.yml /srv/docker/CompleteARR/Settings/
```

Then edit:
- `/srv/docker/CompleteARR/Settings/CompleteARR_SONARR_Settings.example.yml`
- `/srv/docker/CompleteARR/Settings/CompleteARR_RADARR_Settings.example.yml`

### Start via stack
```
cd /srv/compose
docker-compose -f stack.yml up -d
```

### View logs
```
docker logs -f completearr
```

## Tips for Success

1. **Use the FetchInfo tool** – It makes setup much easier!
2. **Set up your Plex/Jellyfin libraries** to only include the “Complete” folders
3. **Run CompleteARR regularly** (set up a scheduled task)
4. **Check the logs** in the `CompleteARR_Logs` folder if something doesn’t work
5. **Start with dry runs** by setting `DryRun: true` in your settings
7. **Set GraceDays** to change how long an episode can be considered released, before it counts against a shows completion status.

---

## 📁 Project Structure

### 🎬 Sonarr Scripts:
- **`CompleteARR_SONARR_Launcher.ps1`** – Runs the Sonarr Series Engine
- **`CompleteARR_SONARR_SeriesEngine.ps1`** – Manages show completion and special episode monitoring

### 🎥 Radarr Scripts:
- **`CompleteARR_RADARR_Launcher.ps1`** – Runs the Radarr Film Engine
- **`CompleteARR_RADARR_FilmEngine.ps1`** – Enforces quality profile‑to‑ root folder mappings

### 🛠️ Helper Tools:
- **`CompleteARR_FetchInfo.ps1`** – Essential setup tool that shows your current Quality Profiles and Root Folders, launch with **`CompleteARR_FetchInfo_Launcher.ps1`**
- **`CompleteARR_Launch_All_Scripts.ps1`** – Runs the full suite of CompleteARR tools

### ⚙️ Configuration:
- **`CompleteARR_SONARR_Settings.yml`** – Sonarr‑specific configuration
- **`CompleteARR_RADARR_Settings.yml`** – Radarr‑specific configuration

---

## 🔒 What CompleteARR Does NOT Do

- ❌ **Does NOT download content**
- ❌ **Does NOT search for torrents or NZBs**
- ❌ **Does NOT access the internet** except to talk to your Sonarr/Radarr
- ❌ **Does NOT modify your media files**, at most it can just move them between Root Folders.

---

## ⚖️ Legal & Responsible Use

**Important:** CompleteARR is designed to help you organize media you are legally allowed to have. 
This includes:

- Media you purchased and ripped yourself, where allowed by law
- Personal recordings where allowed by law
- Content you are explicitly licensed to download or own

**You are responsible for:**
- Ensuring your setup complies with your local laws
- Respecting terms of service for any services you use
- Only using CompleteARR with content you have rights to

By using CompleteARR, you agree to use it responsibly and legally.

---

## 🆘 Need Help?

1. **Check the logs** in the `CompleteARR_Logs` folder
2. **Review your settings files** – make sure everything matches your Sonarr/Radarr setup. Refer to the Settings.example.yml
3. **Use the FetchInfo tool** to verify your configuration
4. **Start with dry runs** by setting `DryRun: true` in your settings
5. **Verify your quality profiles and root folders** match what’s in your Sonarr/Radarr settings

---

## 🔍 Technical Breakdown (How the Engines Work)

This section explains the internal logic in plain English so you can trust exactly what CompleteARR is doing.

### 1) FetchInfo (setup helper)
`CompleteARR_FetchInfo.ps1` connects to Sonarr/Radarr and pulls:
- Your quality profiles
- Your root folders

It writes this to the log so you can **copy/paste the exact names** into your settings files without typos.

### 2) Sonarr Series Engine (TV Shows)
For each **Set** in your Sonarr settings:
1. It gathers all series tied to the “Incomplete” profile/root folder.
2. It checks episode availability, release dates, and **GraceDays** (how long an episode can be missing before a show is considered incomplete).
3. If every episode is present (or allowed by GraceDays), the show is **moved** to the “Complete” profile/root folder.
4. If a show becomes incomplete again (missing newly‑aired episodes), it can move back to the “Incomplete” set.

### 3) Radarr Film Engine (Movies)
For each **Quality Profile → Root Folder** mapping in your Radarr settings:
1. It checks every movie with that quality profile.
2. If the movie’s current root folder **does not match** the mapped root folder, it **moves the movie** to the correct folder.
3. It logs every change so you can audit what moved and why.

### 4) What it *doesn’t* touch
- It does **not** download or search for media.
- It only talks to Sonarr/Radarr via their APIs.
- It only moves items between **existing root folders** you specify.

---

![CompleteARR Logo](CompleteARR_Logos/CompleteARR_Logo_Square.png)

Thank you so much for using CompleteARR!

CompleteARR started off as a feature I wanted, and became its own little suite of tools, 
the first of which are included in this release with more to come in the near future. 

These tools are free and will always be free. 

If these tools have been helpful and you’d like to leave a tip,
please use the sponsor links on the main CompleteARR page.
Support is always appreciated, but never expected.
