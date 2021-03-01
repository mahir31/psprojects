<#  
.SYNOPSIS  
    Automated Solution to adding credentials to Blue Prism Credential Manager.

.DESCRIPTION
    Retrieves Development and Production Worker passwords and adds them to Blue Prism Credential Manager.

.PREREQUISITES
    Powershell Az module is installed - run `Install-Module -Name Az -AllowClobber -Scope CurrentUser` if otherwise
    IE Enhanced Security Configuration is turned off in Server Manager
    Blue Prism 6.10 is installed
    Both Development and Production Connections are configured in Blue Prism

.NOTES  
    Author     : Mahir Ajmal
    Version    : 0.1
#>

function Retrieve-Credential {
    param (
    [parameter(mandatory)]$secretname,
    [parameter(mandatory)]$vaultname
    )
    $secret = Get-AzKeyVaultSecret -VaultName $vaultname -Name $secretname
    $ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret.SecretValue)
    try {
        $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
    }
    return $secretValueText
}

function Add-Credentials {
    param (
    [parameter(mandatory)]$connectionpassword,
    [parameter(mandatory)]$workernames,
    [parameter(mandatory)]$secretlist,
    [parameter(mandatory)]$vaultname,
    [parameter(mandatory)]$dbconname
    )
    $n=0
    foreach ($s in $secretlist) {
        $workercredential = Retrieve-Credential -secretname $s.Name -vaultname $vaultname
        $command = '"C:\Program Files\Blue Prism Limited\Blue Prism Automate\AutomateC.exe" /dbconname ' + $dbconname + ' /user operator ' + $connectionpassword + ' /createcredential "Windows Login: ' + $workernames[$n] + '" "virtual.worker" "' + $workercredential + '" /description "' + $workernames
        $command = cmd.exe /c $command
        Write-Host $command
        $n ++
    }
}

try {
    Connect-AzAccount
    $azureSubscription = (Get-AzSubscription | Sort-Object Name | Out-GridView -Title "Choose your Azure subscription and click OK." -PassThru)
    if ($azureSubscription -ne $null) { Write-host "Switching to Azure subscription: $($azureSubscription.Name)"  -ForegroundColor Green }
    $azureSubscriptionInfo = Select-AzSubscription -SubscriptionId $azureSubscription.Id
} catch {
    "User canceled authentication"
    break
}

$virtualmachines = Get-AzVM
$keyvault = Get-AzKeyVault | where { $_.VaultName -like "*Client*"}
$secretlist = Get-AzKeyVaultSecret -VaultName $keyvault.VaultName

$developmentconnection = retrieve-credential -secretname "RPA-Development-Client" -vaultname $keyvault.VaultName
$productionconnection = retrieve-credential -secretname "RPA-Production-Client" -vaultname $keyvault.VaultName

$devworkernames = @()
$prodworkernames = @()
$devsecretlist = @()
$prodsecretlist = @()

foreach ($m in $virtualmachines) {
    if ($m.Name -like "*dvw*") {
        $devworkernames += $m.Name
        Write-Host "Machine: $($m.Name) queued to be added" -ForegroundColor Green
    }
}

foreach ($m in $virtualmachines) {
    if ($m.Name -like "ProdVW*") {
        $prodworkernames += $m.Name
        Write-Host "Machine: $($m.Name) queued to be added" -ForegroundColor Green
    }
}

foreach ($s in $secretlist) {
    if ($s.Name -like "DevVw*") {
    $devsecretlist += $s
    Write-Host "Credential: $($s.Name) queued to be added" -ForegroundColor Green
    }
}

foreach ($s in $secretlist) {
    if ($s.Name -like "ProdVW*") {
    $prodsecretlist += $s
    Write-Host "Credential: $($s.Name) queued to be added" -ForegroundColor Green
    }
}

$adddevelopmentcredentials = Add-Credentials -connectionpassword $developmentconnection -workernames $devworkernames -secretlist $devsecretlist -vaultname $keyvault.VaultName -dbconname "Development"
$addproductioncredentials = Add-Credentials -connectionpassword $productionconnection -workernames $prodworkernames -secretlist $prodsecretlist -vaultname $keyvault.VaultName -dbconname "Production"
Disconnect-AzAccount
Write-Host "Script has complete running, please check aligned connections and verify credentials have been added" -ForegroundColor Green