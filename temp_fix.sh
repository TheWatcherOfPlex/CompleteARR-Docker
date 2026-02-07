#!/usr/bin/env bash
# Disable MoveVerifyEnabled in SONARR settings
sed -i 's/MoveVerifyEnabled: true/MoveVerifyEnabled: false/g' /app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml

# Reduce retries from 10 to 3
sed -i 's/MoveVerifyRetries: 10/MoveVerifyRetries: 3/g' /app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml

echo "Updated SONARR settings:"
grep -A2 "MoveVerification:" /app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml
