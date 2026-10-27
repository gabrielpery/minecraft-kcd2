#Requires -Version 7.3
# Incremental log cursor fixtures only. No game, input, console or process calls.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudWalkingReceipts.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
$encoding=[Text.UTF8Encoding]::new($false,$true)
$run='abcdef0123456789abcdef0123456789'
$other='0123456789abcdef0123456789abcdef'
$tags=@('MineComeMovementCapabilities','MineComeMovementContract','MineComeHudPhysicalView','MineComeMovementFollower')
$dir=Join-Path $root ('runtime/evidence/walking-receipts-pure-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
'SYNTHETIC ONLY; receipt parser fixtures, no game interactions.' | Set-Content (Join-Path $dir 'FIXTURE.txt')
function File([string]$Name,[byte[]]$Bytes){
    $p=Join-Path $dir $Name
    [IO.File]::WriteAllBytes($p,$Bytes)
    return $p
}
function Append([string]$Path,[byte[]]$Bytes){
    $f=[IO.FileStream]::new($Path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
    try{$f.Write($Bytes);$f.Flush($true)}finally{$f.Dispose()}
}
function Record([string]$Tag,[int]$Seq,[string]$Run=$run,[int]$Schema=1){
    '[{0}] {{"schema":{1},"run":"{2}","seq":{3}}}' -f $Tag,$Schema,$Run,$Seq
}
foreach($invalidRun in @('',('a'*31),('a'*33),$run.ToUpperInvariant(),'../x')){
    Reject {New-HudWalkingReceiptCursor 'unused' 0 $invalidRun} 'Invalid run cursor accepted'
}
Reject {New-HudWalkingReceiptCursor 'unused' -1 $run} 'Negative starting offset accepted'

# Read complete lines once, even when callers alternate requested tags.
$prefix=$encoding.GetBytes("historical prefix`n")
$p=File 'multiple.log' $prefix
$c=New-HudWalkingReceiptCursor $p $prefix.Length $run
foreach($tag in $tags){Append $p $encoding.GetBytes((Record $tag 1)+"`r`n")}
Append $p $encoding.GetBytes((Record $tags[2] 2 $other)+"`n"+(Record $tags[2] 3 $run.ToUpperInvariant())+"`n"+(Record $tags[2] 4 $run 2)+"`n")
Append $p $encoding.GetBytes("[UnrelatedTag] {bad json ignored}`nengine status only`n")
$first=@(Read-HudWalkingReceipts $c $tags[2])
Check ($first.Count -eq 1 -and $first[0].seq -eq 1) 'Tag/schema/exact run identity filtering'
Check ($c.Parsed -eq 7 -and $c.Position -eq (Get-Item -LiteralPath $p).Length) 'All complete known-tag records parsed exactly once'
foreach($tag in $tags){
    $values=@(Read-HudWalkingReceipts $c $tag)
    Check ($values.Count -eq 1 -and $values[0].run -ceq $run) 'Other tags remain independently cached'
}
$parsed=$c.Parsed;$position=$c.Position
for($i=0;$i -lt 12;$i++){
    $values=@(Read-HudWalkingReceipts $c $tags[2])
    Check ($c.Parsed -eq $parsed -and $c.Position -eq $position -and [Object]::ReferenceEquals($values[0],$first[0])) 'Unchanged read reparsed or replaced cached receipt'
}
Reject {Read-HudWalkingReceipts $c 'unknown'} 'Unknown requested tag accepted'
Append $p $encoding.GetBytes("timestamp prefix "+(Record $tags[2] 5)+"`n")
$values=@(Read-HudWalkingReceipts $c $tags[2])
Check ($values.Count -eq 2 -and $values[1].seq -eq 5 -and $c.Parsed -eq $parsed+1) 'Only appended record parsed and CryLog timestamp prefix accepted'

# A complete JSON object is still unavailable until its newline is on disk.
$partial=Record $tags[2] 6
Append $p $encoding.GetBytes($partial)
$before=$c.Position;$parsed=$c.Parsed
Check (@(Read-HudWalkingReceipts $c $tags[2]).Count -eq 2 -and $c.Position -eq $before -and $c.Parsed -eq $parsed) 'Unterminated JSON tail was consumed'
Append $p $encoding.GetBytes("`n")
Check (@(Read-HudWalkingReceipts $c $tags[2]).Count -eq 3 -and $c.Parsed -eq $parsed+1) 'Final newline did not release held record exactly once'

# UTF-8 may be split anywhere in the uncommitted tail. Decode complete lines only.
$utf8Prefix=$encoding.GetBytes((Record $tags[1] 1)+"`n"+'[MineComeHudPhysicalView] {"schema":1,"run":"'+$run+'","seq":2,"text":"')
$pUtf=File 'utf8.log' ($utf8Prefix+[byte[]]@(0xe2))
$utf=New-HudWalkingReceiptCursor $pUtf 0 $run
Check (@(Read-HudWalkingReceipts $utf $tags[1]).Count -eq 1 -and $utf.Parsed -eq 1) 'Valid complete prefix rejected due partial UTF-8 tail'
$partialPosition=$utf.Position
Append $pUtf ([byte[]]@(0x82))
Check (@(Read-HudWalkingReceipts $utf $tags[2]).Count -eq 0 -and $utf.Position -eq $partialPosition) 'Incomplete UTF-8 tail was decoded'
Append $pUtf (([byte[]]@(0xac))+$encoding.GetBytes('"}'+"`n"))
$euro=@(Read-HudWalkingReceipts $utf $tags[2])
Check ($euro.Count -eq 1 -and $euro[0].text -ceq [string][char]0x20ac -and $utf.Parsed -eq 2) 'Completed multibyte tail not parsed exactly once'
$badUtf=File 'invalid-utf8.log' ([byte[]]@(0xff,10))
$badUtfCursor=New-HudWalkingReceiptCursor $badUtf 0 $run
Reject {Read-HudWalkingReceipts $badUtfCursor $tags[2]} 'Invalid UTF-8 in complete record accepted'
Check ($badUtfCursor.Position -eq 0 -and $badUtfCursor.Parsed -eq 0) 'Invalid UTF-8 mutated consumed position/cache'

# Complete malformed known-tag payloads are fatal, including a missing closing }.
foreach($payload in @('{broken}','{broken','not-json','[]','null','{"schema":1}','{"run":"'+$run+'"}')){
    $pBad=File ('bad-'+[Guid]::NewGuid().ToString('N')+'.log') $encoding.GetBytes('['+$tags[2]+'] '+$payload+"`n")
    $bad=New-HudWalkingReceiptCursor $pBad 0 $run
    Reject {Read-HudWalkingReceipts $bad $tags[2]} 'Malformed complete known-tag payload skipped'
    Check ($bad.Position -eq 0 -and $bad.Parsed -eq 0 -and $bad.Receipts[$tags[2]].Count -eq 0) 'Malformed record mutated committed cache'
}
$pBatch=File 'batch-atomic.log' $encoding.GetBytes((Record $tags[2] 1)+"`n"+'['+$tags[3]+'] {broken'+"`n")
$batch=New-HudWalkingReceiptCursor $pBatch 0 $run
for($i=0;$i -lt 2;$i++){
    Reject {Read-HudWalkingReceipts $batch $tags[2]} 'Mixed valid/malformed batch was accepted'
    Check ($batch.Position -eq 0 -and $batch.Parsed -eq 0 -and $batch.Receipts[$tags[2]].Count -eq 0) 'Failed batch partially committed or duplicated receipts on retry'
}

# Track the entire observed tail, not only consumed position, to reject truncation.
$pCut=File 'truncated.log' $encoding.GetBytes((Record $tags[2] 1)+"`npartial tail")
$cut=New-HudWalkingReceiptCursor $pCut 0 $run
$null=Read-HudWalkingReceipts $cut $tags[2]
$f=[IO.File]::OpenWrite($pCut)
try{$f.SetLength($cut.Position)}finally{$f.Dispose()}
Reject {Read-HudWalkingReceipts $cut $tags[2]} 'Truncated previously observed incomplete tail accepted'
$pOffset=File 'short.log' $encoding.GetBytes('short')
$offset=New-HudWalkingReceiptCursor $pOffset 6 $run
Reject {Read-HudWalkingReceipts $offset $tags[2]} 'Starting offset beyond file accepted'

# The bound is the new extent after the starting offset, not total log length.
$pBound=File 'extent.log' ([byte[]]::new(16))
$f=[IO.File]::OpenWrite($pBound)
try{$f.SetLength(16+8388608);$f.Position=$f.Length-1;$f.WriteByte(10)}finally{$f.Dispose()}
$bound=New-HudWalkingReceiptCursor $pBound 16 $run
Check (@(Read-HudWalkingReceipts $bound $tags[2]).Count -eq 0 -and $bound.Position -eq 16+8388608) 'Exact8MiB new extent rejected'
Append $pBound ([byte[]]@(10))
Reject {Read-HudWalkingReceipts $bound $tags[2]} 'Extent beyond8MiB accepted'

# The camera worker can retain a read handle, preserving all parser/extent rules.
$pHeld=File 'held.log' $encoding.GetBytes((Record $tags[2] 1)+"`n"+(Record $tags[2] 2))
$held=New-HudWalkingReceiptCursor $pHeld 0 $run -KeepOpen
Check ($held.KeepOpen -and $null -eq $held.Stream -and -not $held.Closed) 'Persistent cursor did not start unopened'
try{
    Check (@(Read-HudWalkingReceipts $held $tags[2]).Count -eq 1) 'Persistent cursor consumed an incomplete tail'
    $handle=$held.Stream;$heldPosition=$held.Position
    Append $pHeld $encoding.GetBytes("`n")
    $values=@(Read-HudWalkingReceipts $held $tags[2])
    Check ($values.Count -eq 2 -and $values[1].seq -eq 2 -and $held.Position -gt $heldPosition) 'Persistent handle did not observe append after its previous EOF'
    Check ([object]::ReferenceEquals($handle,$held.Stream)) 'Persistent read reopened the log'
    Append $pHeld $encoding.GetBytes((Record $tags[2] 3))
    $null=Read-HudWalkingReceipts $held $tags[2]
    # Rewrite an uncommitted tail in place, without changing the observed length.
    # A buffered old tail must not turn this malformed complete line into JSON.
    $f=[IO.FileStream]::new($pHeld,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
    try{$f.Position=$held.Position;$f.WriteByte([byte][char]'!');$f.Position=$f.Length;$f.WriteByte(10)}finally{$f.Dispose()}
    $values=@(Read-HudWalkingReceipts $held $tags[2])
    Check ($values.Count -eq 2 -and $held.Parsed -eq 2) 'Persistent read used stale buffered tail bytes'
    Append $pHeld $encoding.GetBytes('truncated partial tail')
    $null=Read-HudWalkingReceipts $held $tags[2]
    $f=[IO.FileStream]::new($pHeld,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
    try{$f.SetLength($held.Position)}finally{$f.Dispose()}
    Reject {Read-HudWalkingReceipts $held $tags[2]} 'Persistent handle accepted tail truncation'
}finally{Close-HudWalkingReceiptCursor $held}
Check ($held.Closed -and $null -eq $held.Stream -and -not $handle.CanRead) 'Closing retained cursor did not dispose its handle'
Close-HudWalkingReceiptCursor $held
Reject {Read-HudWalkingReceipts $held $tags[2]} 'Closed persistent cursor reopened'

$heldBatch=New-HudWalkingReceiptCursor $pBatch 0 $run -KeepOpen
try{
    Reject {Read-HudWalkingReceipts $heldBatch $tags[2]} 'Persistent cursor accepted malformed batch'
    Check ($heldBatch.Position -eq 0 -and $heldBatch.Parsed -eq 0 -and $heldBatch.Receipts[$tags[2]].Count -eq 0) 'Persistent malformed batch partially committed'
}finally{Close-HudWalkingReceiptCursor $heldBatch}
$heldBound=New-HudWalkingReceiptCursor $pBound 16 $run -KeepOpen
try{Reject {Read-HudWalkingReceipts $heldBound $tags[2]} 'Persistent cursor accepted extent beyond8MiB'}finally{Close-HudWalkingReceiptCursor $heldBound}
$heldOffset=New-HudWalkingReceiptCursor $pOffset 6 $run -KeepOpen
try{Reject {Read-HudWalkingReceipts $heldOffset $tags[2]} 'Persistent cursor accepted offset beyond current length'}finally{Close-HudWalkingReceiptCursor $heldOffset}

# File rotation remains permitted, but its replacement must never enter the
# pinned cursor. The camera's existing no-ack deadline will fail closed.
$pRotate=File 'rotating.log' $encoding.GetBytes((Record $tags[2] 1)+"`n")
$rotated=Join-Path $dir 'rotated-original.log'
$rotating=New-HudWalkingReceiptCursor $pRotate 0 $run -KeepOpen
try{
    $null=Read-HudWalkingReceipts $rotating $tags[2]
    [IO.File]::Move($pRotate,$rotated)
    [IO.File]::WriteAllText($pRotate,((Record $tags[2] 999)+"`n"),$encoding)
    $values=@(Read-HudWalkingReceipts $rotating $tags[2])
    Check ($values.Count -eq 1 -and $values[0].seq -eq 1) 'Rotated replacement entered retained receipt history'
    Append $rotated $encoding.GetBytes((Record $tags[2] 2)+"`n")
    $values=@(Read-HudWalkingReceipts $rotating $tags[2])
    Check ($values.Count -eq 2 -and $values[1].seq -eq 2) 'Retained cursor did not remain attached to its original file'
}finally{Close-HudWalkingReceiptCursor $rotating}
Close-HudWalkingReceiptCursor $c
Reject {Read-HudWalkingReceipts $c $tags[2]} 'Explicitly closed default cursor reopened'
Write-Output "HUD_WALKING_RECEIPTS_TESTS checks=$script:checks PASS"
