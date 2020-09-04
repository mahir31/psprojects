Connect-AzAccount

New-Item -Path "C:\" -Name "new.ps1" -ItemType "file" -Value "if ((Test-path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL3.0') -eq 'True') { } else {
New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols' -Name 'SSL 3.0' 
New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0' -Name 'Client' 
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client' -Name 'DisabledByDefault' -Value '1' -PropertyType 'DWORD' 
New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0' -Name 'Server' 
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server' -Name 'Enabled' -Value '0' -PropertyType 'DWORD'
}" 

# select subscription
$AzureSubscription = (Get-AzSubscription | Sort Name | Out-GridView -Title "Choose your Azure subscription and click OK." -PassThru)
Write-host "Switching to Azure subscription: $($AzureSubscription.Name)"  -ForegroundColor Green ; 
$AzureSubscriptionInfo = Select-AzSubscription -SubscriptionId $AzureSubscription.Id

$scriptblock = {
Invoke-AzVMRunCommand -ResourceGroupName $args[0] -VMName $args[1] -CommandId 'RunPowerShellScript' -ScriptPath C:\new.ps1
}

$GetVM = Get-AzVM | Sort Name | Out-GridView -Title "Choose your Azure Virtual Machines and click OK." -PassThru

foreach ($VM in $GetVM){
    $RGName = $VM.ResourceGroupName
    $vmName = $VM.Name
    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList @($RGName,$vmName)
    }

"Disabling SSL 3.0 on the selected VMs..."

Get-Job | Wait-Job

remove-item -Path "C:\new.ps1"

disconnect-AzAccount