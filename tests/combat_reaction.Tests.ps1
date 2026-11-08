#Requires -Version 7.3
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$source=Join-Path $PSScriptRoot '../scripts/Test-KcdCombatReaction.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Test-MineComeReactionFraction'},$true)
if(-not $fn){throw 'Missing reaction fraction admission function.'}
# Extract only the pure predicate; this test must never dispatch a game command.
. ([scriptblock]::Create($fn.Extent.Text))
foreach($native in @(.35,.34999999404,.350000023842)){
 if(-not (Test-MineComeReactionFraction $native .35)){throw "Native float rejected: $native"}
}
foreach($bad in @($null,'0.35',$true,[double]::NaN,[double]::PositiveInfinity,.1,.350002,.349998)){
 if(Test-MineComeReactionFraction $bad .35){throw "Invalid or changed fraction admitted: $bad"}
}
if(Test-MineComeReactionFraction .35 ([double]::NaN)){throw 'Non-finite requested fraction admitted.'}
Write-Output 'PASS combat reaction native-float receipt tolerance (no game calls)'
