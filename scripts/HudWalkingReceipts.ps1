# Read each complete log record once. Partial tails stay on disk until their LF
# arrives; parsing old camera history must not consume the live view's lease.
function New-HudWalkingReceiptCursor([string]$Path,[long]$Offset,[string]$Run,[switch]$KeepOpen){
    if($Offset -lt 0 -or $Run -cnotmatch '^[0-9a-f]{32}$'){throw 'Invalid walking receipt cursor.'}
    $receipts=@{}
    foreach($tag in @('MineComeMovementCapabilities','MineComeMovementContract','MineComeHudPhysicalView','MineComeMovementFollower')){
        $receipts[$tag]=[Collections.Generic.List[object]]::new()
    }
    [pscustomobject]@{Path=$Path;Start=$Offset;Position=$Offset;ObservedLength=$Offset;Run=$Run;Receipts=$receipts;Parsed=0L;KeepOpen=[bool]$KeepOpen;Stream=$null;Closed=$false}
}
function Close-HudWalkingReceiptCursor($Cursor){
    # Idempotent, and closing never grants a later read permission to reopen.
    $Cursor.Closed=$true
    $stream=$Cursor.Stream;$Cursor.Stream=$null
    if($stream){$stream.Dispose()}
}
function Read-HudWalkingReceipts($Cursor,[string]$Tag){
    if($Cursor.Closed){throw 'Walking receipt cursor is closed.'}
    if(-not $Cursor.Receipts.ContainsKey($Tag)){throw 'Unknown walking receipt tag.'}
    $stream=$Cursor.Stream
    if(-not $stream){
        # Reopening an actively written Windows log is a measured latency cost.
        # KeepOpen pins its current file; log rotation cannot supply replacement
        # acknowledgements. ReadWrite/Delete sharing still permits game logging.
        # Disable read buffering so each poll sees current length and tail bytes.
        $stream=[IO.FileStream]::new($Cursor.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete),1,[IO.FileOptions]::None)
        if($Cursor.KeepOpen){$Cursor.Stream=$stream}
    }
    try{
        $length=$stream.Length
        if($length -lt $Cursor.ObservedLength -or $length-$Cursor.Start -gt 8388608){throw 'Walking log changed or exceeded the bounded8MiB probe extent.'}
        $Cursor.ObservedLength=$length
        $stream.Position=$Cursor.Position
        $bytes=[byte[]]::new([int]($length-$Cursor.Position));$read=0
        while($read -lt $bytes.Length){
            $received=$stream.Read($bytes,$read,$bytes.Length-$read)
            if($received -eq 0){throw 'Walking log was truncated during capture.'}
            $read+=$received
        }
        $lastLf=[Array]::LastIndexOf($bytes,[byte]10)
        if($lastLf -ge 0){
            # Decode only complete lines, including complete UTF-8 codepoints.
            $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes,0,$lastLf+1)
            $staged=[Collections.Generic.List[object]]::new();$parsed=0L
            foreach($match in [regex]::Matches($text,'\[(MineComeMovementCapabilities|MineComeMovementContract|MineComeHudPhysicalView|MineComeMovementFollower)\] ([^\r\n]*)\r?\n')){
                $receipt=$match.Groups[2].Value | ConvertFrom-Json
                if($receipt -isnot [pscustomobject] -or -not $receipt.PSObject.Properties['schema'] -or -not $receipt.PSObject.Properties['run']){
                    throw 'Invalid walking receipt object.'
                }
                $parsed++
                if($receipt.schema -eq 1 -and $receipt.run -ceq $Cursor.Run){
                    $staged.Add([pscustomobject]@{Tag=$match.Groups[1].Value;Receipt=$receipt})
                }
            }
            # A malformed later line must not leave earlier records half-committed.
            foreach($entry in $staged){$Cursor.Receipts[$entry.Tag].Add($entry.Receipt)}
            $Cursor.Parsed+=$parsed
            $Cursor.Position+=$lastLf+1
        }
    }finally{if(-not $Cursor.KeepOpen){$stream.Dispose()}}
    return $Cursor.Receipts[$Tag].ToArray()
}
