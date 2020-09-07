<#  
.SYNOPSIS  
    Automated deployment of virtual machines to Azure Subscription.

.DESCRIPTION
    Signs into Azure Subscription, collates existing information; VPN, NSG, KV etc. takes user input from WPF Form and deploys virtual machines.

.NOTES  
    Author     : Mahir Ajmal
    Version    : 0.1
#>

function Create-Password {
    $password = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".ToCharArray()
    ($password | Get-Random -Count 11) -Join ''
}

function next-as {
    param (
    [parameter(mandatory)]$vn,
    [parameter(mandatory)]$vm
    )
    [hashtable]$return = @{}
    $y=0
    $schck = $true
    if ($vm -match "VW") {
        $vm = $vm.SubString(1)
        $vm = $vm -replace "vw.*", "vw"
    }
    Do {
        if ($vn.Subnets[$y].Name -ne $vm+"_subnet") {
            $y ++
        }
        else {
            $schck = $false
        }
    } while ($schck -ne $false)
    $ap = $vn.Subnets[$y].AddressPrefix
    $subid = $vn.Subnets[$y].Id
    $networkid = $ap -replace ("[0-9]{1,3}[/][1-9]{1,3}$", "")
    $endipstring = $ap -replace ("$networkid", "")
    $endipstring = $endipstring -replace ("[/][1-9]{1,3}$", "")
    $newadd = $endipstring
    $newadd = [int]$endipstring.GetValue(0)
    
    $localaddress = $false
    while ($localaddress -eq $false) {
        $newadd = ++ $newadd
        $ip = $networkid.GetValue(0) + $newadd
        $address = Test-AzPrivateIPAddressAvailability -VirtualNetwork $vn -IPAddress $ip
        if ($address.Available -eq $true) {
            $localipaddress = $ip
            $localaddress = $true
        }
    }
    $return.lia = $localipaddress
    $return.subid = $subid
    return $return
}

function deploy-vm {
    param(
        [parameter(mandatory)]$vm,
        [parameter(mandatory)]$size,
        [parameter(mandatory)]$loc,
        [parameter(mandatory)]$vn,
        [parameter(mandatory)]$nsec,
        [parameter(mandatory)]$kv,
        [parameter(mandatory)]$str
    )
    $rg = New-AzResourceGroup -Name ($pfxselect+$vm+"_RG") -Location $loc.DisplayName
    Write-Host -ForegroundColor Green "New Resource Group deployed"
    $pword = Create-Password
    $pword = ConvertTo-SecureString ($pword + '!') -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $kv -Name ($vm+"-admin") -SecretValue $pword -ContentType "Windows Administrator Account" -NotBefore ((Get-Date).ToUniversalTime())
    Write-Host -ForegroundColor Green "Administrator Credentials stored in Key Vaults"
    $user = $vm+"admin"
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $user, $pword
    $nextas = next-as -vn $vn -vm $vm
    Write-Host -ForegroundColor Green "Address to be used: $nextas.lia"
    $nic = New-AzNetworkInterfaceIpConfig -Name ($pfxselect+$vm+"nic") -PrivateIpAddressVersion IPv4 -PrivateIpAddress $nextas.lia -SubnetId $nextas.subid
    $nic = New-AzNetworkInterface -Name $nic.Name -ResourceGroupName $rg.ResourceGroupName -Location $loc.DisplayName -IpConfiguration $nic -NetworkSecurityGroupId $nsec.Id
    Write-Host -ForegroundColor Green "Network Interface Card has been deployed"
    $vmconfig = New-AzVMConfig -VMName ($pfxselect+$vm) -VMSize $size
    $vmconfig = Set-AzVMOperatingSystem -Windows -ComputerName $vmconfig.Name -Credential $cred -ProvisionVMAgent -VM $vmconfig -TimeZone 'GMT Standard Time' | Set-AzVMSourceImage -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2016-Datacenter' -Version 'Latest' | Add-AzVMNetworkInterface -Id $nic.Id
    $vmconfig = Set-AzVMOSDisk -VM $vmconfig -Name $vmconfig.Name -VhdUri ($str.PrimaryEndpoints.Blob.ToString()+"vhds/"+($pfxselect+$vm+"OSDisk")+".vhd") -CreateOption FromImage
    $vmconfig = Set-AzVMBootDiagnostic -VM $vmconfig -Enable -ResourceGroupName $str.ResourceGroupName -StorageAccountName $str.StorageAccountName
    $newvm = New-AzVM -ResourceGroupName $rg.ResourceGroupName -Location $loc.DisplayName -VM $vmconfig
    Write-Host -ForegroundColor Green "Virtual Machine has been deployed"

}

