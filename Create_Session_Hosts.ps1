param (
    [Parameter(Mandatory=$false)] 
    [String] $ResourceGroupName = "rg-JackChan",
    [Parameter(Mandatory=$false)] 
    [String] $KeyVaultName = "key-avd-lab-001",
    [Parameter(Mandatory=$false)] 
    [String] $Location = "eastasia",
    [Parameter(Mandatory=$false)] 
    [String] $ImageGalleryName = "sigwvdtest",
    [Parameter(Mandatory=$false)] 
    [String] $StorageAccounName = "terraform20211116",
    [Parameter(Mandatory=$false)] 
    [String] $ImageDefinitionName = "sigimage-wvd-eas-prd-fwdgp-ms",
    [Parameter(Mandatory=$false)] 
    [String] $VirtualNetworkName = "vnet-AVD",
    [Parameter(Mandatory=$false)] 
    [String] $SubnetName = "snet-AVD-001",
    [Parameter(Mandatory=$false)] 
    [String] $HostPoolName = "avd-host-pool-004",
    [Parameter(Mandatory=$false)] 
    [String] $VMNamePrefix = "vm-avd-test",
    [Parameter(Mandatory=$false)] 
    [String] $VMSize = "Standard_D2s_v3",
    [Parameter(Mandatory=$false)]
    [Int] $Count = 2
)
Get-Date -Format "HH:mm"
# For VM Creation
$NetworkInterfaceCardPrefix = "nic01-$VMNamePrefix"
$LocalAdminAccount = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'local-admin-username' -AsPlainText
$LocalAdminPassword = ConvertTo-SecureString -String (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'local-admin-password' -AsPlainText) -AsPlainText -Force
$LocalAdminCredentails = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $LocalAdminAccount, $LocalAdminPassword
# For Domain Join Section
$DomainJoinServiceAccount = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'addc-admin-username' -AsPlainText
$DomainJoinServicePassword = ConvertTo-SecureString -String (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'addc-admin-password' -AsPlainText) -AsPlainText -Force
$DomainName = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'addc-domain-name' -AsPlainText
$OUPath = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'addc-ou-path' -AsPlainText
$StorageAccountKey = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'storage-aacount-access-key' -AsPlainText
$DomainJoinTemplateUri = New-AzStorageBlobSASToken `
-Container "template" `
-Blob "joindomain.json" `
-Permission r `
-Context (New-AzStorageContext -StorageAccountName $StorageAccounName -StorageAccountKey $StorageAccountKey) `
-ExpiryTime (Get-Date).AddHours(2.0) -FullUri


$Registered = Get-AzWvdRegistrationInfo -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName
if (-not(-Not $Registered.Token)){$registrationTokenValidFor = (NEW-TIMESPAN -Start (get-date) -End $Registered.ExpirationTime | select Days,Hours,Minutes,Seconds)}
 "Token is valid for:$registrationTokenValidFor"
if ((-Not $Registered.Token) -or ($Registered.ExpirationTime -le (get-date)))
{
    $Registered = New-AzWvdRegistrationInfo -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -ExpirationTime (Get-Date).AddHours(4) -ErrorAction SilentlyContinue
}
$RegistrationToken = $Registered.Token

$InstallWVDAgentURI = @("https://$StorageAccounName.blob.core.windows.net/script/InstallWVDAgent.ps1")
$WVDAgentProtectSettings = @{
    "fileUris" = $InstallWVDAgentURI
    "storageAccountName" = [string]$StorageAccounName
    "storageAccountKey" = [string]$StorageAccountKey
    "commandToExecute" = "powershell -ExecutionPolicy Unrestricted -File InstallWVDAgent.ps1 $RegistrationToken "
}
function CountExistVM {
    $VMCountFromStart = 1
    $VMsLenght = ((Get-AzVM -ResourceGroupName $ResourceGroupName -Name "$VMNamePrefix*").Name).Length

    if ([int]$VMsLenght -eq $null) {
        "No value to change"
    }
    elseif ([int]$VMsLenght -lt 0) {
        "No value to change"
    }
    else {
        $VMCountFromStart = $VMCountFromStart + [int]$VMsLenght 
    }
    return $VMCountFromStart
}

function CountVMNumber {
    $VMList = @()
    $VMNumberPrefix = CountExistVM
    for($i=0; $i -lt $Count; $i++){
        $Name = [String]$VMNamePrefix+"-"+$VMNumberPrefix
        $VMList += $Name
        $VMNumberPrefix++
    }
    return $VMList
}

function WaitingToComplete {
"Waiting to Complete the action"
Get-Job | Wait-Job
Get-Job | Remove-Job 
}

function RemoveExtension($VMList,$ExtenSionName) {

    
}

$VMList = CountVMNumber


# $ImageId = ((Get-AzGalleryImageVersion -ResourceGroupName $ResourceGroupName `
# -GalleryName "sigwvdeasprdfwdgp01" `
# -GalleryImageDefinitionName "sigimage-wvd-eas-prd-fwdgp-ss-dev-tool")[-1]).Id
# $GalleryImageReference = @{Id = $ImageId}

