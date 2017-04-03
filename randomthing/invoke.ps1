function Last-Task {

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

    $params = @{
        "administratorLogin" = $administratorLogin
        "administratorLoginPassword" = (Convertto-SecureString -Force -AsPlainText $administratorPassword)
        "databaseName" = $databaseName
        "sqlServerName" = $serverName
        "siteName" = $webAppName
        "hostingPlanName" = $($webAppName + '-Plan')
        "location" = $location
        "repoURL" = $repoURL
    }

    $rg = New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
    New-AzureRmResourceGroupDeployment -ResourceGroupName $rg.resourceGroupName -Name 'WebApp' `
    -TemplateFile _.json @params
}