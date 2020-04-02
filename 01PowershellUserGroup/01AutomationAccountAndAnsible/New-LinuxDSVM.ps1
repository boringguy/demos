[CmdletBinding(
    SupportsShouldProcess = $True,
    PositionalBinding = $True
)]
[OutputType([PSCustomObject])]
param(
    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Name of Location - e.g. westeurope"
    )]
    [ValidateSet("westeurope", "eastus2", "westus", "westus2", "southeastasia")]
    [Alias("Loc")]
    [string] $Location,
    [Parameter(
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Code of the Operating System - e.g. L"
    )]
    [ValidateSet("L")]
    [string] $OperatingSystem = "L",
    [Parameter(
        Mandatory = $false,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Size of the additional data disks in GB (Default: 100GB)"
    )]
    [string]
    $DataDiskSizeGB = 512,
    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Azure VM Size"
    )]
    [string]
    $virtualMachineSize,
    [Parameter(
        Mandatory = $True,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "UTC Offset of the target area"
    )]
    [Alias("UTC")]
    [string] $UTCOffset
)

$VerbosePreference = "Continue"
$ErrorActionPreference = "Continue"

### DEFINE OUTPUT FUNCTION
function Set-Output {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true
        )]
        [ValidateSet("Successful", "Failed")]
        [string]$Status,
        [string]$Hostname,
        [string]$IPAddress,
        [string]$Exception
    )
    process {
        $Output = @{
            Status    = $Status
            Hostname  = $null
            IPAddress = $null
            bAccount  = $null
            Exception = $null
        }
        if ($Status -eq 'Failed') {
            $Output.Exception = $Exception
            Write-Error "$Exception"
        }
        else {
            $Output.Hostname = $Hostname
            $Output.IPAddress = $IPAddress
        }
        return $Output
    }
}
function Login() {
    [CmdletBinding()]
    param (
        [string]$ConnectionName = "AzureRunAsConnection"
    )
    process {
        Write-Verbose "[$(Get-Date)] Get the connection $ConnectionName"
        $ServicePrincipalConnection = Get-AutomationConnection -Name $ConnectionName
        if (!$ServicePrincipalConnection) {
            Write-Error "[$(Get-Date)] Connection $connectionName not found."
        }
        Write-Output "[$(Get-Date)] Logging in to Azure..."
        $ConnectionParam = @{
            TenantId              = $ServicePrincipalConnection.TenantId
            ApplicationId         = $ServicePrincipalConnection.ApplicationId
            CertificateThumbprint = $ServicePrincipalConnection.CertificateThumbprint
            InformationAction     = 'SilentlyContinue'
        }
        $ConnectionAzureAD = Connect-AzureAD @ConnectionParam
        Write-Debug "Azure AD connection:"
        Write-Debug "$ConnectionAzureAD"
        $ConnectionParam += @{
            ServicePrincipal = $True
        }
        $ConnectionAzureAz = Connect-AzAccount @ConnectionParam
        Write-Debug "Azure Az connection:"
        Write-Debug "$ConnectionAzureAz"
        $Context = Get-AzContext
        Write-Debug "Az Context:"
        Write-Debug "$Context"
    }
}

### LOGIN
try {
    Login
}
catch {
    return Set-Output -Status Failed -Exception $_.Exception.Message
}

# TODO: Get configuration form Azure Automation Variables

# TODO: Deploy Azure Virtual Machine (Linux)

# TODO: Get information from deployment output

Write-Verbose "[$(Get-Date)] Start Ansible Configuration"
Try {
    $Parameters = @{
        Hostname                             = $DSVM.Outputs['virtualMachineName'].Value
        Playbook                             = $config.PlaybookName
        VirtualMachineAdministratorGroupName = $config.VirtualMachineAdministratorGroupName
    }

    $AutomationAccountName = # TODO: Get Automation Account Name
    $ResourceGroupName = # TODO: Get Resource Group Name
    $HybridWorkerGroup = # TODO: Get Hybrid Worker Group Name

    $Job = Start-AzAutomationRunbook –AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName –Name "Configure-LinuxDSVM" -RunOn $HybridWorkerGroup -Parameters $Parameters -MaxWaitSeconds 1800
    While ($True) {
        $JobStatus = Get-AzAutomationJob -JobId $Job.JobId -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName
        if ($JobStatus -in "Queued", "Starting", "Running") {
            Write-Verbose "[$(Get-Date)] Post configuration is still running. Will check again in 30 seconds."
            Start-Sleep 30
        }
        else {
            Break
        }
    }

    # TODO: Provide necessary information to Set-Output
}
Catch {
    return Set-Output -Status Failed -Exception $_.Exception
}
if ($JobStatus.Status -eq 'Failed') {
    Write-Error "Post configuration failed: $JobStatus"
    return Set-Output -Status Failed -Exception $JobStatus.Exception
}

# TODO: Review Set-Output function
return Set-Output -Status Successful -Hostname $DSVM.Outputs['virtualMachineName'].Value -IPAddress $PublicIp