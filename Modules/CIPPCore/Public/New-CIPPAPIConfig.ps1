

function New-CIPPAPIConfig {
    [CmdletBinding()]
    param (
        $APIName = "CIPP API Config",
        $ExecutingUser,
        $resetpassword
    )
    $null = Connect-AzAccount -Identity
    $currentapp = (Get-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name "CIPPAPIAPP" -AsPlainText)

    try {
        if ($currentapp) {
            $APIApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appid='$($currentapp)')" -NoAuthCheck $true 
        }
        else {
            $CreateBody = @"
{"api":{"oauth2PermissionScopes":[{"adminConsentDescription":"Allow the application to access CIPP-API on behalf of the signed-in user.","adminConsentDisplayName":"Access CIPP-API","id":"ba7ffeff-96ea-4ac4-9822-1bcfee9adaa4","isEnabled":true,"type":"User","userConsentDescription":"Allow the application to access CIPP-API on your behalf.","userConsentDisplayName":"Access CIPP-API","value":"user_impersonation"}]},"displayName":"CIPP-API","requiredResourceAccess":[{"resourceAccess":[{"id":"e1fe6dd8-ba31-4d61-89e7-88639da4683d","type":"Scope"}],"resourceAppId":"00000003-0000-0000-c000-000000000000"}],"signInAudience":"AzureADMyOrg","web":{"homePageUrl":"https://cipp.app","implicitGrantSettings":{"enableAccessTokenIssuance":false,"enableIdTokenIssuance":true},"redirectUris":["https://$($ENV:Website_hostname)/.auth/login/aad/callback"]}}
"@
            Write-Host "Creating app"
            $APIApp = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications" -NoAuthCheck $true -type POST -body $CreateBody
            Write-Host "Creating password"
            $APIPassword = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($APIApp.id)/addPassword"  -NoAuthCheck $true -type POST -body "{`"passwordCredential`":{`"displayName`":`"Generated by API Setup`",`"startDateTime`":`"2023-07-20T12:47:59.217Z`",`"endDateTime`":`"2033-07-20T12:47:59.217Z`"}}"
            Write-Host "Adding App URL"
            $APIIdUrl = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($APIApp.id)"  -NoAuthCheck $true -type PATCH -body "{`"identifierUris`":[`"api://$($APIApp.appId)`"]}"
            Write-Host "Adding serviceprincipal"
            $ServicePrincipal = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/serviceprincipals"  -NoAuthCheck $true -type POST -body "{`"accountEnabled`":true,`"appId`":`"$($APIApp.appId)`",`"displayName`":`"CIPP-API`",`"tags`":[`"WindowsAzureActiveDirectoryIntegratedApp`",`"AppServiceIntegratedApp`"]}"
        }
        $subscription = $($ENV:WEBSITE_OWNER_NAME).Split('+')[0]
        $CurrentSettings = New-GraphGetRequest -uri "https://management.azure.com/subscriptions/$($subscription)/resourceGroups/$ENV:WEBSITE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$ENV:WEBSITE_SITE_NAME/Config/authsettingsV2/list?api-version=2018-11-01" -NoAuthCheck $true -scope "https://management.azure.com/.default"
        Write-Host "setting settings"
        $currentSettings.properties.identityProviders.azureActiveDirectory = @{
            registration = @{
                clientId     = $APIApp.appId
                openIdIssuer = "https://sts.windows.net/$($ENV:TenantId)/v2.0"
            }
            validation   = @{
                allowedAudiences = "api://$($APIApp.appId)"
            }
        }
        if ($resetpassword) {
            Write-Host "Removing all old passwords"
            $RemovePasswords = New-GraphPOSTRequest -type Patch -uri "https://graph.microsoft.com/v1.0/applications/$($APIApp.id)/" -body '{"passwordCredentials":[]}' -NoAuthCheck $true
            $APIPassword = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($APIApp.id)/addPassword"  -NoAuthCheck $true -type POST -body "{`"passwordCredential`":{`"displayName`":`"Generated by API Setup`",`"startDateTime`":`"2023-07-20T12:47:59.217Z`",`"endDateTime`":`"2033-07-20T12:47:59.217Z`"}}"
            Write-LogMessage -user $ExecutingUser -API $APINAME -tenant 'None '-message "Reset CIPP API Password." -Sev "info"
        }
        else {
            $currentBody = ConvertTo-Json -Depth 15 -InputObject ($currentSettings | Select-Object Properties)
            Write-Host "writing to Azure"
            $SetAPIAuth = New-GraphPOSTRequest -type "PUT" -uri "https://management.azure.com/subscriptions/$($subscription)/resourceGroups/$ENV:WEBSITE_RESOURCE_GROUP/providers/Microsoft.Web/sites/$ENV:WEBSITE_SITE_NAME/Config/authsettingsV2?api-version=2018-11-01" -scope "https://management.azure.com/.default" -NoAuthCheck $true -body $currentBody
            $null = Set-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name 'CIPPAPIAPP' -SecretValue (ConvertTo-SecureString -String $APIApp.AppID -AsPlainText -Force)
            Write-LogMessage -user $ExecutingUser -API $APINAME -tenant 'None '-message "Succesfully setup CIPP-API Access." -Sev "info"
        }
        return @{
            ApplicationID     = $APIApp.AppId
            ApplicationSecret = $APIPassword.secretText
            Results           = "API Enabled. Your Application ID is $($APIApp.AppId) and your Application Secret is $($APIPassword.secretText) - Copy these keys, they are only shown once."
        }
    
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant 'None' -message "Failed to setup CIPP-API Access: $($_.Exception.Message) Linenumber: $($_.InvocationInfo.ScriptLineNumber)" -Sev "Error"
        return @{
            Results = " but could not set API configuration: $($_.Exception.Message)"
        }
        
    }
}