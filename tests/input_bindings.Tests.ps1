#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/InputBindings.ps1')
$checks=0
function Assert-InputBinding($Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
$default=Get-MineComeInputBindings
Assert-InputBinding ($default.Argument -ceq 'W,S,A,D,SPACE,LSHIFT') 'Default canonical binding order'
$arrows=Get-MineComeInputBindings 'UP,DOWN,LEFT,RIGHT,SPACE,RCTRL'
Assert-InputBinding ($arrows.Forward -ceq 'UP' -and $arrows.Sprint -ceq 'RCTRL') 'Custom semantic order'
foreach($bad in @('', 'W,S,A,D,SPACE','W,S,A,D,SPACE,LSHIFT,E','W,S,A,D,SPACE,W',
    'w,S,A,D,SPACE,LSHIFT',' W,S,A,D,SPACE,LSHIFT','W,S,A,D,SPACE,LSHIFT ',
    'W,S,A,D,,LSHIFT','W,S,A,D,SPACE,F8','W,S,A,D,SPACE,ESC','W,S,A,D,SPACE,CTRL',
    'W,S,A,D,SPACE,0','W,S,A,D,SPACE,ENTER',('X'*65))) {
    $failed=$false;try{Get-MineComeInputBindings $bad|Out-Null}catch{$failed=$true}
    Assert-InputBinding $failed ('Invalid binding accepted: '+$bad)
}
Write-Output "INPUT_BINDINGS_POWERSHELL_PASS checks=$checks no capture/game calls"
