#region Parameters
Param(
#Resource Group where resources are located - if need to filter to a specifc RG instead of the complete subscription
    [Parameter(Mandatory=$false)]
    $rgazresources,

#Resource type - if need to filter to a specific resource type instead of running for all resource types
    [Parameter(Mandatory=$false)]
    $azrestype,

#Location of CSV and parameter.json files
    [Parameter(Mandatory=$true)]
    $fileslocation,

#Mandatory - Resource Group where the action group is located
    [Parameter(Mandatory=$true)]
    $rgactiongroup,

#Mandatory - Action Group name
    [Parameter(Mandatory=$true)]
    $actiongroupname
)
#endregion Parameters

$csvpath = "$psscriptroot\$fileslocation\azure_monitoring.csv"
$azuremonitor = Import-Csv $csvpath | Where-Object {$_.'Enable for monitoring' -eq 'yes'}

$erroractionpreference = [System.Management.Automation.ActionPreference]::Stop

Try
{
    $alertgroup = Get-AzActionGroup -ResourceGroupName $rgactiongroup -Name $actiongroupname
    $actiongroupid = $alertgroup.Id
    Write-Host "Alert group Id" $alertgroup.Id "." -ForegroundColor Green -BackgroundColor Black

}
Catch
{
    Write-Host "The action group you have defined has not been found" -ForegroundColor Red -BackgroundColor Black
    Throw
}

If($azuremonitor.count -eq 0)
{
    Write-Host "No resource types have been enabled for monitoring. Please update the CSV file." -ForegroundColor Red -BackgroundColor Black
    Throw
}
If (($rgazresources) -or ($azrestype))
{
    Try
    {
        Get-AzResourceGroup -Name $rgazresources
    }
    Catch
    {
        Write-Host "The resource group you have defined in the parameter is not found" -ForegroundColor Red -BackgroundColor Black
        Throw
    }

    If ($azuremonitor -match $azrestype)
    {

    }
    Else
    {
        Write-Host "The resource type you have defined in the parameter is not enabled for monitoring" -ForegroundColor Red -BackgroundColor Black
        Throw
    }
}
$azrestypemonitoring = @()
ForEach ($csvrow in $azuremonitor)
{
    $aztype = $csvrow.'Resource Type'
    $azrestypemonitoring = $azrestypemonitoring + $aztype
}
$azrestypemonitoring = $azrestypemonitoring | Select-Object -Unique
 Write-Host "Resource type for monitoring" $azrestype "enabled for monitoring"  -ForegroundColor White -BackgroundColor Black

If ((!$rgazresources) -and (!$azrestype))
{
    Write-Host "Setting alert for all resources type enabled for monitoring in the source CSV for the entire subscription" -ForegroundColor Green -BackgroundColor Black
    Try
    {
        $azresources = Get-AzResource | Where {$_.ResourceType -in $azrestypemonitoring} | Select-Object -Property ResourceId,Name,ResourceType,Tags,ResourceGroupName
    }
    Catch
    {
        $_.Exception.Message
    }
}
If ($azrestype)
{
    If ($azrestypemonitoring -match $azrestype)
    {
        Write-Host "Resource type" $azrestype "enabled for monitoring"
        $threshold = $azresource.Tags.$aztagname
    }
    Else
    {
        Write-Host "Resource type" $azrestype "not enabled for monitoring. Please change your paramater or CSV file to enable monitoring." -ForegroundColor Red -BackgroundColor Black
        Exit
    }
}
#If both resource group and resoure type parameters provided
If (($rgazresources) -and ($azrestype))
{
    Write-Host "Setting alert for specific resource type $azrestype within a specific resource group $rgazresources" -ForegroundColor Green -BackgroundColor Black
    Try
    {
        $azresources = Get-AzResource -ResourceGroupName $rgazresources -ResourceType $azrestype | Where {$_.ResourceType -in $azrestypemonitoring} | Select-Object -Property ResourceId,Name,ResourceType,Tags,ResourceGroupName
    }
    Catch
    {
        $_.Exception.Message
    }
}
If ($azrestype)
{
    Write-Host "Setting alert for specific resource type for the entire subscription" -ForegroundColor Green -BackgroundColor Black
    Try
    {
        $azresources = Get-AzResource -ResourceType $azrestype | Where {$_.ResourceType -in $azrestypemonitoring} | Select-Object -Property ResourceId,Name,ResourceType,Tags,ResourceGroupName
    }
    Catch
    {
        $_.Exception.Message
    }
}

