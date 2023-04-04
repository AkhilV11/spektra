Param (
    [Parameter(Mandatory = $true)]
    [string]
    $AzureUserName,

    [string]
    $AzurePassword,

    [string]
    $AzureTenantID,

    [string]
    $AzureSubscriptionID,

    [string]
    $ODLID,

    [string]
    $DeploymentID,

    [string]
    $InstallCloudLabsShadow
)

Start-Transcript -Path C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt -Append
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls" 

#Import Common Functions
$path = pwd
$path=$path.Path
$commonscriptpath = "$path" + "\cloudlabs-common\cloudlabs-windows-functions.ps1"
. $commonscriptpath

# Run Imported functions from cloudlabs-windows-functions.ps1
WindowsServerCommon
InstallCloudLabsShadow $ODLID $InstallCloudLabsShadow
CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID

#Download power Bi desktop

$WebClient = New-Object System.Net.WebClient



$WebClient.DownloadFile("https://download.microsoft.com/download/8/8/0/880BCA75-79DD-466A-927D-1ABF1F5454B0/PBIDesktopSetup_x64.exe","C:\LabFiles\PBIDesktop_x64.exe")



#INstall power Bi desktop

Start-Process -FilePath "C:\LabFiles\PBIDesktop_x64.exe" -ArgumentList '-quiet','ACCEPT_EULA=1'

[Environment]::SetEnvironmentVariable("PBI_enableWebView2Preview","0", "Machine")



Set-ExecutionPolicy -ExecutionPolicy bypass -Force


#download az-copy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/SpektraSystems/CloudLabs-Azure/master/azure-synapse-analytics-workshop-400/artifacts/setup/azcopy.exe" -OutFile "C:\labfiles\azcopy.exe"


#install the AZ module
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name "PSGallery" -Installationpolicy Trusted
Install-Module -Name Az -AllowClobber -Scope AllUsers -Force

#connect to Az account
CD C:\LabFiles

$credsfilepath = ".\AzureCreds.txt"
$creds = Get-Content $credsfilepath | Out-String | ConvertFrom-StringData
$AzureUserName = "$($creds.AzureUserName)"
$AzurePassword = "$($creds.AzurePassword)"
$DeploymentID = "$($creds.DeploymentID)"
$AzureSubscriptionID = "$($creds.AzureSubscriptionID)"
$passwd = ConvertTo-SecureString $AzurePassword -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $AzureUserName, $passwd
$subscriptionId = $AzureSubscriptionID 

Connect-AzAccount -Credential $cred | Out-Null

#fetching the storage account name
$rgName = (Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "ODL*" }).ResourceGroupName
$storageAccounts = Get-AzResource -ResourceGroupName $rgName -ResourceType "Microsoft.Storage/storageAccounts"
$storageName = $storageAccounts | Where-Object { $_.Name -like 'sba*' }
$storageaccountname=$storagename.name
$storage = Get-AzStorageAccount -ResourceGroupName $rgName -Name $storageName.Name
$storageContext = $storage.Context

#create the conatiners
New-AzStorageContainer -Name "input" -Context $storageContext -Permission Blob
New-AzStorageContainer -Name "output" -Context $storageContext -Permission Blob
New-AzStorageContainer -Name "testinput" -Context $storageContext -Permission Blob
New-AzStorageContainer -Name "testoutput" -Context $storageContext -Permission Blob
New-AzStorageContainer -Name "testresult" -Context $storageContext -Permission Blob


#storage copy
$srcUrl = $null
$rgLocation = (Get-AzResourceGroup -Name $rgName).Location
          

$srcUrl = "https://experienceazure.blob.core.windows.net/input?sp=racwdli&st=2023-01-23T08:16:53Z&se=2028-01-30T16:16:53Z&spr=https&sv=2021-06-08&sr=c&sig=QQSqnPuBUHWTp2eh7Yb4PwNEtWoerWGsJgzll%2BIE4jQ%3D"

$destContext = $storage.Context           
$resources = $null


$startTime = Get-Date
$endTime = $startTime.AddDays(2)
$destSASToken = New-AzStorageContainerSASToken  -Context $destContext -Container "input" -Permission rwd -StartTime $startTime -ExpiryTime $endTime
$destUrl = $destContext.BlobEndPoint + "input" + $destSASToken

