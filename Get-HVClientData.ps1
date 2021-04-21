<#
.SYNOPSIS
 Collects Horizon View session data and writes data to a SQL server database. 
.DESCRIPTION
 Collects Horizon View session data and writes data to a SQL server database.
 Requires HV Connection Server
.PARAMETER Server
 A vCenter server name
.PARAMETER Credential
.PARAMETER WhatIf
 Switch to turn testing mode on or off.
.EXAMPLE
.\Get-VDIClientData.ps1 -hvserver hvserver.mydomain.edu -hvCredential $hvCredObj -SQLServer mssql.mydomain.edu -Database ViewClientSessionsDB -TableName ViewClientSessionDataTable -SQLCredential $nativeMSSQLCredObj
.EXAMPLE
.\Get-VDIClientData.ps1 -hvserver hvserver.mydomain.edu -hvCredential $hvCredObj -SQLServer mssql.mydomain.edu -Database ViewClientSessionsDB -TableName ViewClientSessionDataTable -SQLCredential $nativeMSSQLCredObj -WhatIf -Verbose -Debug
.INPUTS
.OUTPUTS
 Log messages are output to the console.
.NOTES
"HV" in the context of this script is shorthand for "Horizon View"

Special Thanks to all you generaous folks out there:
 Dugas! https://stackoverflow.com/questions/33503283/replace-null-value-in-powershell-output
 https://www.sqlservertutorial.net/sql-server-basics/sql-server-insert-multiple-rows/
 Graeme Gordon! https://blogs.vmware.com/euc/2020/01/vmware-horizon-7-powercli.html
#>

[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)]
 [Alias('hvserver','vdiserver')]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$HVConnectionServer,
 [Parameter(Mandatory = $True)]
 [Alias('vdicred')]
 [System.Management.Automation.PSCredential]$HVCredential,
 [Parameter(Mandatory = $True)]
 [Alias('dbserver')]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$SQLServer,
 [Parameter(Mandatory = $True)]
 [string]$Database,
 [Parameter(Mandatory = $True)]
 [string]$TableName,
 [Parameter(Mandatory = $True)]
 [Alias('dbcred')]
 [System.Management.Automation.PSCredential]$SQLCredential,
 [Alias('wi')]
 [switch]$WhatIf
)
# $env:psmodulepath = 'C:\Program Files\WindowsPowerShell\Modules; C:\Windows\system32\config\systemprofile\Documents\WindowsPowerShell\Modules; C:\Program Files (x86)\WindowsPowerShell\Modules; C:\Windows\system32\WindowsPowerShell\v1.0\Modules; C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules'

# Import Functions
. '.\lib\Add-Log.ps1'
. '.\lib\Run-SQLCMD.ps1'
. '.\lib\Set-PSCred.ps1'

Import-Module VMware.VimAutomation.HorizonView

# Clear current server connections
if ($global:DefaultHVServers) { Disconnect-HVServer -Server * -Force -Confirm:$false }

function checkAllHVServers ([array]$hvServers, [System.Management.Automation.PSCredential]$hvCred) {
 foreach ($connServer in $hvServers){
  if ($global:DefaultHVServers.name -notcontains $connServer){
   Add-Log hvserver ( 'Connecting to {0}' -f $connServer )
   $count = 10
   do {
    Write-Verbose ('Connecting to hvServer {0} as {1}' -f $connServer, $hvCred.Username)
    Connect-HVServer -Server $connServer -Cred $hvCred
    Start-Sleep 1
    $count--
    if ($global:DefaultHVServers.name -contains $connServer){
     Add-Log hvserver ( 'HV server {0} connected.' -f $connServer )
    }
   }
   until ( ($global:DefaultHVServers.name -contains $connServer) -or ($count -eq 0) )
  } else {
   Write-Verbose "HV $connServer already connected."
  }
 }
}

$columnNames = 'UserName,AgentVersion,ClientAddress,ClientLocationID,ClientName,ClientType,ClientVersion,DesktopName,DesktopPoolCN,DesktopSource,DesktopType,MachineOrRDSServerDNS,SecurityGatewayAddress,SecurityGatewayDNS,SecurityGatewayLocation'
$propertyNames = 'UserName','AgentVersion','ClientAddress','ClientLocationID','ClientName','ClientType','ClientVersion','DesktopName','DesktopPoolCN','DesktopSource','DesktopType','MachineOrRDSServerDNS','SecurityGatewayAddress','SecurityGatewayDNS','SecurityGatewayLocation'

function formatClientDataSQL ($table,$hvNamesdata) {
 # Replace empty data with 'NULL' and convert to CSV with double quoted data.
 $global:i = 0
 $convertedSQLValues = $hvNamesdata | Select-Object $propertyNames | ForEach-Object {
  foreach ($p in $_.PSObject.Properties) {
   if ( $null -eq $p.Value ) {
    $p.Value = 'NULL'
   }
  }
  $_
 } | ConvertTo-Csv -NoTypeInformation
 # Remove Table Headers, put commas between values as needed, 
 # add () around VALUES, and replace double quotes with single quotes
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

Connect-HVServer -Server $HVConnectionServer -Cred $HVCredential
$allHvServers = $global:DefaultHVServers.extensiondata.ConnectionServer.ConnectionServer_List().general.fqhn

checkAllHVServers -hvServers $allHvServers -hvCred $HVCredential

# Get initial client data from all HV Servers
$hvClientDataOld = (Get-HVLocalSession).namesdata

$sqlParams = @{
 Server        = $SQLServer
 Database      = $Database
 Credential    = $SQLCredential
}

# if ($hvClientDataOld){
 # Add-Log sqltable ('Adding data to {0}' -f $TableName)
 # $initialInsertSQL = formatClientDataSQL -table $TableName -hvNamesdata $hvClientDataOld
 # Write initial connection results
 # Run-SQLCMD @sqlParams -SQLCMD $initialInsertSQL -Whatif:$WhatIf
# }

do {
 Write-Verbose "Running Loop"

 # Cleanup old database entries
 $cleanupCMD = "DELETE FROM $Tablename WHERE DTS < DATEADD(day, -180,getdate())"
 Run-SQLCMD @sqlParams -SQLCMD $cleanupCMD -Whatif:$WhatIf

 # Check hv connection server session
 checkAllHVServers -hvServers $allHvServers -hvCred $HVCredential

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
  $newHVEntries
  # Read-Host "Wait and check the sql...."
  Write-Verbose "Writing new entries"
  Run-SQLCMD @sqlParams -SQLCMD $latestInsertSQL -Whatif:$WhatIf
 }

 # Replace prior hv data with most recent data
 $hvClientDataOld = $hvClientDataNew

 # Loop delay time in seconds
 $delayTime = 10
 if (!$WhatIf) {Start-Sleep $delayTime}

} until ( $WhatIf ) # Runs forever unless -whatif specified.

# Cleanup
if ($global:DefaultHVServers) { Disconnect-HVServer -Server * -Force -Confirm:$false }