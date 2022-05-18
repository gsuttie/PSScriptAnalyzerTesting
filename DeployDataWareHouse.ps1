# Script for creating resources 
#az account set --subscription "e8be867a-93cd-4908-8e53-e06af2504a25"
#az storage account create --name dwnijhuisstor --resource-group rg-dwnijhuis --location westeurope --sku Standard_LRS

#Run this once az extension add --name account

#Example Run - .\DeployDataWareHouse.ps1 -environmentName development -subscriptionName 'Microsoft Azure Sponsorship' -location 'West Europe' -subscriptionId e8be867a-93cd-4908-8e53-e06af2504a25

<# 
 Author: Gregor Suttie
 DataWarehouse Script for customer 
 
 Requirements: 
 -Azure CLI
 Usage: 
 Description: 
#>

[CmdletBinding(DefaultParametersetName='None')] 
param(
   [string] [Parameter(Mandatory = $true)] $environmentName = "production",
   [string] [Parameter(Mandatory = $true)] $subscriptionName = "Microsoft Azure (nijhuisnl): #1025392",
   [string] [Parameter(Mandatory = $true)] $subscriptionId = "ad0442f8-00a4-4cdd-b235-705f0453a640",
   [string] [Parameter(Mandatory = $false)] $tagValue = "DW",
   [string] [Parameter(Mandatory = $false)] $location = "West Europe",

   <# Deploy switches #>
   [switch] $EnsureResourceGroups,
   [switch] $EnsureLogAnalytics,
   [switch] $EnsureKeyVault,
   [switch] $EnsureAzureSQLServer,
   [switch] $azurePolicy,
   [switch] $CreateStorageAccount,
   [switch] $CreateDataLakeStorageAccount,
   [Parameter(ParameterSetName='SQL')][switch] $CreateAzureSQLServer,
   [switch] $CreateAzureSQLServerDatabase,
   [switch] $cleanup
)


$customerName = 'nijhuis'

<# Resource Groups #>
$resourceGroupNameDW = "rg-dw-$environmentName"
$resourceGroupNameMonitoring = "rg-monitoring-$environmentName"
$resourceGroupNameKV = "rg-kv-$environmentName"
$monitoringWorkspaceName = "wsdw$environmentName"

<# Keyvault variables #>
$keyvaultName = "kv-$customerName-$environmentName"

<# storage Account Names #>
$storageprefix = 'dwstor'
$storageDataLakeprefix = 'dwstordl'
$storageSku = 'Standard_LRS'


<# Azure SQl Details #>
$servername = "$customerName-sqlServer-$environmentName"
$database = "$customerName-$environmentName"

<# Azure Data Factory Details #>
$dataFactoryName = "df-$environmentName-$customerName"

<# Azure DataBricks Details #>
$databricksName = "$($customerName)adbws1"

<# Set Subscription #>
az account set --subscription $subscriptionName

<# DEPLOYMENT - NO HARDCODED VALUES FROM HERE PLEASE #>
az tag create --name Environment --output none 

$location = "west europe"

function Ensurepermissions 
{
    Write-Host "Checking you have the right permissons to deploy the resources..." -ForegroundColor Blue
    $user = az ad signed-in-user show --query objectId -o tsv
    $subid = az account show --query id -o tsv
    $cspCheck = az account subscription show --id $subid --query subscriptionPolicies.quotaId -o tsv 2> $null
    if ($cspCheck -like "*CSP*")
    {
    $userperms = az role assignment list --assignee $user --include-inherited --output json --query '[].{roleDefinitionName:roleDefinitionName}' | convertFrom-Json
    if ($userperms.roleDefinitionName -contains 'Owner' -or $userperms.roleDefinitionName -contains 'Contributor' -or $userperms.roleDefinitionName -like 'CoAdministrator')
    {
    Write-host "  You have the correct permissions." -ForegroundColor Green
    }
    else
    { 
    Write-Host "  You do not have the correct permissions to create the resources. Please make sure you have contributer permissions on the subscription." -ForegroundColor Red
    break
    }
    }
    else
    {
    $userperms = az role assignment list --assignee $user --include-classic-administrators --include-inherited --output json --query '[].{roleDefinitionName:roleDefinitionName}' | convertFrom-Json
    if ($userperms.roleDefinitionName -contains 'Owner' -or $userperms.roleDefinitionName -contains 'Contributor' -or $userperms.roleDefinitionName -like 'CoAdministrator')
    {
    Write-host "  You have the correct permissions." -ForegroundColor Green
    }
    else
    { 
    Write-Host "  You do not have the correct permissions to create the resources. Please make sure you have contributer permissions on the subscription." -ForegroundColor Red
    break
    }
    }
}

