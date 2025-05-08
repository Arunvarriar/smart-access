#This script is used to update all the user ids from the Smart Access Manager extension, either to Basic or Basic + TestPlan.
#Downgrade to Basic will happen on a regular schedule.
#Upgrade to Basic + Test Plans will be a backup plan, in case there is an issue with the extension or the associated azure function, to unblock people.

param (
    [Parameter(Mandatory=$true)]    #provide the name of the azure devops organization
    [string] $accountName = "",

    [Parameter(Mandatory=$true)]    #PAT that has access to modify user entitlements
    [string] $pat = "",

    [Parameter(Mandatory=$true)]    #"upgrade" to upgrade all approved users to Basic + Test Plan
    [string] $operation = ""        #"downgrade" to downgrade all approved users back to Basic


    )

# Create the AzureDevOps auth header
$base64authinfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$vstsAuthHeader = @{"Authorization"="Basic $base64authinfo"}
$allHeaders = $vstsAuthHeader + @{"Content-Type"="application/json"; "Accept"="application/json"}
$patchHeaders = $vstsAuthHeader + @{"Content-Type"="application/json-patch+json"; "Accept"="application/json"}
$UpgradedLicenses=@()
#upgrade or downgrade user license based on the operation specified.
function ModifyUserLicense ($userId){

    $userEntitlementUrl = "https://vsaex.dev.azure.com/"+ $accountName +"/_apis/userentitlements/"+ $userId +"?api-version=5.1-preview.2";

    if($operation -eq "upgrade")
    {
        $Body = @{
            "from" = ""
            "op" = "replace"
            "path" = "/accessLevel"
            "value" =@{
                "accountLicenseType" = "4"
                "licensingSource" = "1"      
                }
            }  | ConvertTo-Json -Depth 5
    }
    elseif ($operation -eq "downgrade")
    {
        $Body = @{
            "from" = ""
            "op" = "replace"
            "path" = "/accessLevel"
            "value" =@{
                "accountLicenseType" = "2"
                "licensingSource" = "1"      
                }
            }  | ConvertTo-Json -Depth 5

    }
    $Body = '[' + $Body + ']'

    $Result = Invoke-WebRequest -Uri "$userEntitlementUrl" -Headers $patchHeaders -Method Patch -Body $Body 
    $ResultJson = ConvertFrom-Json $Result.Content

}
#get the userId of the current user to be passed to the license update function
function GetUserId ($userEmail){

    $getUserIdUrl= "https://vsaex.dev.azure.com/$accountName/_apis/userentitlements?`$filter=name eq '"+ $userEmail +"'&api-version=6.1-preview.3"
    $getUserIdResult = Invoke-WebRequest -Headers $allHeaders -Method GET "$getUserIdUrl"
    
    if ($getUserIdResult.StatusCode -ne 200)
        {
            Write-Output $getUserIdResult.Content
            throw "Failed to get user Id"
        }

    $getUserIdResultJson = ConvertFrom-Json $getUserIdResult.Content
    #To get the list of users who updated their license
    if($getUserIdResultJson.members[0].accessLevel.licenseDisplayName -eq "Basic + Test Plans")
    {
    $UpgradedLicenses += $getUserIdResultJson.members[0].user.principalName
    }    
    return $getUserIdResultJson.members[0].id


}

try{

    $getApprovedUsersUrl= "https://extmgmt.dev.azure.com/$accountName/_apis/ExtensionManagement/InstalledExtensions/arunvarriar/smartacesss-license-manager/Data/Scopes/Default/Current/Collections/UserList/Documents/b730c0cf-0398-4dfc-b8f7-60f8bac7cab7"
    $approvedUsersResult = Invoke-WebRequest -Headers $allHeaders -Method GET "$getApprovedUsersUrl"
    
    if ($approvedUsersResult.StatusCode -ne 200)
        {
            Write-Output $approvedUsersResult.Content
            throw "Failed to get approved user list"
        }

    $approvedUsersJson = ConvertFrom-Json $approvedUsersResult.Content
    
    foreach($user in $approvedUsersJson.users){
        
        Write-Host "Modifying license for user: " $user
        $userId = GetUserId($user)
        ModifyUserLicense($userId)

    }

    Write-Host "User licenses successfully modified"
    #Write-Host "Users updated Licenses are:"
    Write-Host $UpgradedLicenses

}

catch{
throw "Licnese modification failed, details : " + $_
}

