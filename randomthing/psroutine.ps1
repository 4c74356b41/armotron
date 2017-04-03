function Do-AlltheStuff {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=0)]
        [string]$resourceGroupName,

        [Parameter(Mandatory=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=1)]
        [ValidateSet("eastasia", "southeastasia", "centralus", "eastus", "eastus2", "westus", "northcentralus",
        "southcentralus", "northeurope", "westeurope", "japanwest", "japaneast", "brazilsouth", "australiaeast",
        "australiasoutheast", "canadacentral", "canadaeast", "uksouth", "ukwest", "westcentralus", "westus2",
        "koreacentral", "koreasouth")]
        [string]$location,

        [Parameter(Mandatory=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=3)]
        [string]$webAppName,

        [Parameter(Mandatory=$false,
            ValueFromPipelineByPropertyName=$true,
            Position=4)]
        [ValidateSet("Free", "Shared", "Basic", "Standard", "Premium")]
        [string]$skuCode = "Free",

        [Parameter(Mandatory=$false,
            ValueFromPipelineByPropertyName=$true,
            Position=5)]
        [ValidateSet(1, 2, 3)]
        [string]$workerCount = "1",

        [Parameter(Mandatory=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=6)]
        [string]$administratorLogin,

        [Parameter(Mandatory=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=7)]
        [string]$administratorPassword,

        [Parameter(Mandatory=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=8)]
        [ValidateScript({$_ -notmatch '\s+' -and $_ -match '[a-zA-Z0-9]+'})] 
        [string]$databaseName,

        [Parameter(Mandatory=$true,
            ValueFromPipelineByPropertyName=$true,
            Position=9)]
        [ValidateScript({$_ -notmatch '\s+' -and $_ -match '[a-zA-Z0-9]+'})] 
        [string]$serverName,

        [string]$repoURL

    )

    # Create credentials object and get locations for stuff
    $cred = ([pscredential]::new($administratorLogin,(ConvertTo-SecureString -String $administratorPassword -AsPlainText -Force)))
    $location2 = Get-AlternateLocation $location
    $location3 = Get-AlternateLocation $location

    # Create resource group
    $rg = New-AzureRmResourceGroup -Name $resourceGroupName -Location $location

    # Start web app routine
    $app = New-AzureRmAppServicePlan -Location $location -Tier $skuCode -NumberofWorkers $workerCount `
        -ResourceGroupName $rg.ResourceGroupName -Name $rg.ResourceGroupName
    $webapp1 = New-AzureRmWebApp -ResourceGroupName $rg.ResourceGroupName -Name $($webAppName + '1') -AppServicePlan $app.Id -Location $location
    $webapp2 = New-AzureRmWebApp -ResourceGroupName $rg.ResourceGroupName -Name $($webAppName + '2') -AppServicePlan $app.Id -Location $location2

    # "Number of apps in App Service Plan"
    (Get-AzureRmAppServicePlan -ResourceGroupName $rg.ResourceGroupName -Name $rg.ResourceGroupName).NumberOfSites

    Start-Process $("http://" + $webapp1.EnabledHostNames[0])
    Start-Process $("http://" + $webapp2.EnabledHostNames[0])

    Write-Host -ForegroundColor Green "WebApp Done"

    # Start SQL routine
    Get-AzureRmResourceProvider -ProviderNamespace "Microsoft.Sql"
    
    # SQL fails for no reason (sometimes), so we'd like to retry
    # Pretty hackish workaround, but we are using a try\catch! hooray!
    for ($i = 1; $i -lt 4; $i++) { 
        try {
            Set-Variable -Name $('srv' + $i) -Value (New-AzureRmSqlServer -ServerName $($serverName + $i) -SqlAdministratorCredentials $cred `
                -Location $location -ResourceGroupName $rg.ResourceGroupName -ErrorAction Stop)
        }
        catch {
            Start-Sleep 15
            Set-Variable -Name $('srv' + $i) -Value (New-AzureRmSqlServer -ServerName $($serverName + 'retry' + $i) -SqlAdministratorCredentials $cred `
                -Location $location -ResourceGroupName $rg.ResourceGroupName)
        }
        # Lets create firewall rules while we are here
        New-AzureRmSqlServerFirewallRule -ResourceGroupName $rg.ResourceGroupName `
            -ServerName (Get-Variable -Name $('srv' + $i)).value.ServerName -FirewallRuleName "aaa" `
            -StartIpAddress "0.0.0.0" -EndIpAddress "255.255.255.255" | Out-Null

        "Server #$i done!"
    }

    Write-Host -ForegroundColor Green "SQL Done"

    # Create storage account for bacpac export\import
    $storage = New-AzureRmStorageAccount -ResourceGroupName $rg.resourceGroupName -Location $location -SkuName Standard_LRS `
        -Name ($str = $databaseName + (Get-Random)).Substring(0, [math]::Min(20,$str.Length)).ToLower()
    New-AzureStorageContainer -Name 'qaz' -Context $storage.Context | Out-Null

    # Create and Copy DB
    $db = New-AzureRmSqlDatabase -DatabaseName $databaseName -Edition Basic -ServerName $srv1.ServerName `
        -ResourceGroupName $rg.ResourceGroupName
    New-AzureRmSqlDatabaseCopy -DatabaseName $databaseName -ServerName $srv1.ServerName `
        -ResourceGroupName $rg.ResourceGroupName -CopyResourceGroupName $rg.ResourceGroupName `
        -CopyServerName $srv2.ServerName -CopyDatabaseName $databaseName | Out-Null

    Write-Host -ForegroundColor Green "Databases Done"

    # Notification Hub
    New-AzureRmResourceGroupDeployment -ResourceGroupName $rg.resourceGroupName -Name 'Notification-Hub' `
        -TemplateUri 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/101-notification-hub/azuredeploy.json' `
        -namespaceName ($str = $databaseName + (Get-Random)).Substring(0, [math]::Min(20,$str.Length)).ToLower() -Location $location

    # Export Stuff
    $key = (Get-AzureRmStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storage.StorageAccountName)[0].Value
    $exportRequest = New-AzureRmSqlDatabaseExport -DatabaseName $db.DatabaseName -ServerName $db.ServerName `
        -StorageKeyType StorageAccessKey -StorageKey $key -AdministratorLogin $administratorLogin `
        -AdministratorLoginPassword (ConvertTo-SecureString -Force -AsPlainText $administratorPassword) `
        -StorageUri ('https://' + $storage.StorageAccountName +'.blob.core.windows.net/qaz/bacpac.bacpac') `
        -ResourceGroupName $resourceGroupName

    $exportRequest

    # Wait for export to finish
    while ((Get-AzureRmSqlDatabaseImportExportStatus -OperationStatusLink $exportRequest.OperationStatusLink).Status -ne "Succeeded") {
        Start-Sleep 30
        "Waiting 30 seconds more for export to finish"
    }

    # Import Stuff
    $importRequest = New-AzureRmSqlDatabaseImport -DatabaseName $db.DatabaseName -Edition Basic -ServerName $srv3.ServerName `
        -StorageUri ('https://' + $storage.StorageAccountName + '.blob.core.windows.net/qaz/bacpac.bacpac') `
        -AdministratorLogin $administratorLogin -StorageKeyType StorageAccessKey -StorageKey $key `
        -AdministratorLoginPassword (ConvertTo-SecureString -Force -AsPlainText $administratorPassword) `
        -ResourceGroupName $rg.resourceGroupName -ServiceObjectiveName basic -DatabaseMaxSizeBytes 2000000

    Get-AzureRmSqlDatabaseImportExportStatus -OperationStatusLink $importRequest.OperationStatusLink

    Write-Host -ForegroundColor Green "All Done"

}

# $location2 and $location3 can sometimes collide, but its not worth the additional check
function Get-AlternateLocation($location) {
    do {
        $loc = "eastasia", "southeastasia", "centralus", "eastus", "eastus2", "westus", "northcentralus",
        "southcentralus", "northeurope", "westeurope", "japanwest", "japaneast", "brazilsouth", "australiaeast",
        "australiasoutheast", "canadacentral", "canadaeast", "uksouth", "ukwest", "westcentralus", "westus2",
        "koreacentral", "koreasouth" | Get-Random  
    } while ($loc -eq $location)
    $loc
}