function CreateResourceGroups($resourceGroupName)
{
    az group create --name $resourceGroupName --location $location --output none  
    az group update --resource-group $resourceGroupName --tags Environment=$tagValue --output none 
}


function EnsureResourceGroups
{
    # Prepare resource groups
    Write-Host "Checking if resource group '$resourceGroupNameDW' exists..." -ForegroundColor Blue
    $resourceGroup1 = az group exists --resource-group $resourceGroupNameDW
    if($resourceGroup1 -eq "false")
    {
        Write-Host "  resource group doesn't exist, creating a new one..." -ForegroundColor Yellow
        CreateResourceGroups -resourceGroupName $resourceGroupNameDW
        if (!$?) {
            Write-Host "  Something went wrong. Please check the error and try again." -ForegroundColor Red
            break   
        }
        else {
        Write-Host "  $resourceGroupNameDW resource group created." -ForegroundColor Green
        }
    }
    else
    {
        Write-Host "  resource groups already exists." -ForegroundColor Yellow
    }
    Write-Host "Checking if resource group '$resourceGroupNameMonitoring' exists..." -ForegroundColor Blue
    $resourceGroup2 = az group exists --resource-group $resourceGroupNameMonitoring
    if($resourceGroup2 -eq "false")
    {
        Write-Host "  resource group doesn't exist, creating a new one..." -ForegroundColor Yellow
        CreateResourceGroups -resourceGroupName $resourceGroupNameMonitoring 
        if (!$?) {
            Write-Host "  Something went wrong. Please check the error and try again." -ForegroundColor Red
            break   
        }
        else {
        Write-Host "  $resourceGroupNameMonitoring resource group created." -ForegroundColor Green
        }
    }
    else
    {
        Write-Host "  resource groups already exists." -ForegroundColor Yellow
    }
    Write-Host "Checking if resource group '$resourceGroupNameKV' exists..." -ForegroundColor Blue
    $resourceGroup4 = az group exists --resource-group $resourceGroupNameKV
    if($resourceGroup4 -eq "false")
    {
        Write-Host "  resource group doesn't exist, creating a new one..." -ForegroundColor Yellow
        CreateResourceGroups -resourceGroupName $resourceGroupNameKV
        if (!$?) {
            Write-Host "  Something went wrong. Please check the error and try again." -ForegroundColor Red
            break   
        }
        else {
        Write-Host "  $resourceGroupNameKV resource group created." -ForegroundColor Green
        }
    }
    else
    {
        Write-Host "  $resourceGroupNameKV resource groups already exists." -ForegroundColor Yellow
    }
}

