# CompleteARR Docker

This container runs CompleteARR on a schedule (default: once per hour) behind gluetun.

## Container Behavior
- Runs `CompleteARR_Launch_All_Scripts.ps1` once per loop.
- Sleeps for `RUN_INTERVAL_SECONDS` (default `3600`).

## Required Volumes
Mount your settings and logs so they persist:

```
/srv/docker/CompleteARR/Settings:/app/CompleteARR_Settings
/srv/docker/CompleteARR/Logs:/app/CompleteARR_Logs
/mnt/win_data/Data:/data
```

## Environment
```
TZ=America/Chicago
RUN_INTERVAL_SECONDS=3600
```

## Build (on server)
```
git clone https://github.com/TheWatcherOfPlex/CompleteARR-Docker /srv/compose/CompleteARR-Docker
cd /srv/compose/CompleteARR-Docker
docker build -t completearr:latest .
```

## Settings bootstrap
```
mkdir -p /srv/docker/CompleteARR/Settings /srv/docker/CompleteARR/Logs
cp /srv/compose/CompleteARR-Docker/CompleteARR_Settings/*.example.yml /srv/docker/CompleteARR/Settings/
```

Then edit `/srv/docker/CompleteARR/Settings/CompleteARR_SONARR_Settings.example.yml`
and `/srv/docker/CompleteARR/Settings/CompleteARR_RADARR_Settings.example.yml` to match your environment.

## Start via stack
```
cd /srv/compose
docker-compose -f stack.yml up -d
```

## View logs
```
docker logs -f completearr
```