$srcUrl 
$destUrl

C:\LabFiles\azcopy.exe copy $srcUrl $destUrl --recursive


#Assign contributor role for the Service Principal on the Machine Learning workspace
$rgName = (Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "ODL*" }).ResourceGroupName
$machinelearningAccounts = Get-AzResource -ResourceGroupName $rgName -ResourceType "Microsoft.MachineLearningServices/workspaces"
$machinelearningname = $machinelearningAccounts | Where-Object { $_.Name -like 'loan*' }
$machinelearningaccountname=$machinelearningname.name


$servicePrincipalDisplayName = "https://odl_user_sp_$DeploymentID"
$servicePrincipal = Get-AzADServicePrincipal -DisplayName $servicePrincipalDisplayName
$id =$servicePrincipal.id
$saName="asadatalake"+$DeploymentID
$workspacename= "loanmodel"+$DeploymentID
$saaName="sbadata"+$DeploymentID
$rgname="ODL-manymodels-"+$DeploymentID



#Assigning synapse adminstrator role to synapse workspace
Install-Module AzureAD -Force

Connect-AzureAD -Credential $cred | Out-Null

$id1 = Get-AzureADUser -ObjectId $AzureUserName
$id1=$id1.ObjectId
$id = (Get-AzADServicePrincipal -DisplayName $WorkspaceName).id
$id=$id.get(1)

$id3 = $AzureUserName
New-AzRoleAssignment -Objectid $id -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$RGName/providers/Microsoft.Storage/storageAccounts/$saName" -ErrorAction SilentlyContinue;
New-AzRoleAssignment -SignInName $AzureUserName -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.Storage/storageAccounts/$saName"

New-AzRoleAssignment -SignInName $AzureUserName -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.Storage/storageAccounts/$saaName"
New-AzRoleAssignment -Objectid $id -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$RGName/providers/Microsoft.Storage/storageAccounts/$saaName" -ErrorAction SilentlyContinue;

New-AzRoleAssignment -ObjectID $id -RoleDefinitionName "contributor" -Scope "/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.MachineLearningServices/workspaces/$machinelearningaccountname"
New-AzRoleAssignment -SignInName $id3 -RoleDefinitionName "contributor" -Scope "/subscriptions/$SubscriptionId/resourceGroups/$rgName/providers/Microsoft.Synapse/workspaces/$workspacename"
#Role assignment on synapse workspace for AAD group
New-AzSynapseRoleAssignment -WorkspaceName $workspacename -RoleDefinitionId "6e4bf58a-b8e1-4cc3-bbf9-d73143322b78" -ObjectId $id1
New-AzSynapseRoleAssignment -WorkspaceName $workspacename -RoleDefinitionId "7af0c69a-a548-47d6-aea3-d00e69bd83aa" -ObjectId $id1
New-AzSynapseRoleAssignment -WorkspaceName $workspacename -RoleDefinitionId "c3a6d2f1-a26f-4810-9b0f-591308d5cbf1" -ObjectId $id1

Start-Sleep 600

#downloading synapse pipelines

$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://raw.githubusercontent.com/bhavangowdan/spektra/main/loanmodelling/Clean_Raw_Data_support_live.zip","C:\LabFiles\Clean_Raw_Data_support_live.zip")
#unziping folder
function Expand-ZIPFile($file, $destination)
{
$shell = new-object -com shell.application
$zip = $shell.NameSpace($file)
foreach($item in $zip.items())
{
$shell.Namespace($destination).copyhere($item)
}
}
Expand-ZIPFile -File "C:\LabFiles\Clean_Raw_Data_support_live.zip" -Destination "C:\LabFiles\"

#Extracting the connection string

$connection1= (Get-AzStorageAccount -ResourceGroupName $rgname -Name $saaName).Context
$connectionstring1=$connection1.ConnectionString

(Get-Content -Path "C:\LabFiles\Clean_Raw_Data_support_live\linkedService\link_to_sbadata_storage.json") | ForEach-Object {$_ -Replace '<connectionstring1>', $connectionstring1} | Set-Content -Path "C:\LabFiles\Clean_Raw_Data_support_live\linkedService\link_to_sbadata_storage.json"