<# Deploy Log analytics resource for monitoring #>
function DeployLoganalytics
{
    az monitor log-analytics workspace create `
        --resource-group $resourceGroupNameMonitoring `
        --workspace-name $monitoringWorkspaceName `
        --sku PerGB2018 `
        --location $location `
        --tags Environment=$tagValue `
        --output none `
        2> $null

        if (!$?) {
            Write-Host "  Something went wrong. Please check the error and try again." -ForegroundColor Red
            break   
        }
}

function EnsureLoganalytics
{
    # Prepare Log Analytics
    Write-Host "Checking if Loganalytics workspace '$monitoringWorkspaceName' exists..." -ForegroundColor Blue
    $la = az monitor log-analytics workspace show --resource-group $resourceGroupNameMonitoring --workspace-name $monitoringWorkspaceName 2> $null
    if($la -eq $null)
    {
        Write-Host "  Loganalytics Workspace doesn't exist, creating a new one..." -ForegroundColor Yellow
        DeployLoganalytics
        Write-Host "  Loganalytics Workspace created." -ForegroundColor Green
    }
    else
    {
        Write-Host "  $monitoringWorkspaceName Loganalytics Workspace already exists." -ForegroundColor Yellow
    }
}


function EnsureKeyVault
{
    # properly create a new Key Vault
    # KV must be enabled for deployment (last parameter)
    Write-Host "Checking if Key Vault '$keyvaultName' exists..." -ForegroundColor Blue
    $keyVault = az keyvault show --name $keyvaultName 2> $null
    if($keyVault -eq $null)
    {
        Write-Host "  key vault doesn't exist, creating a new one..." -ForegroundColor Yellow
        az keyvault create --name $keyvaultName --resource-group $resourceGroupNameKV --location $Location --tags Environment=$tagValue --output none 2> $null
        if(!$?)
        {
            Write-Host "Key vault has been soft deleted to reuse this keyvault you will need to purge it first using." -ForegroundColor Red
            Write-Host "az keyvault purge --name $keyvaultName" -ForegroundColor Yellow
            Write-Host "If you get an error when trying to purge make sure the account you are using has the permissions to purge."
            Write-Host "Once the purge has been completed please re-run using the same command. `n If you have tried purgeing the Key Vault check the error and try again." -ForegroundColor Red
            break
        }  
            Write-Host "  $keyvaultName Key Vault Created and enabled for deployment." -ForegroundColor Green
    }
    else
    {
        Write-Host " $keyvaultName key vault already exists." -ForegroundColor Yellow
    }
}

function CreateStorageAccount
{
    $randomstorageaccountname = -join ((48..57) + (97..122) | Get-Random -Count 32 | % {[char]$_})
    $randomstorageaccountname = $storageprefix +  $environmentName + $randomstorageaccountname
    $randomstorageaccountname = $randomstorageaccountname.SubString(0,23)

    Write-Host "  Storage Account name to be used $randomstorageaccountname" -ForegroundColor Yellow

    az storage account create --name $randomstorageaccountname --resource-group $resourceGroupNameDW --location $location  --sku $storageSku --tags Environment=$tagValue --output none 
}

function CreateDataLakeStorageAccount
{
    $randomdlstorageaccountname = -join ((48..57) + (97..122) | Get-Random -Count 32 | % {[char]$_})
    $randomdlstorageaccountname = $storageDataLakeprefix +  $environmentName + $randomdlstorageaccountname
    $randomdlstorageaccountname = $randomdlstorageaccountname.SubString(0,23)

    Write-Host "  Data Lake Storage Account name to be used $randomdlstorageaccountname" -ForegroundColor Yellow

    az storage account create --name $randomdlstorageaccountname --resource-group $resourceGroupNameDW --kind StorageV2 --hns --tags Environment=$tagValue --output none
}

function EnsureAzureSQLServer
{
    # Prepare Azure SQL Server
    Write-Host "Checking if Azure SQL Server '$servername' exists..." -ForegroundColor Blue
    $as = az sql server show --resource-group $resourceGroupNameDW --name $servername 2> $null
    
    if($as -eq $null)
    {
        Write-Host "  Azure SQL Server doesn't exist, creating a new one..." -ForegroundColor Yellow
        CreateAzureSQLServer
        Write-Host "  Azure SQL Server created." -ForegroundColor Green
    }
    else
    {
        Write-Host "  '$servername' Azure SQL Server already exists." -ForegroundColor Yellow
    }
}

function CreateAzureSQLServer {
   param(
   [string] [Parameter(ParameterSetName='SQL', Mandatory = $true)] $sqlserverlogin = "sqlserveradmin",
   [string] [Parameter(ParameterSetName='SQL', Mandatory = $true)] $sqlserverpassword
   )

    Write-Host "Creating $servername in $location..." -ForegroundColor Yellow
    az sql server create --name $servername --resource-group $resourceGroupNameDW --location "$location" --admin-user $sqlserverlogin --admin-password $sqlserverpassword --output none

    if (!$?)
    {
        Write-Host "  Something went wrong creating the Azure SQL Server - Please check the error and try again." -ForegroundColor Red
        break   
    }
}

