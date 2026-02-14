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
    Connect-AzAccount -Identity | Out-Null

    $params = @{
        UserPrincipalName = $upn
        Country           = $country
    }

    $job = Start-AzAutomationRunbook `
        -AutomationAccountName "blacklone" `
        -ResourceGroupName $env:AUTOMATION_RESOURCE_GROUP `
        -Name "Blacktrigger" `
        -Parameters $params `
        -RunOn "Activedirectory"

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = (@{
            message = "Country change request submitted for $upn to $country"
            jobId   = $job.JobId.ToString()
        } | ConvertTo-Json)
    })
}
catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = (@{ message = "Failed to trigger runbook: $_" } | ConvertTo-Json)
    })
}