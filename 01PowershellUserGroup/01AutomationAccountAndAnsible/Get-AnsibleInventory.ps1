[CmdletBinding(
    SupportsShouldProcess = $True,
    PositionalBinding = $True
)]
[OutputType([PSCustomObject])]
param(
    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "List of hostnames"
    )]
    [string[]]$HostNames
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
        [Object]$Inventory,
        [string]$Exception
    )
    process {
        $Output = @{
            Status    = $Status
            Inventory = $null
            Exception = $null
        }
        if ($Status -eq 'Failed') {
            $Output.Exception = $Exception
            Write-Error "$Exception"
        }
        else {
            $Output.Inventory = $Inventory
        }
        Write-Output $Output
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
        Write-Verbose "[$(Get-Date)] Logging in to Azure..."
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
### DEPENDENCIES
try {
    Import-Module MRAzBdapShared
}
catch {
    Write-Error $_.Exception
    return Set-Output -Status Failed -Exception $_.Exception.Message
}
### LOGIN
try {
    $null = Login
}
catch {
    return Set-Output -Status Failed -Exception $_.Exception.Message
}
### VARIABLES
Write-Verbose "[$(Get-Date)] Source variables"
$Environment = (Get-AzSubscription).Name.Split("-")[1]
$Servers = @()
$KeyVaultSecrets = Get-AutomationVariable -Name "KeyVaultSecrets" | ConvertFrom-Json
try {
    foreach ($HostName in $HostNames) {
        Write-Verbose "[$(Get-Date)] Get information for host $HostName"
        $VM = Get-AzVm -Name $HostName
        $Location = $VM.Location
        $VMNICName = $VM.NetworkProfile.NetworkInterfaces.Id.Split("/")[-1]
        $VMIpConfigurations = (Get-AzNetworkInterface -Name $VMNICName -ResourceGroupName $VM.ResourceGroupName).IpConfigurations
        $PrivateIp = $VMIpConfigurations.PrivateIpAddress
        $PublicIpName = $VMIpConfigurations.PublicIpAddress.Id.Split("/")[-1]
        $PIPResourceGroupName = $VMIpConfigurations.PublicIpAddress.Id.Split("/")[4]
        $PublicIp = (Get-AzPublicIpAddress -Name $PublicIpName -ResourceGroupName $PIPResourceGroupName).IpAddress
        Write-Verbose "[$(Get-Date)] $Hostname - PrivateIp: $PrivateIp"
        Write-Verbose "[$(Get-Date)] $Hostname - PublicIp: $PublicIp"
        $KeyVaultName = ("mr-bdap-{0}-{1}" -f $Environment, $MrLocation).ToLower()
        Write-Verbose "[$(Get-Date)] $Hostname - KeyVault: $KeyVaultName"
        Write-Verbose "[$(Get-Date)] $Hostname - Retrieve Domain Join information"
        $DomainJoin = @{
            LDAPUser   = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecrets.DomainJoin.Account.SecretName).SecretValueText.Split("\")[1]
            LDAPsecret = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecrets.DomainJoin.Password.SecretName).SecretValueText
            ComputerOU = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecrets.DomainJoin.ComputerOU.SecretName).SecretValueText
        }
        Write-Verbose "[$(Get-Date)] $Hostname - Retrieve TrendMicro information"
        $TrendMicro = @{
            TenantId = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecrets.TrendMicro.TenantId.SecretName).SecretValueText
            Token    = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecrets.TrendMicro.Token.SecretName).SecretValueText
            PolicyId = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecrets.TrendMicro.PolicyId.SecretName).SecretValueText
            GroupId  = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $KeyVaultSecrets.TrendMicro.GroupId.SecretName).SecretValueText
        }
        Write-Verbose "[$(Get-Date)] $Hostname - Retrieve Log Analytics information"
        $LogAnalytics = @{
            WorkspaceId = (Get-AzKeyVaultSecret -vaultName $KeyVaultName -Name $KeyVaultSecrets.logAnalyticsWorkspaceId.SecretName).SecretValueText
        }
        $Servers += @(
            [PSCustomObject]@{
                Name      = $Hostname
                IpAddress = $PublicIp
                Vars      = @{
                    ansible_ssh_common_args   = '-o StrictHostKeyChecking=no'
                    log_Analytics_WorkspaceId = $LogAnalytics.WorkspaceId
                    LDAPuser                  = $DomainJoin.LDAPuser
                    LDAPsecret                = $DomainJoin.LDAPsecret
                    computer_ou               = $DomainJoin.ComputerOU
                    tenantId                  = $TrendMicro.TenantId
                    token                     = $TrendMicro.Token
                    policyid                  = $TrendMicro.PolicyId
                    groupid                   = $TrendMicro.GroupId
                }
            }
        )
    }
}
catch {
    Write-Error $_.Exception
    return Set-Output -Status Failed -Exception $_.Exception.Message
}
### PROCESS
try {
    Write-Verbose "[$(Get-Date)] Create Ansible Inventory"
    $Inventory = Get-MRAzBdapSharedAnsibleInventory -Servers $Servers
    Write-Verbose "[$(Get-Date)] Ansible Inventory created"
    return Set-Output -Status Successful -Inventory $Inventory
}
catch {
    Write-Error $_.Exception
    return Set-Output -Status Failed -Exception $_.Exception.Message
}