# Function takes XAML string and converts to a PowerShell [Windows.window] Object
function Get-WindowFromXamlString {
    param (
        [Parameter(Mandatory)][string]$xaml
    )
    # Type required for Windows Presentation Framework form
    Add-Type -AssemblyName PresentationFramework

    [string]$_byteOrderMarkUtf8 = [Text.Encoding]::UTF8.GetString([Text.Encoding]::UTF8.GetPreamble())
    if ($xaml.StartsWith($_byteOrderMarkUtf8, [StringComparison]::Ordinal)) {
        Write-Warning -Message "Byte Order Issue Found"
        [int]$lastIndexOfUtf8 = $_byteOrderMarkUtf8.Length
        $xaml = $xaml.remove(0, $lastIndexOfUtf8)
    }
    
    $xaml = $xaml -replace 'mc:Ignorable="d"','' -replace 'x:N','N' -replace '^<Win.*', '<Window'

    $reader = [XML.XMLReader]::Create([IO.StringReader]$xaml)
    $result = [Windows.Markup.XAMLReader]::Load($reader)

    (((Select-Xml -Xml ([xml]$xaml) -XPath / ).Node).SelectNodes('//*[@Name]')).Name | ForEach-Object {
        $result | Add-Member -MemberType NoteProperty -Name $_ -Value $result.FindName($_) -Force
    }
    $result
}

# Function will display the described XAML window
function Show-WPFWindow {
    param (
        [Parameter(Mandatory)][Windows.Window]$window
    )
    $null = $window.Dispatcher.InvokeAsync{
        $window.ShowDialog()
    }.wait()
    $window.DialogResult
}

New-Item -Path $env:TEMP -Name "new.ps1" -ItemType "file" -Value "Set-WinSystemLocale en-GB
Set-WinUserLanguageList en-GB -Force"

$ErrorActionPreference = 'Stop'

Try {
    Connect-AzAccount
    $azureSubscription = (Get-AzSubscription | Sort-Object Name | Out-GridView -Title "Choose your Azure subscription and click OK." -PassThru)
    if ($azureSubscription -ne $null) { Write-host "Switching to Azure subscription: $($azureSubscription.Name)"  -ForegroundColor Green }
    $azureSubscriptionInfo = Select-AzSubscription -SubscriptionId $azureSubscription.Id
    $azureLocation = (Get-AzLocation | Sort-Object Name | Out-GridView -Title "Chosose your Azure location and click OK." -PassThru)
    if ($azureLocation -ne $null) { Write-Host "Switching to Azure location: $($azureLocation.DisplayName)" -ForegroundColor Green }
} Catch {
    "User canceled authentication"
}

$rglist = Get-AzResourceGroup

# Get information for virtual networks and associated subnets
$vnet = Get-AzVirtualNetwork
$vnetList = @()
foreach ($v in $vnet) {
    if ($vnet.Location -eq $azureLocation.Location) {
        $vnetList += $vnet.Name
    }
}
$vnetList = $vnetList | Where-Object { $_ } | Select-Object -Unique
if ($vnetList -eq $null) { 
    Write-Host -ForegroundColor white -BackgroundColor DarkRed "No existing virtual networks found." 
} else { 
    Write-Host -ForegroundColor Green "Available virtual networks loaded."
}

# Get Network Security Group
$nsg = Get-AzNetworkSecurityGroup
$nsgList = @()
foreach ($n in $nsg) {
    if ($nsg.Location -eq $azureLocation.Location) {
        $nsgList += $nsg.Name
    }
}
$nsgList = $nsgList | Where-Object { $_ } | Select-Object -Unique
if ($nsgList -eq $null) {
    Write-Host -ForegroundColor White -BackgroundColor DarkRed "No existing network security groups found."
} else { Write-Host -ForegroundColor Green "Available network security groups loaded." }

# Get Key Vaults List
$currentKeyVaults = Get-AzKeyVault
$keyVaultsList = @()    
foreach ($currentKeyVaults in $currentKeyVaults) {
    if ($currentKeyVaults.Location -eq $azureLocation.Location) {
        $keyVaultsList += $currentKeyVaults.VaultName
        }
}
$keyVaultsList = $keyVaultsList | Where-Object { $_ } | Select-Object -Unique
if ($keyVaultsList -eq $null) {
    Write-Host -ForegroundColor White -BackgroundColor DarkRed "No existing azure key vaults found."
} else { Write-Host -ForegroundColor Green "Available azure key vaults loaded." }

