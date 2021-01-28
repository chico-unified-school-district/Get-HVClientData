<#
.SYNOPSIS
 Restart vCenter Hosts in order
.DESCRIPTION
 Get hosts attached to vCenter server, place in Maintenance Mode, Restart.
.PARAMETER Server
 A vCenter server name
.PARAMETER Credential
 A credential object with permissions to vCenter Host poweroperation
.PARAMETER WhatIf
 Switch to turn testing mode on or off.
.EXAMPLE
.\Restart-VCenterHosts.ps1 -Server vcenterServer.my.com -Credential $vcenterCredObj
.EXAMPLE
.\Restart-VCenterHosts.ps1 -Server vcenterServer.my.com -Credential $vcenterCredObj -WhatIf
.INPUTS
 [string] vCenter Server name 
 [PSCredential] vCenter Credentials
.OUTPUTS
 Log messages are output to the console.
.NOTES
 Warning:
 Disabling DRS will delete any resource pool on the cluster without warning!!!
 http://www.van-lieshout.com/2010/05/powercli-disableenable-ha-and-drs/
 Special thanks to Arnim van Lieshout.

 This script requires more than one host in each cluster to function properly
#>

[cmdletbinding()]
param (
 # Target VIServer
 [Parameter(Mandatory = $True)]
 [Alias('vcserver')]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$VCenterServer,
 # VIServer Credentials with Proper Permission Levels
 [Parameter(Mandatory = $True)]
 [Alias('vccred')]
 [System.Management.Automation.PSCredential]$VCenterCredential,
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
 [string]$DatabaseServer,
 [Parameter(Mandatory = $True)]
 [string]$Database,
 # VIServer Credentials with Proper Permission Levels
 [Parameter(Mandatory = $True)]
 [Alias('dbcred')]
 [System.Management.Automation.PSCredential]$DatabaseCredential,
 [Alias('wi')]
 [switch]$WhatIf
)
# $env:psmodulepath += 'C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules'
Clear-Host
$env:psmodulepath = 'C:\Program Files\WindowsPowerShell\Modules; C:\Windows\system32\config\systemprofile\Documents\WindowsPowerShell\Modules; C:\Program Files (x86)\WindowsPowerShell\Modules; C:\Windows\system32\WindowsPowerShell\v1.0\Modules; C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules'
# Import Functions
. .\lib\Add-Log.ps1
. .\lib\Set-PSCred.ps1

Import-Module VMware.VimAutomation.HorizonView
Import-Module VMware.VimAutomation.Core
 # $server = Read-Host "VDI COnnection Server Name"
$hvServer1 = Connect-HVServer -Server $VDIConnectionServer -Cred $VDICredential
$hvExtData = $hvServer1.ExtensionData
Connect-VIServer -Server $VCenterServer -Cred $VCenterCredential

$dts = Get-Date -f u
$hvClientData = (Get-HVLocalSession).namesdata
# Write Initial results + DTS

do {
 $dts = Get-Date -f u
 $hvClientData2 = (Get-HVLocalSession).namesdata
 $compareObjParams = @{
  ReferenceObject  = $hvClientData
  DifferenceObject = $hvClientData2
  Property         = 'UserName','MachineOrRDSServerName','ClientName','ClientAddress'
 }
 $newEntries = Compare-Object @compareObjParams

 # Write changes + DTS
}