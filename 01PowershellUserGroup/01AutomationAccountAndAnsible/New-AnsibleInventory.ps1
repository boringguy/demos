function New-AnsibleInventory {
    <#
    .SYNOPSIS
    Returns the Ansible inventory
    .DESCRIPTION
    Returns the Ansible inventory
    .PARAMETER Servers
    List of Server objects. Server object has following definition
    [PSCustomObject]@{
        Name = "Hostname"
        IpAddress = "127.0.0.1"
        Vars = @{
            var1 = "value1"
            var2 = "value2"
        }
        Groups = @("group1", "group2")
    }
    .PARAMETER GroupsVariables
    Group specific variables
    [HashTable]@{
        group1 = @{
            groupvar1 = "value1"
        }
        group2 = @{
            groupvar1 = "value1"
            groupvar2 = "value2"
        }
    }
    .EXAMPLE
    $Servers =@(
        [PSCustomObject]@{
            Name      = "host1"
            IpAddress = "127.0.0.1"
        },
        [PSCustomObject]@{
            Name      = "host2"
            IpAddress = "127.0.0.2"
            Vars      = @{
                var1 = "value1"
                var2 = "value2"
            }
            Groups    = @("group1")
        }
    )
    $GroupsVariables = @{
        all    =    @{
            allvar1 = "value1"
        }
        group1 = @{
            group1var1 = "value1"
            group1var2 = "value2"
        }
    }
    Get-MrAzBdapSharedAnsibleInventory -Servers $Servers -GroupsVariables $GroupsVariables
    Returns Ansible Inventory
    @{
        all    = @{
            host1 = @{
                ansible_host = "127.0.0.1"
            }
            host2 = @{
                ansible_host = "127.0.0.2"
                var1         = "value1"
                var2         = "value2"
            }
            vars  = @{
                allvar1 = "value1"
            }
        }
        group1 = @{
            host2 = $null
            vars  = @{
                group1var1 = "value1"
                group1var2 = "value2"
            }
        }
    }
#>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "List of server objects"
        )]
        [PSCustomObject[]]
        $Servers,
        [Parameter(
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Group variables"
        )]
        [HashTable]$GroupsVariables
    )
    begin {
    }
    process {
        $Inventory = [System.Collections.Specialized.OrderedDictionary]@{ }
        $Inventory.Add("all", [System.Collections.Specialized.OrderedDictionary]@{ })
        $Inventory.all.Add("hosts", [System.Collections.Specialized.OrderedDictionary]@{ })
        foreach ($Server in $Servers) {
            $Inventory.all.hosts.Add($($Server.Name), @{ansible_host = $Server.IpAddress })
            if ($Server.Vars) {
                $Inventory.all.hosts.$($Server.Name) += $Server.Vars
            }
            foreach ($group in $Server.Groups) {
                if (!$Inventory.Contains($group)) {
                    $Inventory.Add($group, [System.Collections.Specialized.OrderedDictionary]@{ })
                    $Inventory.$($group).Add("hosts", [System.Collections.Specialized.OrderedDictionary]@{ })
                }
                $Inventory.$($group).hosts.Add($Server.Name, $null)
            }
        }
        foreach ($group in $GroupsVariables.Keys) {
            $Inventory.$($group).Add("vars", @{ })
            $Inventory.$($group).vars += $GroupsVariables.$($group)
        }
        $Inventory
    }
    end {
    }
}