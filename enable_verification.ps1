$cfg = Get-Content -Raw "/app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml" | ConvertFrom-Yaml
$cfg.Behavior.MoveVerification.MoveVerifyEnabled = $true
$cfg.Behavior.MoveVerification.MoveVerifyRetries = 3
$cfg.Behavior.MoveVerification.MoveVerifyDelaySeconds = 5
$cfg.Behavior.MoveVerification.MoveVerifyBackoffSeconds = 2
$cfg.Behavior.MoveVerification.MoveVerifyReattemptMove = $false
$cfg | ConvertTo-Yaml | Set-Content "/app/CompleteARR_Settings/CompleteARR_SONARR_Settings.yml"
"Move verification re-enabled with safe settings:"
$cfg.Behavior.MoveVerification
