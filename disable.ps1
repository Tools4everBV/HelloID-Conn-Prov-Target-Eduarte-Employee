##################################################
# HelloID-Conn-Prov-Target-Eduarte-Medewerker-Disable
# PowerShell V2
##################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Add-XmlElement {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory,
            ValueFromPipeline = $True,
            Position = 0)]
        [System.Xml.XmlElement]
        $XmlParentDocument,

        [Parameter(Mandatory)]
        [string]
        $ElementName,

        [Parameter(Mandatory)]
        [string]
        [AllowEmptyString()]
        $ElementValue
    )
    process {
        try {
            $child = $XmlParentDocument.OwnerDocument.CreateElement($ElementName)
            $null = $child.InnerText = "$ElementValue"
            $null = $XmlParentDocument.AppendChild($child)
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}


function Get-EduarteGebruiker {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$UserName
    )
    process {
        try {
            Write-Information "Getting Eduarte user for: [$($UserName)]"

            # Try to correlate
            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
    <soapenv:Header/>
    <soapenv:Body>
    <api:getGebruikerRollen>
    </api:getGebruikerRollen>
    </soapenv:Body>
</soapenv:Envelope>'

            $element = $soapEnvelope.envelope.body.ChildNodes | Where-Object { $_.LocalName -eq 'getGebruikerRollen' }
            $element | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($actionContext.Configuration.ApiKey)"
            $element | Add-XmlElement -ElementName 'gebruikernaam' -ElementValue $UserName

            $splatParams = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/gebruikers"
                ContentType     = 'text/xml;charset=utf-8'
                Body            = $soapEnvelope.InnerXml
                UseBasicParsing = $true
            }

            try {
                $response = Invoke-WebRequest @splatParams

                # Check if the response is valid
                if ($response.StatusCode -ne "200") {
                    Write-Error "Invalid response: $($response.StatusCode)"
                    return $null
                }

                $rawResponse = ([xml]$response.content).Envelope.body

                if ([String]::IsNullOrEmpty($rawResponse.getGebruikerRollenResponse)) {
                    return $null
                }
                else {
                    Write-Information "Correlated Eduarte user for: [$($UserName)]"

                    return $UserName
                }

                return $null
            }
            catch {
                if ($_.ErrorDetails -match "niet gevonden") {
                    return $null
                }
                else {
                    throw $_.ErrorDetails
                }
            }
        }
        catch {
            throw $_
        }

    }
}


function Disable-EduarteUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$UserName
    )
    process {
        try {
            Write-Information "Disabling Eduarte user for: [$($UserName)]"

            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
    <soapenv:Header/>
    <soapenv:Body>
    <api:deactiveerGebruiker>
        <apiSleutel>X</apiSleutel>
        <gebruikernaam>X</gebruikernaam>
    </api:deactiveerGebruiker>
    </soapenv:Body>
</soapenv:Envelope>'

            # Add the properties
            $soapEnvelope.envelope.body.deactiveerGebruiker.apiSleutel = "$($actionContext.Configuration.ApiKey)"
            $soapEnvelope.envelope.body.deactiveerGebruiker.gebruikernaam = $UserName

            $splatParams = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/gebruikers"
                ContentType     = 'text/xml;charset=utf-8'
                Body            = $soapEnvelope.InnerXml
                UseBasicParsing = $true
            }

            # Parse the response
            # When this call executes without an exception, we assume OK
            $null = Invoke-WebRequest @splatParams

        }
        catch {
            throw $_
        }
    }
}

function Resolve-Eduarte-EmployeeError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
            $httpErrorObj.FriendlyMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException' -and (-not [string]::IsNullOrEmpty($ErrorObject.Exception.Response))) {
            $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
            if ( $streamReaderResponse ) {
                $httpErrorObj.ErrorDetails = $streamReaderResponse
                $httpErrorObj.FriendlyMessage = $streamReaderResponse
            }
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account.User))) {
        throw 'The account reference could not be found'
    }

    Write-Information "Verifying if a Eduarte-employee (medewerker) account for [$($personContext.Person.DisplayName)] exists"
    $correlatedAccount = Get-EduarteGebruiker -UserName $actionContext.References.Account.User

    if ($null -ne $correlatedAccount) {
        $action = 'DisableAccount'
        $dryRunMessage = "Disable Eduarte-user (gebruiker) account for Eduarte-employee (medewerker) account: [$($actionContext.References.Account.User)] for person: [$($personContext.Person.DisplayName)] will be executed during enforcement"
    } else {
        $action = 'NotFound'
        $dryRunMessage = "No Eduarte-user (gebruiker) account found for existing Eduarte-employee (medewerker) account: [$($actionContext.References.Account.User)], possibly indicating that it could be deleted, or the account is not correlated"
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'DisableAccount' {
                Write-Information "Disabling Eduarte-employee (medewerker) account with accountReference: [$($actionContext.References.Account.User)]"

                $null = Disable-EduarteUser -UserName $actionContext.References.Account.User

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Disable account was successful [$($actionContext.References.Account.User)]"
                    IsError = $false
                })
                break
            }

            'NotFound' {
                $outputContext.Success  = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Eduarte-Medewerker account: [$($actionContext.References.Account.User)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                    IsError = $false
                })
                break
            }
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Eduarte-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not disable Eduarte-Medewerker account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not disable Eduarte-Medewerker account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Message = $auditMessage
        IsError = $true
    })
}