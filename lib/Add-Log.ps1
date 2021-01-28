function Add-Log {
	[cmdletbinding()]
	Param (
		[Parameter(Position = 0, Mandatory = $True)]
		[STRING]$Type,
  [Parameter(Position = 1, Mandatory = $True)]
  [Alias("Msg")]
  $Message,
  [Parameter(Position = 3, Mandatory = $false)]
  $logPath,
  [Parameter(Position = 4, Mandatory = $false)]
  [switch]$WhatIf )
 begin {
  $date = Get-Date -Format u
  $type = "[$($type.toUpper())]"
  $testString = if ($WhatIf) { "[WhatIf]," }
 }
 process {
  foreach ($line in $Message) {
   $logMsg = "$testString$date,$type,$line"
   Write-Output $logMsg
   if (!$WhatIf -and $logPath) { "$date, $type, $line" | Out-File -FilePath $logPath -Append }
  }
 }
 end { }
}