$cfg = Get-Content -Raw "/app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml" | ConvertFrom-Yaml
$cfg.Behavior.MoveVerification.MoveVerifyEnabled = $false
$cfg.Behavior.MoveVerification.MoveVerifyRetries = 3
$cfg | ConvertTo-Yaml -LineWidth 120 | Set-Content "/app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml"
Write-Host "Updated settings:"
Get-Content "/app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml" | Select-Object -First 10
