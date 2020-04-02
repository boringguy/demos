[CmdletBinding(
    SupportsShouldProcess = $True,
    PositionalBinding = $True
)]
[OutputType([PSCustomObject])]
param(
    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Name of Ansible playbook"
    )]
    [string] $Playbook,
    [Parameter(
        Mandatory = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Ansible Inventory"
    )]
    [Object] $Inventory
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
### LOGIN
try {
    $null = Login
}
catch {
    return Set-Output -Status Failed -Exception $_.Exception.Message
}
### VARIABLES
$AnsibleConfig = Get-AutomationVariable -Name "Ansible" | ConvertFrom-Json
$AnsibleSshKey = Get-AutomationVariable -Name "AnsibleSshKey"
$Password = "Empty" | ConvertTo-SecureString -asPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($AnsibleConfig.User, $Password)
$DateTime = $(Get-Date -Format FileDateTime)
Write-Verbose "[$(Get-Date)] Parse local inventory path"
$InvetoryFileName = ("inventory_{0}.yml" -f $DateTime)
Write-Verbose "[$(Get-Date)] Parse remote inventory path"
$InventoryPathRemote = (Join-Path $AnsibleConfig.InventoryDir $InvetoryFileName).Replace("\", "/")
if (!$Playbook.EndsWith(".yml")) {
    $Playbook += ".yml"
}
Write-Verbose "[$(Get-Date)] Parse remote playbook path"
$PlaybookPath = (Join-Path $AnsibleConfig.PlaybooksDir $Playbook).Replace("\", "/")
Write-Verbose "[$(Get-Date)] Inventory stored locally as '$InvetoryFileName'"
if ($PSCmdlet.ShouldProcess("LOCALHOST", "Store inventory locally as '$InvetoryFileName'")) {
    $Inventory | ConvertTo-Yaml | Out-File  -FilePath $InvetoryFileName -NoNewLine -Encoding "UTF8"
}
### PROCESS
try {
    Write-Verbose "[$(Get-Date)] Copying inventory to Ansible host - $($AnsibleConfig.Host)"
    if ($PSCmdlet.ShouldProcess("$($AnsibleConfig.Host)", "Copy inventory $InvetoryFileName to remote location $($AnsibleConfig.InventoryDir)")) {
        $SCPStatus = Set-SCPFile -Computer $AnsibleConfig.Host -Credential $Credential -KeyString $AnsibleSshKey -LocalFile $InvetoryFileName -RemotePath $AnsibleConfig.InventoryDir -Force
        if ($SCPStatus.Error) {
            return Set-Output -Status Failed -Exception $SCPStatus.Error
        }
    }
    # File is copied to Ansible host, remember to remove it at the end
    $RemoveRemoteFile = $True
    Write-Verbose "[$(Get-Date)] Config: $AnsibleConfig"
    Write-Verbose "[$(Get-Date)] Opening new SSH session to Ansible host"
    if ($PSCmdlet.ShouldProcess("$($AnsibleConfig.Host)", "Open new SSH session to Ansible host")) {
        $SshSession = New-SSHSession -Computer $AnsibleConfig.Host -Credential $Credential -KeyString $AnsibleSshKey -Force
        Write-Verbose "[$(Get-Date)] SSHSession: $SshSession"
        if ($SshSession.Error) {
            Write-Verbose "[$(Get-Date)] SSHSession Error: $SshSession.Error"
            return Set-Output -Status Failed -Exception $SshSession.Error
        }
    }
    $Command = ("{0} -i {1} {2}" -f $AnsibleConfig.Path, $InventoryPathRemote, $PlaybookPath)
    Write-Verbose "[$(Get-Date)] Executing the command: $Command"
    if ($PSCmdlet.ShouldProcess("$($AnsibleConfig.Host)", "Execute command: '$Command'")) {
        Write-Verbose "[$(Get-Date)] Host: $AnsibleConfig.Host"
        $CommandStatus = Invoke-SSHCommand $Command -SSHSession $SshSession -TimeOut 10800
        Write-Verbose "[$(Get-Date)] Ansible Output:"
        Write-Verbose "$($CommandStatus.Output)"
        if ($CommandStatus.ExitStatus -ne 0) {
            Write-Error "$($CommandStatus.Output)"
            return Set-Output -Status Failed -Exception "Ansible playbook has failed, please check the logs for more information."
        }
    }
    return Set-Output -Status Successful
}
catch {
    Write-Error $_.Exception
    return Set-Output -Status Failed -Exception $_.Exception.Message
}
finally {
    Write-Verbose "[$(Get-Date)] Removing local inventory file $InvetoryFileName"
    if ($PSCmdlet.ShouldProcess("LOCALHOST", "Remove local inventory file $InvetoryFileName")) {
        Remove-Item -Path $InvetoryFileName -Force
        Write-Verbose "[$(Get-Date)] File $InvetoryFileName removed"
    }
    if ($RemoveRemoteFile) {
        $Command = ("rm -fr {0}" -f $InventoryPathRemote)
        try {
            Write-Verbose "[$(Get-Date)] Removing remote inventory file $InventoryPathRemote"
            if ($PSCmdlet.ShouldProcess("$($AnsibleConfig.Host)", "Remove remote inventory file $InventoryPathRemote")) {
                $CommandStatus = Invoke-SSHCommand $Command -SSHSession $SshSession
                if ($CommandStatus.ExitStatus -eq 0) {
                    Write-Verbose "[$(Get-Date)] File $InventoryPathRemote removed"
                }
                else {
                    Write-Verbose "[$(Get-Date)] Failed to remove remote inventory file $InventoryPathRemote"
                    Write-Verbose "[$(Get-Date)] $($CommandStatus.Output)"
                }
            }
        }
        catch {
            Write-Error $_.Exception
        }
    }
    try {
        if ($PSCmdlet.ShouldProcess("$($AnsibleConfig.Host)", "Remove SSHSession")) {
            Remove-SSHSession -SSHSession $SshSession
        }
    }
    catch {
        Write-Error $_.Exception
    }
}