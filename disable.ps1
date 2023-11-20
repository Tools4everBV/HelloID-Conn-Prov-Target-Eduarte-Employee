#######################################
# HelloID-Conn-Prov-Target-Eduarte-Employee-Disable
#
# Version: 1.0.0
#######################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
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
        # Todo: The error message may need to be neatened for the friendlyerror message
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
#endregion

# Begin
try {
    if ([string]::IsNullOrEmpty($($aRef))) {
        throw 'The account reference could not be found'
    }
    
    Write-Verbose "Verifying if a Eduarte-Employee account for [$($p.DisplayName)] exists"
    [xml]$soapEnvelopegetMedewerkerMetId = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
        <soapenv:Header/>
        <soapenv:Body>
        <api:getMedewerkerMetId>
        </api:getMedewerkerMetId>
        </soapenv:Body>
    </soapenv:Envelope>'
    $getMedewerkerMetIdElement = $soapEnvelopegetMedewerkerMetId.envelope.body.ChildNodes | Where-Object { $_.LocalName -eq 'getMedewerkerMetId' }
    $getMedewerkerMetIdElement | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($config.ApiKey)"
    $getMedewerkerMetIdElement | Add-XmlElement -ElementName 'personeelsnummer' -ElementValue "$($aRef)"

    $splatGetEmployee = @{
        Method      = 'Post'
        Uri         = "$($config.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
        ContentType = "text/xml" 
        Body        = $soapEnvelopegetMedewerkerMetId.InnerXml
    }
    $responseEmployee = Invoke-RestMethod @splatGetEmployee -Verbose:$false

    if ($responseEmployee) {
        $action = 'Found'
        $dryRunMessage = "Disable Eduarte-Employee account for: [$($p.DisplayName)] will be executed during enforcement"
    }
    elseif ($null -eq $responseEmployee) {
        $action = 'NotFound'
        $dryRunMessage = "Eduarte-Employee account for: [$($p.DisplayName)] not found. Possibly already deleted. Skipping action"
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Found' {
                Write-Verbose "Disable Eduarte-Employee account with accountReference: [$aRef]"

                [xml]$disableEmployee = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
                    <soapenv:Header/>
                    <soapenv:Body>
                    <api:deactiveerGebruiker>
                        <apiSleutel>X</apiSleutel>
                    </api:deactiveerGebruiker>
                    </soapenv:Body>
                </soapenv:Envelope>' 

                $disableEmployee.envelope.body.deactiveerGebruiker.apiSleutel = "$($config.ApiKey)"

                $updateElement = $disableEmployee.envelope.body.deactiveerGebruiker

                # Todo check if the resultStudent.gebruikersnaam is the correct way of retrieving the username 
                $updateElement | Add-XmlElement -ElementName 'gebruikernaam' -ElementValue "$($responseEmployee.gebruikernaam)"

                $splatDisableEmployee = @{
                    Uri         = "$($config.BaseUrl.TrimEnd('/'))/services/api/algemeen/gebruikers" 
                    Method      = 'Post'
                    ContentType = "text/xml" 
                    Body        = $disableEmployee.InnerXml
                }
                $responseEmployee = Invoke-RestMethod @splatDisableEmployee -Verbose:$false

                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Disable account was successful'
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Eduarte-Employee account for: [$($p.DisplayName)] not found. Possibly already deleted. Skipping action"
                        IsError = $false
                    })
                break
            }
        }

        $success = $true
    }
}
catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Eduarte-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not disable Eduarte-Employee account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not disable Eduarte-Employee account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
    # End
}
finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