if ($errorsFound -eq $false) {
    Write-Host -ForegroundColor Yellow -BackgroundColor DarkRed "Errors were found whilst loading resources. Ensure components are available before proceeding."
    pause
    exit
}

do {
    [string]$xaml = @"
    <Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:ed="http://schemas.microsoft.com/expression/2010/drawing"
        x:Name="Input" Title="Virtual Machine Deployment Tool" SizeToContent="WidthAndHeight" WindowStartupLocation="CenterScreen">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Label x:Name="vmpfxcaption" Content="Virtual Machine Prefix:" Grid.Row="0" HorizontalAlignment="Left" Margin="10, 0, 0, 0" />
            <TextBox x:Name="vmpfx" Width="200" Grid.Row="1" HorizontalAlignment="Left" Margin="10, 0, 0, 0" />
            <Label x:Name="nsglabel" Content="Network Security Group:" Grid.Row="2" HorizontalAlignment="Left" Margin="10, 0, 0, 0" />
            <ComboBox x:Name="nsgselect" Width="200" Grid.Row="3" HorizontalAlignment="Left" Margin="10, 0, 0, 0" />
            <Label x:Name="dvwlabel" Content="Development Virtual Workers:" Grid.Row="4" HorizontalAlignment="Left" Margin="10, 0, 0, 0" />
            <ComboBox x:Name="dvwselect" Width="200" Grid.Row="5" HorizontalAlignment="Left" Margin="10, 0, 0, 0" />
            <Button x:Name="confirm" Content="Confirm Settings" IsDefault="True" Width="200" Grid.Row="6" HorizontalAlignment="Left" Margin="10, 20, 10, 10" />
            <Label x:Name="vnlabel" Content="Virtual Network:" Grid.Row="0" Grid.Column="1" HorizontalAlignment="Left" Margin="10, 0, 10, 0" />
            <ComboBox x:Name="vnselect" Width="200" Grid.Row="1" Grid.Column="1" HorizontalAlignment="Left" Margin="10, 0, 10, 0" />
            <Label x:Name="kvlabel" Content="Key Vault:" Grid.Row="2" Grid.Column="1" HorizontalAlignment="Left" Margin="10, 0, 10, 0" />
            <ComboBox x:Name="kvselect" Width="200" Grid.Row="3" Grid.Column="1" HorizontalAlignment="Left" Margin="10, 0, 10, 0" />
            <Label x:Name="pvwlabel" Content="Production Virtual Workers:" Grid.Row="4" Grid.Column="1" HorizontalAlignment="Left" Margin="10, 0, 10, 0" />
            <ComboBox x:Name="pvwselect" Width="200" Grid.Row="5" Grid.Column="1" HorizontalAlignment="Left" Margin="10, 0, 10, 0"/>
            <Button x:Name="cancel" Content="Cancel" IsCancel="True" Width="200" Grid.Row="6" Grid.Column="1" Margin="10, 20, 10, 10"  />
        </Grid>
    </Window>
"@

    # Region WPF Form Generation 
    $window = Get-WindowFromXamlString -xaml $xaml
    $response = '' | Select-Object -Property Text, Result

    # Region WPF Form Event Handlers
    $window.confirm.add_click{
        $window.DialogResult = $true
    }
    $window.cancel.add_click{
        $window.DialogResult = $false
    }

    # Presents Virtual Network in the target location in a dropdown box
    foreach ($v in $vnetlist) {
        $window.vnselect.Items.Add($v) | Out-Null
    }
    # Presents Network Security Groups in the target location in a dropdown box 
    foreach ($n in $nsgList) {
        $window.nsgselect.Items.Add($n) | Out-Null
    }
    # Presents Key Vault in the target location in a dropdown box
    foreach ($k in $keyVaultsList) {
        $window.kvselect.Items.Add($k) | Out-Null
    }
    # Declares Array, presents array as string in the Development Virtual Worker dropdown box
    $d = 0..5
    foreach ($d in $d) {
        $window.dvwselect.Items.Add([string]$d) | Out-Null
    }
    # Declares Array, presents array as string in the Production Virtual Worker dropdown box
    $p = 0..10
    foreach ($p in $p) {
        $window.pvwselect.Items.Add([string]$p) | Out-Null
    }
    $response.Result = Show-WPFWindow -window $window
    # Input from dropdown boxes selected by the user are assigned to variables 
    $pfxselect = $window.vmpfx.Text.ToUpper()
    $vnselect = $window.vnselect.SelectedItem
    $nsgselect = $window.nsgselect.SelectedItem
    $kvselect = $window.kvselect.SelectedItem
    $dvwselect = $window.dvwselect.SelectedItem -as [int]
    $pvwselect = $window.pvwselect.SelectedItem -as [int]

    # Each input is verified against either being null or empty or containing a string from the lists developed from the users subscriptions
    if (![string]::isnullorempty($pfxselect)) {
        Write-Host -ForegroundColor Green "Virtual Machine Prefix $pfxselect has been verified"
    } else {
        Write-Host -ForegroundColor Red "Error verifying Virtual Machine Prefix"
        $errorsFound = $true
    }
    if ($vnselect -contains $vnetList) {
        Write-Host -ForegroundColor Green "Virtual Network: $vnselect verified"
        $vnselect = Get-AzVirtualNetwork -Name ($vnselect)
        $errorsFound = $false
    } else {
        Write-Host -ForegroundColor Red "Error verifying selected virtual network"
        $errorsFound = $true
    }
    if ($nsgselect -contains $nsgList) {
        Write-Host -ForegroundColor Green "Network Security Group: $nsgselect verified"
        $nsgselect = Get-AzNetworkSecurityGroup -Name ($nsgselect)
        $errorsFound = $false
    } else {
        Write-Host -ForegroundColor Red "Error verifying selected network security group"
        $errorsFound = $true
    }
    if ($kvselect -contains $keyVaultsList) {
        Write-Host -ForegroundColor Green "Key Vault: $kvselect verified"
        $kvselect = Get-AzKeyVault -VaultName ($kvselect)
        $errorsFound = $false
    } else {
        Write-Host -ForegroundColor Red "Error verifying selected key vault"
        $errorsFound = $true
    }
    if (![string]::isnullorempty($dvwselect)) {
        Write-Host -ForegroundColor Green "Number of Development Virtual Workers verified"
        $errorsFound = $false
    } else {
        Write-Host -ForegroundColor Red "Error verifying number of Development Virtual Workers"
        $errorsFound = $true
    }
    if (![string]::isnullorempty($pvwselect)) {
        Write-Host -ForegroundColor Green "Number of Production Virtual Workers verified"
        $errorsFound = $false
    } else {
        Write-Host -ForegroundColor Red "Error verifying number of Production Virtual Workers"
        $errorsFound = $true
    }
    if ($errorsFound -eq $true) {
        Write-Host -ForegroundColor Green "Errors were found whilst selecting options. Please verify all fields are correct"
    } else {
        Write-Host "All options verified"
    }
} while ($errorsFound -eq $true)

