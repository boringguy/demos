$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
$Ansible = '{
    "Host": "127.0.0.1",
    "User": "user",
    "Path": "/usr/bin/ansible-playbook",
    "InventoryDir": "/tmp",
    "PlaybooksDir": "/opt/azure/ansible-playbook"
}'
function Login () {}
function Get-AutomationVariable () {
    param(
        [string]$Name
    )
}
Describe "Invoke-AnsiblePlaybook Unit Tests" {
    Context "Invoke Ansible Playbook - Dry run" {
        Mock Login { return @{ } }
        Mock Get-AutomationVariable {
            if ($Name -eq "Ansible") {
                return $Ansible
            }
            elseif ($Name -eq "AnsibleSshKey") {
                return "AnsibleSshKey"
            }
        }
        $Inventory = @{
            all = @{
                hosts = @{
                    mockupvm = @{
                        ansible_host = "127.0.0.1"
                    }
                }
            }
        }
        $TestCases = @(
            @{
                Playbook = "playbookwithoutextension"
                Inventory = $Inventory
            },
            @{
                Playbook = "playbookwithextension.yml"
                Inventory = $Inventory
            }
        )
        It "Given
        <Playbook> as Playbook,
        <Inventory> as Inventory
        - expected to succeed without any errors" -TestCases $TestCases {
            param(
$Playbook,
$Inventory
            )
$InputObject = @{
                Playbook = $Playbook
                Inventory = $Inventory
            }
            # Act
$Output = . "$here\$sut" @InputObject -WhatIf
            # Assert
            $Output.Exception | Should -BeNullOrEmpty
        }
    }
}