If ($rgazresources)
{
    Write-Host "Setting alert for all  resource type within a specific resource group $rgazresources" -ForegroundColor Green -BackgroundColor Black
    Try
    {
        $azresources = Get-AzResource -ResourceGroupName $rgazresources | Where {$_.ResourceType -in $azrestypemonitoring} | Select-Object -Property ResourceId,Name,ResourceType,Tags,ResourceGroupName
    }
    Catch
    {
        $_.Exception.Message
    }
}

ForEach ($azresource in $azresources)
{
    Write-Host "Creating Metric for" $azresource.ResourceType -ForegroundColor Green -BackgroundColor Black

    $azresourceid = $azresource.ResourceId
    $azresourcename = $azresource.Name
    $azresourcetype = $azresource.ResourceType
    $azresourcetags = $azresource.Tags
    $azresourcetagskeys = $azresource.Tags.Keys
    $azresourcergname = $azresource.ResourceGroupName

    $azmonitorscsv = $azuremonitor | Where-Object {$_.'Target Name' -eq $azresourcename}

    ForEach ($azmonitorcsv in $azmonitorscsv)
    {
        $aztagname = $azmonitorcsv.'Tag Name'
        If (($azresourcetagskeys -match $aztagname) -and ($aztagname))
        {
           Write-Host "Tag" $aztagname "found for resource" $azresourcename  -ForegroundColor Green -BackgroundColor Black
           $threshold = $azresource.Tags.$aztagname
        }
        Else
        {
            $threshold = $azmonitorcsv.Threshold
        }

        If (!($azmonitorcsv.'Alert Description'))
        {
            $alertdescription = $azmonitorcsv.Description
        }
        Else
        {
            $alertdescription = $azmonitorcsv.'Alert Description'
        }

        $metricname = $azmonitorcsv.Metric
        # $alertname = $azresourcename + '-' + $metricname
        # If ($alertname -like '*/*')
        # {
        #     $alertname = $alertname -replace ('/','-')
        # }
        $alertname = $azmonitorcsv.'Alert Name'

        If($azresource.ResourceType -eq "Microsoft.Sql/servers/databases")
        {
            $templatefilepath = "$psscriptroot\template_2015-01-01.json"
            $parametersfilepath = "$psscriptroot\$fileslocation\parameters_2015-01-01.json"
        }
        Else
        {
            $templatefilepath = "$psscriptroot\template_2019-04-01.json"
            $parametersfilepath = "$psscriptroot\$fileslocation\parameters_2019-04-01.json"
        }

            $paramfile = Get-Content $parametersfilepath -Raw | ConvertFrom-Json
            $paramfile.parameters.alertName.value = $alertname
            $paramfile.parameters.alertDescription.value = $alertdescription
            $paramfile.parameters.metricName.value = $metricname
            $paramfile.parameters.metricNamespace.value = ($azmonitorcsv.'Resource Type')
            $paramfile.parameters.resourceId.value = $azresourceid
            $paramfile.parameters.threshold.value = $threshold
            $paramfile.parameters.actionGroupId.value = $actiongroupid
            $paramfile.parameters.timeAggregation.value = $azmonitorcsv.'Aggregation Time'
            $paramfile.parameters.operator.value = $azmonitorcsv.Operator
            $paramfile.parameters.alertSeverity.value = [int]($azmonitorcsv.Severity)
            $paramfile.parameters.evaluationFrequency.value = $azmonitorcsv.'Eval Frequency'
            $paramfile.parameters.windowSize.value = $azmonitorcsv.'Window Size'

        $updatedjson = $paramfile | ConvertTo-Json
        $updatedjson > $parametersfilepath

        $deploymentname = $alertname
        If ($deploymentname -like '* *')
        {
            $deploymentname = $deploymentname -replace (' ','-')
        }
        If ($deploymentname -like '*/*')
        {
            $deploymentname = $deploymentname -replace ('/','-')
        }
        If ($deploymentname.Length -ge 64)
        {
            $deploymentname = $deploymentname.Substring(0,64) 
        }

        Write-Host "Deploy monitoring alert" $azmonitorcsv.'Metric Display Name' "on resource" $azresourcename "with threshold value set to" $threshold -ForegroundColor Green -BackgroundColor Black
        New-AzResourceGroupDeployment -Name $deploymentname -ResourceGroupName $azresourcergname -TemplateFile $templatefilepath -TemplateParameterFile $parametersfilepath
    }
}