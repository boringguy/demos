[CmdletBinding(
    SupportsShouldProcess = $True,
    PositionalBinding = $True
)]
[OutputType([PSCustomObject])]
param(
    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Name of DSVM"
    )]
    [string] $Hostname,
    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Administrator Group Name"
    )]
    [string] $VirtualMachineAdministratorGroupName = "Fun-CED-bdap-sbx-azure-contributor",
    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "N-Number of the requestor"
    )]
    [string] $NNumber,
    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Ansible Configuration - Playbook"
    )]
    #[ValidateSet("bdap-az-centos-postdeployment")]
    [string] $Playbook = "bdap-az-centos-postdeployment"
)
$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"
### DEFINE OUTPUT FUNCTION
function Set-Output {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true
        )]
        [ValidateSet("Successful", "Failed")]
        [string]$Status,
        [string]$Exception
    )
    process {
        $Output = @{
            Status    = $Status
            Exception = $null
        }
        if ($Status -eq 'Failed') {
            $Output.Exception = $Exception
            Write-Error "$Exception"
        }
        return $Output
    }
}
Try {
    $GetAnsibleInventoryOutput = .\Get-AnsibleInventory.ps1 -Hostnames $($Hostname)
    If ($GetAnsibleInventoryOutput.Exception) {
        return Set-Output -Status Failed -Exception $GetAnsibleInventoryOutput.Exception
    }
}
Catch {
    Write-Error $_.Exception
    return Set-Output -Status Failed -Exception $_.Exception.Message
}
Write-Verbose "[$(Get-Date)] Add DSVM specific parameters"
$Inventory = $GetAnsibleInventoryOutput.Inventory
$Inventory.all.hosts.$($Hostname).Add('dsvm_admin_group', $VirtualMachineAdministratorGroupName)
$Inventory.all.hosts.$($Hostname).Add('dsvm_user', $NNumber)
Try {
    $InvokeAnsiblePlaybookOutput = .\Invoke-AnsiblePlaybook.ps1 -Playbook $Playbook -Inventory $Inventory
    If ($InvokeAnsiblePlaybookOutput.Exception) {
        return Set-Output -Status Failed -Exception $InvokeAnsiblePlaybookOutput.Exception
    }
}
Catch {
    Write-Error $_.Exception
    return Set-Output -Status Failed -Exception $_.Exception.Message
}
return Set-Output -Status Successful