$connection2= (Get-AzStorageAccount -ResourceGroupName $rgname -Name $saName).Context
$connectionstring2=$connection2.ConnectionString

(Get-Content -Path "C:\LabFiles\Clean_Raw_Data_support_live\linkedService\loandemo_datalake.json") | ForEach-Object {$_ -Replace '<connectionstring2>', $connectionstring2} | Set-Content -Path "C:\LabFiles\Clean_Raw_Data_support_live\linkedService\loandemo_datalake.json"
(Get-Content -Path "C:\LabFiles\Clean_Raw_Data_support_live\linkedService\loandemo_datalake.json") | ForEach-Object {$_ -Replace 'DID', $DeploymentID} | Set-Content -Path "C:\LabFiles\Clean_Raw_Data_support_live\linkedService\loandemo_datalake.json"

sleep 10

#Running the synapse1 pipline
Set-AzSynapseLinkedService -WorkspaceName $WorkspaceName -Name link_to_sbadata_storage -DefinitionFile "C:\LabFiles\Clean_Raw_Data_support_live\linkedService\link_to_sbadata_storage.json"
Set-AzSynapseLinkedService -WorkspaceName $WorkspaceName -Name loandemo_datalake -DefinitionFile "C:\LabFiles\Clean_Raw_Data_support_live\linkedService\loandemo_datalake.json"

sleep 10

Set-AzSynapseDataset -WorkspaceName $WorkspaceName  -Name SBA_Raw_Data -DefinitionFile "C:\LabFiles\Clean_Raw_Data_support_live\dataset\SBA_Raw_Data.json"
Set-AzSynapseDataset -WorkspaceName $WorkspaceName  -Name SBA_input_data -DefinitionFile "C:\LabFiles\Clean_Raw_Data_support_live\dataset\SBA_input_data.json"
Set-AzSynapseDataset -WorkspaceName $WorkspaceName  -Name NAICS_data -DefinitionFile "C:\LabFiles\Clean_Raw_Data_support_live\dataset\NAICS_data.json"
Set-AzSynapseDataset -WorkspaceName $WorkspaceName  -Name LoanRawData -DefinitionFile "C:\LabFiles\Clean_Raw_Data_support_live\dataset\LoanRawData.json"
Set-AzSynapseDataset -WorkspaceName $WorkspaceName  -Name LoanCuratedData -DefinitionFile "C:\LabFiles\Clean_Raw_Data_support_live\dataset\LoanCuratedData.json"

sleep 10

Set-AzSynapseDataFlow -WorkspaceName $WorkspaceName -Name Clean_Loan_Raw_Data -DefinitionFile "C:\LabFiles\Clean_Raw_Data_support_live\dataflow\Clean_Loan_Raw_Data.json"

sleep 10

Set-AzSynapsePipeline -WorkspaceName $WorkspaceName -Name Clean_Raw_Data -DefinitionFile "C:\LabFiles\Clean_Raw_Data_support_live\pipeline\Clean_Raw_Data.json"

sleep 10

$HeadersInfo = Invoke-AzSynapsePipeline -WorkspaceName $WorkspaceName -PipelineName "Clean_Raw_Data"
$HeadersInfo
$HeadersRunID=$HeadersInfo.RunId

sleep 600

#Running the spark note book

$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://raw.githubusercontent.com/bhavangowdan/spektra/main/loanmodelling/Notebook%201.ipynb","C:\LabFiles\Notebook1.ipynb")
$WebClient.DownloadFile("https://raw.githubusercontent.com/bhavangowdan/spektra/main/loanmodelling/Pipeline%201.json","C:\LabFiles\Pipeline1.json")

(Get-Content -Path "C:\LabFiles\Notebook1.ipynb") | ForEach-Object {$_ -Replace 'DID', $DeploymentID} | Set-Content -Path "C:\LabFiles\Notebook1.ipynb"


sleep 100

Set-AzSynapseNotebook -WorkspaceName $workspacename -Name notebook1 -DefinitionFile "C:\LabFiles\Notebook1.ipynb"

Set-AzSynapsePipeline -WorkspaceName $workspacename -Name pipeline1 -DefinitionFile "C:\LabFiles\Pipeline1.json"


Invoke-AzSynapsePipeline -WorkspaceName $workspacename -PipelineName pipeline1

sleep 600