$vm = @()

while ($dvwselect -ne 0) {
    New-Variable -Name ("DVW" + $dvwselect.ToString()) -Value ("DVW" + $dvwselect.ToString())
    $dvw = Get-Variable -Name ("DVW" + $dvwselect.ToString()) -ValueOnly
    $vm += $dvw
    $dvwselect --
}

while ($pvwselect -ne 0) {
    New-Variable -Name ("PVW" + $pvwselect.ToString()) -Value ("PVW" + $pvwselect.ToString())
    $pvw = Get-Variable -Name ("PVW" + $pvwselect.ToString()) -ValueOnly
    $vm += $pvw
    $pvwselect --
}

$stract = New-AzStorageAccount -ResourceGroupName $rglist[0].ResourceGroupName -Name ($pfxselect+"diag").ToLower() -Location $azureLocation.DisplayName -SkuName Standard_LRS
$size = "Standard_B1ms"
foreach ($vm in $vm) {
    deploy-vm -vm $vm -size $size -loc $azureLocation -vn $vnselect -nsec $nsgselect -kv $kvselect.VaultName -str $stract
}

Remove-Item -Path $env:TEMP/new.ps1

Disconnect-AzAccount

# Invoke-AzVMRunCommand -ResourceGroupName $rg.ResourceGroupName -VMName ($pfxselect+$vm) -CommandId 'RunPowerShellScript' -ScriptPath $env:TEMP/new.ps1