#Create Session Hosts
foreach($VMName in $VMList){
    try {
        $NetworkInterfaceCardName = "nic01-"+[String]$VMName
    
        $ImageDefinition = Get-AzGalleryImageDefinition `
        -GalleryName $ImageGalleryName `
        -GalleryImageDefinitionName $ImageDefinitionName `
        -ResourceGroupName $ResourceGroupName
    
        $SessionHostVirtualNetwork = Get-AzVirtualNetwork -Name $VirtualNetworkName -ResourceGroupName $ResourceGroupName
    
        $SessionHostSubnetID = (Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $SessionHostVirtualNetwork).Id
    
        $NetworkInterfaceCardName = New-AzNetworkInterface -Name $NetworkInterfaceCardName `
        -ResourceGroupName $ResourceGroupName `
        -Location $Location `
        -SubnetId $SessionHostSubnetID
    
        $SessionHostConfig = New-AzVMConfig -VMName $VMName `
        -VMSize $VMSize | `
        Set-AzVMSourceImage -Id $ImageDefinition.Id | `
        Add-AzVMNetworkInterface -Id $NetworkInterfaceCardName.Id | `
        Set-AzVMOperatingSystem -Windows -ComputerName $VMName -Credential $LocalAdminCredentails | `
        Set-AzVMBootDiagnostic -Disable
    
        New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $SessionHostConfig  -AsJob
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }

}

WaitingToComplete
Get-Date -Format "HH:mm"
"To Install Domain Join Extension"

$VMList | ForEach-Object {$String += $_+","}
$VMListString = $String.Substring(0,$String.Length-1)
$DomainJoinTemplateParameterSettings = @{
    "vmList" = [string]$VMListString
    "location" = [string]$Location
    "domainJoinUserName" = [string]$DomainJoinServiceAccount 
    "domainJoinUserPassword" = [SecureString]$DomainJoinServicePassword
    "domainFQDN" = [string]$DomainName
    "ouPath" = [string]$OUPath
}
try {
    New-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -TemplateUri $DomainJoinTemplateUri `
    -TemplateParameterObject $DomainJoinTemplateParameterSettings `
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
    }


Get-Date -Format "HH:mm"
WaitingToComplete
"To Install WVD Extension"
foreach($VMName in $VMList){
    Set-AzVMExtension `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -VMName $VMName `
    -Name "wvdagent" `
    -Publisher "Microsoft.Compute" `
    -ExtensionType "CustomScriptExtension" `
    -TypeHandlerVersion "1.10" `
    -ProtectedSettings $WVDAgentProtectSettings `
    -NoWait
}

Get-Date -Format "HH:mm"
WaitingToComplete
"To Change Static IP for VMs"

$NetworkInterfaceCards = (Get-AzNetworkInterface -Name $NetworkInterfaceCardPrefix* -ResourceGroupName $ResourceGroupName)
foreach($NetworkInterfaceCard in $NetworkInterfaceCards){
    $NetworkInterfaceCard.IpConfigurations[0].PrivateIpAllocationMethod = "Static"
    try {
        Set-AzNetworkInterface -NetworkInterface $NetworkInterfaceCard -AsJob
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
    } 
WaitingToComplete
"All Action Completed"
Get-Date -Format "HH:mm"


# "To Remove Domain Join Extension"
# foreach($VMName in $VMList){
#     try {
#         Start-Job -ScriptBlock {
#             Remove-AzVMExtension `
#             -ResourceGroupName $ResourceGroupName `
#             -VMName $VMName `
#             -Name $ExtenSionName `
#             -Force
#         }
#     }
#     catch {
#         Write-Error -Message $_.Exception
#         throw $_.Exception
#     }
# }