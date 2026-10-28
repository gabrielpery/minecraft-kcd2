# Two explicit bounded walking sessions. Limits are chosen by the controller,
# never copied from an untrusted readiness, trace or native receipt.
function Get-HudWalkingSession([switch]$ExtendedWalking) {
    if($ExtendedWalking){
        return [pscustomobject]@{Name='extended';InputMs=15000;SourceMs=16000;DeadlineMs=18000;
            OrdinaryWrites=2047;Receipts=256;TraceBytes=262144;
            BeginFunction='BeginExtendedBufferedPhysicalMovementFollower';
            SourceKind='live_kcd_hud_physical_movement_extended'}
    }
    return [pscustomobject]@{Name='short';InputMs=5000;SourceMs=6000;DeadlineMs=8000;
        OrdinaryWrites=511;Receipts=128;TraceBytes=65536;
        BeginFunction='BeginBufferedPhysicalMovementFollower';SourceKind='live_kcd_hud_physical_movement'}
}
function Assert-HudWalkingSession($Value,[switch]$ExtendedWalking) {
    $field=$Value.PSObject.Properties['movement_session']
    if($Value -is [Collections.IDictionary] -and $Value.Contains('movement_session')){
        $field=[pscustomobject]@{Value=$Value['movement_session']}
    }
    # Original short receipts predate the marker. Absence never grants extension.
    if(-not $field -and -not $ExtendedWalking){return}
    $expected=if($ExtendedWalking){'extended'}else{'short'}
    if(-not $field -or $field.Value -isnot [string] -or $field.Value -cne $expected){
        throw 'Walking session does not match the explicitly selected controller profile.'
    }
}
