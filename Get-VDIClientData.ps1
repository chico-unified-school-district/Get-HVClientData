<#
.SYNOPSIS
 
.DESCRIPTION
 
.PARAMETER Server
 A vCenter server name
.PARAMETER Credential
.PARAMETER WhatIf
 Switch to turn testing mode on or off.
.EXAMPLE
.INPUTS

.OUTPUTS
 Log messages are output to the console.
.NOTES
Thanks, dugas! https://stackoverflow.com/questions/33503283/replace-null-value-in-powershell-output
and https://www.sqlservertutorial.net/sql-server-basics/sql-server-insert-multiple-rows/
#>

[cmdletbinding()]
param (
 # Target VIServer
 # [Parameter(Mandatory = $True)]
 # [Alias('vcserver')]
 # [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 # [string]$VCenterServer,
 # # VIServer Credentials with Proper Permission Levels
 # [Parameter(Mandatory = $True)]
 # [Alias('vccred')]
 # [System.Management.Automation.PSCredential]$VCenterCredential,
 [Parameter(Mandatory = $True)]
 [Alias('vdiserver')]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$VDIConnectionServer,
 # VIServer Credentials with Proper Permission Levels
 [Parameter(Mandatory = $True)]
 [Alias('vdicred')]
 [System.Management.Automation.PSCredential]$VDICredential,
 [Parameter(Mandatory = $True)]
 [Alias('dbserver')]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$SQLServer,
 [Parameter(Mandatory = $True)]
 [string]$Database,
 [Parameter(Mandatory = $True)]
 [string]$TableName,
 # VIServer Credentials with Proper Permission Levels
 [Parameter(Mandatory = $True)]
 [Alias('dbcred')]
 [System.Management.Automation.PSCredential]$SQLCredential,
 [Alias('wi')]
 [switch]$WhatIf
)
# $env:psmodulepath = 'C:\Program Files\WindowsPowerShell\Modules; C:\Windows\system32\config\systemprofile\Documents\WindowsPowerShell\Modules; C:\Program Files (x86)\WindowsPowerShell\Modules; C:\Windows\system32\WindowsPowerShell\v1.0\Modules; C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules'

# Import Functions
. .\lib\Add-Log.ps1
. .\lib\Run-SQLCMD.ps1
. .\lib\Set-PSCred.ps1

if (Get-Module -name VMware.VimAutomation.HorizonView){
 try {Import-Module VMware.VimAutomation.HorizonView }
 catch { EXIT }
} else {
 Add-Log error 'VMware.VimAutomation.HorizonView module not available. Please install the module and check env:psmodulepath. Exiting'
 EXIT
}


function checkHVServer ($hvServer, [System.Management.Automation.PSCredential]$hvCred) {
 if (!$global:DefaultHVServers){
  Write-Verbose ('Connecting to hvServer {0} as {1}' -f $hvServer, $hvCred.Username)
  $count = 60
  do {
   "Attempting to connec to hvServer..."
   Connect-HVServer -Server $hvServer -Cred $hvCred
   Start-Sleep 10
   $count--
  }
  until ($global:DefaultHVServers -or ($count -eq 0))
 } else {
  Write-Verbose "HV Server $VDIConnectionServer already connected."
 }
}

$columnNames = 'UserName,AgentVersion,ClientAddress,ClientLocationID,ClientName,ClientType,ClientVersion,DesktopName,DesktopPoolCN,DesktopSource,DesktopType,MachineOrRDSServerDNS,SecurityGatewayAddress,SecurityGatewayDNS,SecurityGatewayLocation'
$propertyNames = 'UserName','AgentVersion','ClientAddress','ClientLocationID','ClientName','ClientType','ClientVersion','DesktopName','DesktopPoolCN','DesktopSource','DesktopType','MachineOrRDSServerDNS','SecurityGatewayAddress','SecurityGatewayDNS','SecurityGatewayLocation'

function formatClientDataSQL ($table,$hvNamesdata) {
 # Replace empty data with 'NULL' convert to CSV.
 $global:i = 0
 $convertedSQLValues = $hvNamesdata | Select-Object $propertyNames | ForEach-Object {
  foreach ($p in $_.PSObject.Properties) {
   if ( $null -eq $p.Value ) {
    $p.Value = 'NULL'
   }
  }
  $_
 } | ConvertTo-Csv -NoTypeInformation
 # Remove Table Headers index (Count-1), add () around VALUES, and replace double quotes with single quotes
 $formattedSQLValues = $convertedSQLValues.ForEach(
  {
   $info = $_
   if ($i -eq 0) { } # Skip the CSV headers
   elseif ($i -eq ($convertedSQLValues.count-1) ) { "($info)" } # No comma for the last entry
   else { "($info),`n" } # commas for all other entries
   $global:i++
  }
 ) -Replace("`"","'")
 Write-Output "INSERT INTO $table`n($columnNames)`nVALUES`n$formattedSQLValues;"
}

checkHVServer -hvServer $VDIConnectionServer -hvCred $VDICredential
$hvClientDataOld = (Get-HVLocalSession).namesdata
# $hvClientDataOld

$sqlParams = @{
 Server        = $SQLServer
 Database      = $Database
 Credential    = $SQLCredential
}

if ($hvClientDataOld){
 Add-Log sql ('Adding initial data to {0} {1} {2} as {3}' -f $SQLServer, $Database, $TableName, $SQLCredential.Username)
 $initialInsertSQL = formatClientDataSQL -table $TableName -hvNamesdata $hvClientDataOld
 # Write initial connection results
 Run-SQLCMD @sqlParams -SQLCMD $initialInsertSQL -Whatif:$WhatIf
}

$endTime = Get-Date "feb 1 2021 9:00am" # SHould run 23.99ish hours a day.
do {
 Write-Verbose "Running Loop"
 # Check connection server session
 checkHVServer -hvServer $VDIConnectionServer -hvCred $VDICredential

 # Get latest hv data from View Connection Server
 $hvClientDataNew = $null
 $hvClientDataNew = (Get-HVLocalSession).namesdata

 $compareObjParams = @{
  ReferenceObject  = $hvClientDataOld
  DifferenceObject = $hvClientDataNew
  Property         = $propertyNames
 }
 $newHVEntries = Compare-Object @compareObjParams | Where-Object {$_.SideIndicator -eq '=>'} | Select-Object $propertyNames
 # $newHVEntries

 # Write changes
 if ($newHVEntries){
  Write-Verbose "Formatting new entries"
  $latestInsertSQL = formatClientDataSQL -table $TableName -hvNamesdata $newHVEntries
  $latestInsertSQL
  # Read-Host "Wait and check the sql...."
  Write-Verbose "Writing new entries"
  Run-SQLCMD @sqlParams -SQLCMD $latestInsertSQL -Whatif:$WhatIf
 }
 # Replace prior hv data with most recent data
 $hvClientDataOld = $hvClientDataNew

 if (!$WhatIf) {Start-Sleep 5}

} until ( $WhatIf -or ( (Get-date) -ge $endTime ) )
