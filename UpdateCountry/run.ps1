using namespace System.Net

param($Request, $TriggerMetadata)

$body = $Request.Body
$upn     = $body.UserPrincipalName
$country = $body.Country

# Validate input
if (-not $upn -or -not $country) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = (@{ message = "Missing UserPrincipalName or Country" } | ConvertTo-Json)
    })
    return
}

$allowedCountries = @("Azerbaijan", "Russia", "Germany", "United States")
if ($country -notin $allowedCountries) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = (@{ message = "Invalid country: $country" } | ConvertTo-Json)
    })
    return
}

try {
    # Get token directly from Managed Identity - no Az modules needed
    $tokenResponse = Invoke-RestMethod `
        -Uri "$($env:IDENTITY_ENDPOINT)?resource=https://management.azure.com&api-version=2019-08-01" `
        -Headers @{ "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER } `
        -Method GET

    $accessToken = $tokenResponse.access_token

    # Call Azure Automation REST API directly
    $subscriptionId    = $env:SUBSCRIPTION_ID
    $resourceGroup     = $env:AUTOMATION_RESOURCE_GROUP
    $automationAccount = "blacklone"
    $runbookName       = "Blacktrigger"
    $jobId             = [guid]::NewGuid().ToString()

    $apiUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Automation/automationAccounts/$automationAccount/jobs/${jobId}?api-version=2023-11-01"

    $jobBody = @{
        properties = @{
            runbook = @{
                name = $runbookName
            }
            parameters = @{
                UserPrincipalName = $upn
                Country           = $country
            }
            runOn = "Activedirectory"
        }
    } | ConvertTo-Json -Depth 5

    $result = Invoke-RestMethod -Uri $apiUrl `
        -Method PUT `
        -Headers @{
            Authorization  = "Bearer $accessToken"
            "Content-Type" = "application/json"
        } `
        -Body $jobBody

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = (@{
            message = "Country change request submitted for $upn to $country"
            jobId   = $result.properties.jobId
        } | ConvertTo-Json)
    })
}
catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = (@{ message = "Failed: $_" } | ConvertTo-Json)
    })
}
