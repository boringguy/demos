$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$KeyVaultSecrets = '{
    "logAnalyticsWorkspaceId": {
        "Description": "Workspace ID of the log analytics to connect RHEL machine to",
        "SecretName" : "logAnalyticsWorkspaceId"
    },
    "logAnalyticsWorkspaceKey": {
        "Description": "Workspace Bane of the log analytics to connect RHEL machine to",
        "SecretName" : "logAnalyticsWorkspaceKey"
    },
    "DomainJoin": {
        "Account": {
            "Description": "AD account name to run domain join",
            "SecretName" : "DomainJoinAccount"
        },
        "Password": {
            "Description": "AD account password to run domain join",
            "SecretName" : "DomainJoinPassword"
        },
        "ComputerOU": {
            "Description": "OU to join acount to",
            "SecretName" : "DomainJoinComputerOULinux"
        }
    },
    "TrendMicro": {
        "TenantId": {
            "Description": "Tenant Id",
            "SecretName" : "trendmicro-tenant"
        },
        "Token": {
            "Description": "TrendMicro Public Key Token",
            "SecretName" : "trendmicro-token"
        },
        "GroupId": {
            "Description": "GroupId",
            "SecretName" : "trendmicro-groupid"
        },
        "PolicyId": {
            "Description": "PolicyId",
            "SecretName" : "trendmicro-policyid"
        }
    }
}'
function Login () {}
function Get-AutomationVariable () {
    param(
        [string]$Name
    )
}
function Get-AzVm () {}
function Get-AzNetworkInterface () {}
function Get-AzPublicIpAddress () {}
Describe "Get-AnsibleInventory Unit Tests" {
    Context "Generate Ansible Invetory" {
        Mock Login { return @{ } }
        Mock Get-AutomationVariable {
            if ($Name -eq "KeyVaultSecrets") {
                return $KeyVaultSecrets
            }
        }
        Mock Get-AzVm {
            return @{
                Location       = "westeurope"
                NetworkProfile = @{
                    NetworkInterfaces = @{
                        Id = "/NICId"
                    }
                }
            }
        }
        Mock Get-AzNetworkInterface {
            return @{
                IpConfigurations = @{
                    PrivateIpAddress = "127.0.0.1"
                    PublicIpAddress  = @{
                        Id = "/PublicIpAddressId"
                    }
                }
            }
        }
        Mock Get-AzPublicIpAddress { return @{IpAddress = "50.11.11.11" } }
        $TestCases = @(
            @{
                HostNames = @('mockupvm')
            },
            @{
                HostNames = @('mockupvm1', 'mockupvm2')
            }
        )
        It "Given
        <HostNames> as HostNames" -TestCases $TestCases {
            param(
$HostNames
            )
            # Act
$Output = . "$here\$sut" -HostNames $HostNames
            # Assert
$Output.Exception | Should -BeNullOrEmpty
            foreach ($HostName in $HostNames) {
$Output.Inventory.all.hosts.$($HostName).ansible_host | Should -Be "127.0.0.1"
                $Output.Inventory.all.hosts.$($HostName).log_Analytics_WorkspaceId | Should -Not -BeNullOrEmpty
                $Output.Inventory.all.hosts.$($HostName).LDAPuser | Should -Not -BeNullOrEmpty
                $Output.Inventory.all.hosts.$($HostName).LDAPsecret | Should -Not -BeNullOrEmpty
                $Output.Inventory.all.hosts.$($HostName).computer_ou | Should -Not -BeNullOrEmpty
                $Output.Inventory.all.hosts.$($HostName).tenantId | Should -Not -BeNullOrEmpty
                $Output.Inventory.all.hosts.$($HostName).token | Should -Not -BeNullOrEmpty
                $Output.Inventory.all.hosts.$($HostName).policyid | Should -Not -BeNullOrEmpty
                $Output.Inventory.all.hosts.$($HostName).groupid | Should -Not -BeNullOrEmpty
            }
        }
    }
}