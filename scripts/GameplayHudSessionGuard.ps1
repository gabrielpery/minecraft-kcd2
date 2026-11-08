#Requires -Version 7.3
# Read-only early rejection of the sustained compositor's consumed one-arm
# process. Native run receipt + saved exact process-start identity are both
# required; an old log, reused PID, or merely written arm proves nothing alone.
function Read-GameplayHudSessionEvidence([string]$Path,[long]$Maximum){
    if(-not [IO.File]::Exists($Path)){return $null}
    if((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint){return $null}
    $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        if($file.Length -lt 1 -or $file.Length -gt $Maximum){throw 'Gameplay HUD session evidence exceeds its read bound.'}
        $reader=[IO.StreamReader]::new($file,[Text.UTF8Encoding]::new($false,$true),$false)
        try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
    }finally{$file.Dispose()}
}
function Get-GameplayHudConsumedRun($Context,[string]$ToolsBin){
    $log=Read-GameplayHudSessionEvidence (Join-Path $ToolsBin 'ReShade.log') 64MB
    if(-not $log){return $null}
    $evidence=Join-Path $Context.ProjectRoot 'runtime/evidence'
    if(-not [IO.Directory]::Exists($evidence)){return $null}
    $start=$Context.GameStartedUtc.ToFileTimeUtc().ToString()
    $runs=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($match in [regex]::Matches($log,'\[MineComeHudInput\] (\{[^\r\n]*\})\r?\n')){
        if($match.Groups[1].Length -gt 4096){continue}
        try{$r=$match.Groups[1].Value|ConvertFrom-Json -Depth 5}catch{continue}
        if(-not $r.PSObject.Properties['schema'] -or -not $r.PSObject.Properties['event'] -or -not $r.PSObject.Properties['run'] -or
           $r.schema -ne 1 -or $r.run -isnot [string] -or $r.run -cnotmatch '^[a-f0-9]{32}$'){continue}
        if($r.event -ceq 'session_end' -or ($r.event -ceq 'arm' -and $r.PSObject.Properties['result'] -and $r.result -ceq 'accepted')){[void]$runs.Add($r.run)}
    }
    foreach($run in $runs){
        foreach($directory in [IO.Directory]::EnumerateDirectories($evidence,"gameplay-kcd-*-$run",[IO.SearchOption]::TopDirectoryOnly)){
            if((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            $arm=Read-GameplayHudSessionEvidence (Join-Path $directory 'arm.ini') 4096
            if(-not $arm){continue}
            $values=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);$valid=$true;$header=$false
            foreach($line in ($arm -split '\r?\n')){
                if($line -ceq ''){continue}
                if($line -ceq '[HudStream]' -and -not $header){$header=$true;continue}
                if($line -cnotmatch '^(Schema|Run|TargetPid|TargetStart|ProducerPid|ProducerStart|ExpiresUtcMs)=([^\r\n]+)$' -or -not $values.TryAdd($Matches[1],$Matches[2])){$valid=$false;break}
            }
            if($valid -and $header -and $values.Count -eq 7 -and $values['Schema'] -ceq '3' -and $values['Run'] -ceq $run -and
               $values['TargetPid'] -ceq ([string]$Context.GamePid) -and $values['TargetStart'] -ceq $start){return $run}
        }
    }
    return $null
}
function Assert-GameplayHudSessionUnused($Context,[string]$ToolsBin){
    $consumed=Get-GameplayHudConsumedRun $Context $ToolsBin
    if($consumed){throw "KCD2 process $($Context.GamePid) already consumed its gameplay HUD session ($consumed). Close and restart KCD2 normally before starting another gameplay session. No Minecraft client was launched."}
}
