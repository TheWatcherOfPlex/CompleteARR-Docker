$cfg = Get-Content -Raw "/app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml" | ConvertFrom-Yaml
$cfg.Behavior.MoveVerification.MoveVerifyEnabled = $false
$cfg.Behavior.MoveVerification.MoveVerifyRetries = 3
$cfg | ConvertTo-Yaml | Set-Content "/app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml"
"Done. New MoveVerification settings:"
$cfg.Behavior.MoveVerification