function EnsureAzureSQLServerDatabase {

    # Prepare Azure SQL Server Database
    Write-Host "Checking if Azure SQL Server Database '$database' exists..." -ForegroundColor Blue

    $asdb = az sql db show --resource-group $resourceGroupNameDW --server $servername --name $database 2> $null

    if($asdb -eq $null)
    {
        Write-Host " Azure SQL Server Database doesn't exist, creating a new one..." -ForegroundColor Yellow
        CreateAzureSQLServerDatabase
        Write-Host "  Azure SQL Server Database created." -ForegroundColor Green
    }
    else
    {
        Write-Host " Azure SQL Server Database '$database' already exists." -ForegroundColor Yellow
    }
}

function CreateAzureSQLServerDatabase {

    Write-Host "Creating $database on $servername..." -ForegroundColor Yellow
    az sql db create --resource-group $resourceGroupNameDW --server $servername --name $database --edition GeneralPurpose --family Gen5 --capacity 2 --zone-redundant false --tags Environment=$tagValue --output none # zone redundancy is only supported on premium and business critical service tiers 

    if (!$?)
    {
        Write-Host "  Something went wrong creating the Azure SQL Server Database - Please check the error and try again." -ForegroundColor Red
        break   
    }

    Write-Host "  $servername Created ." -ForegroundColor Green
}


function EnsureAzureDataFactory
{
    # properly create a new Azure Data Factory
    Write-Host "Checking if Azure Data Factory '$dataFactoryName' exists..." -ForegroundColor Blue
    az extension add --name datafactory 2> $null

    $df = az datafactory factory show --factory-name $dataFactoryName --resource-group $resourceGroupNameDW 2> $null

    if($df -eq $null)
    {
        
        Write-Host " Creating $dataFactoryName in $location" -ForegroundColor Yellow
        az datafactory factory create --location "$location" --name $dataFactoryName --resource-group $resourceGroupNameDW --tags Environment=$tagValue 2> $null --output none 
    }
    else
    {
        Write-Host " $dataFactoryName Azure Data Factory already exists." -ForegroundColor Yellow
    }
  
}

function EnsureAzureDataBricks
{
    # properly create a new Azure DataBricks
    Write-Host "Checking if Azure DataBricks '$databricksName' exists..." -ForegroundColor Blue
    
    $db = az databricks workspace show --resource-group $resourceGroupNameDW --name $databricksName

    if($db -eq $null)
    {
        Write-Host " Creating $databricksName in $location" -ForegroundColor Yellow
        az databricks workspace create --resource-group $resourceGroupNameDW --name $databricksName --location $location --sku standard
    }
    else
    {
        Write-Host " $databricksName Azure Data Factory already exists." -ForegroundColor Yellow
    }
  
}

function Cleanup
{
    Write-Host "Cleaning up...!" -ForegroundColor Magenta
    az group delete --name $resourceGroupNameDW --no-wait  --yes
    az group delete --name $resourceGroupNameMonitoring --no-wait --yes
    az group delete --name $resourceGroupNameKV --yes
    az keyvault purge --name $keyvaultName --no-wait
    break
}


# Run section
if ($cleanup) {
    Cleanup
}


$starttime = [System.DateTime]::Now
Ensurepermissions
EnsureResourceGroups
EnsureLoganalytics
EnsureKeyVault
CreateStorageAccount
CreateDataLakeStorageAccount
EnsureAzureSQLServer
EnsureAzureSQLServerDatabase
EnsureAzureDataFactory
EnsureAzureDataBricks


if  ($EnsureResourceGroups) {
    EnsureResourceGroups
}

if  ($EnsureLoganalytics) {
    EnsureLoganalytics
}

if  ($EnsureKeyVault) {
    EnsureKeyVault
}

if  ($EnsureAzureSQLServer) {
    EnsureAzureSQLServer
}



$endtime = [System.DateTime]::Now
$duration = $endtime -$starttime
Write-Host ('This deployment took : {0:mm} minutes {0:ss} seconds' -f $duration) -BackgroundColor Yellow -ForegroundColor Magenta

#Example Run - .\DeployDataWareHouse.ps1 -environmentName production -subscriptionName 'Microsoft Azure (nijhuisnl): #1025392' -location 'West Europe' -subscriptionId ad0442f8-00a4-4cdd-b235-705f0453a640


#Todo EnsureAzureSQLServerDatabase
#add in check for sql server and the sql server database
#