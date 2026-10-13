#requires -Version 5.1
# SPDX-License-Identifier: GPL-3.0-or-later
# Admission only: no game calls or input generation. The live controller must
# supply its existing run-bound, foreground-validated physical click records.
function New-MineComeAimedClickLedger([string]$Run) {
    if($Run -cnotmatch '^[0-9a-f]{32}$'){throw 'Aimed click run must be a UUID in N format.'}
    [pscustomobject]@{
        Run=$Run;Arena=$null;LastPermit=0L;LastInstalled=0L;LastClock=0L;LastClick=0L
        Failed=$false;Permits=[Collections.Generic.List[object]]::new()
    }
}
function Add-MineComeAimedPermitLine($State,[string]$Line) {
    if($State.Failed){throw 'Aimed click ledger is failed.'}
    if(-not $Line.Contains('AIM_PERMIT_READY')){return}
    try {
        if($Line.Length -gt 512 -or $Line -cnotmatch '^AIM_PERMIT_READY run=([0-9a-f]{32}) arena=([1-9][0-9]{0,15}) permit=([1-9][0-9]{0,15}) installed_utc_ms=([1-9][0-9]{0,18})$'){
            throw 'Malformed aimed permit acknowledgement.'
        }
        $run=$Matches[1];$arena=[long]::Parse($Matches[2]);$permit=[long]::Parse($Matches[3]);$installed=[long]::Parse($Matches[4])
        if($run -cne $State.Run -or $arena -gt 9007199254740991 -or $permit -gt 9007199254740991 -or
           ($null -ne $State.Arena -and $arena -ne $State.Arena) -or $permit -le $State.LastPermit -or $installed -lt $State.LastInstalled){
            throw 'Aimed permit run, arena, ordering or clock changed.'
        }
        $State.Arena=$arena;$State.LastPermit=$permit;$State.LastInstalled=$installed
        $State.Permits.Add([pscustomobject]@{arena=$arena;permit=$permit;installed_utc_ms=$installed;used=$false})
        while($State.Permits.Count -gt 16){$State.Permits.RemoveAt(0)}
    }catch{$State.Failed=$true;throw}
}
function Select-MineComeAimedClickPermit($State,$Click,[long]$NowUtcMs) {
    if($State.Failed){throw 'Aimed click ledger is failed.'}
    try {
        foreach($name in @('sequence','utc_ms','action')){
            if(($Click.$name -isnot [int] -and $Click.$name -isnot [long]) -or $Click.$name -le 0){throw 'Invalid physical click integer.'}
        }
        if($Click.sequence -ne $State.LastClick+1 -or $Click.sequence -gt 16 -or $Click.action -notin @(1,2)){
            throw 'Aimed click sequence or action invalid.'
        }
        if($NowUtcMs -le 0 -or $NowUtcMs -lt $State.LastClock -or $NowUtcMs -lt $State.LastInstalled){throw 'Aimed controller clock moved backwards.'}
        $State.LastClock=$NowUtcMs;$State.LastClick=$Click.sequence
        $reason=$null;$selected=$null
        if($Click.utc_ms -gt $NowUtcMs){$reason='future_edge'}
        elseif($NowUtcMs-$Click.utc_ms -gt 250){$reason='stale_edge'}
        else {
            # Read-after-click is permitted; install-after-click is not. Keep the
            # original acknowledged permit rather than fetching a replacement
            # when a later Lua/HTTP operation completes.
            for($i=$State.Permits.Count-1;$i -ge 0;$i--){
                $entry=$State.Permits[$i]
                if(-not $entry.used -and $entry.installed_utc_ms -lt $Click.utc_ms -and $NowUtcMs-$entry.installed_utc_ms -le 350){
                    $selected=$entry;break
                }
            }
            if($null -eq $selected){$reason='no_preclick_permit'}
        }
        if($null -eq $selected){return [pscustomobject]@{accepted=$false;reason=$reason;command=$null}}
        # Spend before dispatch, including failed or ambiguous HTTP dispatch.
        $selected.used=$true
        $arena=$selected.arena.ToString([Globalization.CultureInfo]::InvariantCulture)
        $permit=$selected.permit.ToString([Globalization.CultureInfo]::InvariantCulture)
        $sequence=$Click.sequence.ToString([Globalization.CultureInfo]::InvariantCulture)
        [pscustomobject]@{
            accepted=$true;reason=$null;run=$State.Run;arena=$arena;permit=$permit
            sequence=$Click.sequence;action=$Click.action;edge_utc_ms=$Click.utc_ms;installed_utc_ms=$selected.installed_utc_ms
            command=("#MineCome.AimedIntent('{0}','{1}','{2}','{3}',{4})" -f $State.Run,$arena,$permit,$sequence,$Click.action)
        }
    }catch{$State.Failed=$true;throw}
}
