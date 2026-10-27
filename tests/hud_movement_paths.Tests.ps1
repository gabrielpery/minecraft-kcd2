#Requires -Version 7.3
# Filesystem-only path checks; no game, renderer, network or process launch.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
$fixture=Join-Path $root ('runtime/evidence/hud-movement-path-tests-'+[Guid]::NewGuid().ToString('N'))
$project=Join-Path $fixture 'project'
$evidence=Join-Path $project 'runtime/evidence'
[void][IO.Directory]::CreateDirectory($evidence)
$existing=Join-Path $evidence 'existing [literal].json'
[IO.File]::WriteAllText($existing,'{}')
Check ((Resolve-HudMovementEvidencePath $existing $project) -ceq $existing) 'Existing literal file rejected'
$missing=Join-Path $evidence 'new [directory]/nested/output.json'
Check ((Resolve-HudMovementEvidencePath $missing $project) -ceq ([IO.Path]::GetFullPath($missing))) 'Missing output components rejected'
Check (-not [IO.Directory]::Exists((Split-Path -Parent $missing))) 'Resolution created a directory'
Check ((Resolve-HudMovementEvidencePath (Join-Path $evidence 'sub/../output.json') $project) -ceq (Join-Path $evidence 'output.json')) 'Normalized contained path rejected'
Reject {Resolve-HudMovementEvidencePath 'relative.json' $project} 'Relative path accepted'
Reject {Resolve-HudMovementEvidencePath $evidence $project} 'Evidence root itself accepted'
Reject {Resolve-HudMovementEvidencePath (Join-Path $evidence '../escape.json') $project} 'Traversal outside evidence accepted'
Reject {Resolve-HudMovementEvidencePath (Join-Path $project 'runtime/evidence-other/output.json') $project} 'Sibling prefix accepted'
Reject {Resolve-HudMovementEvidencePath (Join-Path $fixture 'elsewhere.json') $project} 'Unrelated absolute path accepted'
Reject {Resolve-HudMovementEvidencePath ($existing+[char]0) $project} 'Invalid path accepted as missing'
if($IsWindows){
    Check ((Resolve-HudMovementEvidencePath $existing.ToUpperInvariant() $project) -ceq $existing.ToUpperInvariant()) 'Windows case-insensitive containment changed'
    # Junctions need no symbolic-link privilege. Include leaf and ancestor links,
    # then make the target absent to exercise a dangling reparse point.
    $target=Join-Path $fixture 'junction-target'
    [void][IO.Directory]::CreateDirectory($target)
    $link=Join-Path $evidence 'linked'
    $null=New-Item -ItemType Junction -Path $link -Target $target
    Check (([IO.File]::GetAttributes($link) -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'Junction fixture was not a reparse point'
    Reject {Resolve-HudMovementEvidencePath $link $project} 'Leaf reparse point accepted'
    Reject {Resolve-HudMovementEvidencePath (Join-Path $link 'missing/child.json') $project} 'Linked ancestor of missing output accepted'
    $verifiedTarget=[IO.Path]::GetFullPath($target)
    if(-not $verifiedTarget.StartsWith($fixture+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid fixture deletion target'}
    # Delete only this verified empty target, leaving the junction intact.
    [IO.Directory]::Delete($verifiedTarget,$false)
    Check (-not [IO.Directory]::Exists($target)) 'Broken-link fixture target still exists'
    Check (([IO.File]::GetAttributes($link) -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'Dangling junction lost its reparse attribute'
    Reject {Resolve-HudMovementEvidencePath $link $project} 'Dangling leaf reparse point accepted'
    Reject {Resolve-HudMovementEvidencePath (Join-Path $link 'missing/child.json') $project} 'Dangling linked ancestor accepted'
    $projectLink=Join-Path $fixture 'linked-project'
    $null=New-Item -ItemType Junction -Path $projectLink -Target $project
    Reject {Resolve-HudMovementEvidencePath (Join-Path $projectLink 'runtime/evidence/output.json') $projectLink} 'Linked project root accepted'
}
# Inject attribute-read faults into a copy of the production function. This
# exercises its catches without changing user ACLs or filesystem permissions.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/HudGroundMovement.ps1'),[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'Production path helper has syntax errors'
$node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Resolve-HudMovementEvidencePath'},$true)
if(-not ('MineCome.Tests.PathAttributes' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.IO;
namespace MineCome.Tests {
 public static class PathAttributes {
  public static bool AccessDenied;
  public static FileAttributes GetAttributes(string path) {
   if(AccessDenied) throw new UnauthorizedAccessException("simulated attribute access denial");
   throw new IOException("simulated attribute read failure");
  }
 }
}
'@
}
$faultSource=$node.Extent.Text.Replace('Resolve-HudMovementEvidencePath','Resolve-HudMovementFaultPath').Replace('[IO.File]::GetAttributes','[MineCome.Tests.PathAttributes]::GetAttributes')
Check ($faultSource -cne $node.Extent.Text -and $faultSource.Contains('[MineCome.Tests.PathAttributes]::GetAttributes')) 'Attribute fault seam missing'
. ([scriptblock]::Create($faultSource))
[MineCome.Tests.PathAttributes]::AccessDenied=$true
Reject {Resolve-HudMovementFaultPath $existing $project} 'Access denied was treated as absent'
[MineCome.Tests.PathAttributes]::AccessDenied=$false
Reject {Resolve-HudMovementFaultPath $existing $project} 'Other I/O failure was treated as absent'
Write-Output "HUD_MOVEMENT_PATH_TESTS checks=$script:checks PASS game_calls=false"
