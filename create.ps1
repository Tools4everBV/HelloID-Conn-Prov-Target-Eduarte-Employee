##################################################
# HelloID-Conn-Prov-Target-Eduarte-Employee-Create-Update
#
# Version: 1.0.0
##################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    ExternalId   = $p.ExternalId
    UserName     = $p.UserName
    EmailAddress = $p.Contact.Business.Email
}

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
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException' -and (-not [string]::IsNullOrEmpty($ErrorObject.Exception.Response))) {
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
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
#endregion

# Begin
try {
    [xml]$soapEnvelopegetMedewerkerMetId = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
        <soapenv:Header/>
        <soapenv:Body>
        <api:getMedewerkerMetId>
        </api:getMedewerkerMetId>
        </soapenv:Body>
    </soapenv:Envelope>'
    $getMedewerkerMetIdElement = $soapEnvelopegetMedewerkerMetId.envelope.body.ChildNodes | Where-Object { $_.LocalName -eq 'getMedewerkerMetId' }
    $getMedewerkerMetIdElement | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($account.ApiKey)"
    $getMedewerkerMetIdElement | Add-XmlElement -ElementName 'personeelsnummer' -ElementValue "$($account.ExternalId)"

    $splatGetEmployee = @{
        Method = 'Post'
        Uri    = "$($config.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
        Body   = $soapEnvelopegetMedewerkerMetId.InnerXml
    }
    $responseEmployee = Invoke-RestMethod @splatGetEmployee -Verbose:$false

    # Todo: Check if update condition works as expected
    if ($responseEmployee) {
        $action = 'Update'
    } else {
        $action = 'NotFound'
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $action Eduarte-Employee account for: [$($p.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Update' {
                # Todo: Validate contactgegeven
                [xml]$soapEnvelopeUpdateEmployee = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.umra.webservices.eduarte.topicus.nl/">
                    <soapenv:Header/>
                    <soapenv:Body>
                        <update xmlns="http://api.algemeen.webservices.eduarte.topicus.nl/">
                            <gewijzigdeMedewerker xmlns="">
                                <contactgegevens>
                                    <contactgegeven>
                                        <contactgegeven>XXXXXX</contactgegeven>
                                        <soort>
                                            <code>1</code>
                                            <naam>mail</naam>
                                        </soort>
                                        <geheim>false</geheim>
                                    </contactgegeven>
                                </contactgegevens>
                            </gewijzigdeMedewerker>
                        </update>
                    </soapenv:Body>
                </soapenv:Envelope>'
                $updateElement = $soapEnvelopeUpdateEmployee.envelope.body.update
                $updateElement | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($config.ApiKey)"

                # Todo: validate Id
                $updateElement.gewijzigdeMedewerker | Add-XmlElement -ElementName 'id' -ElementValue "$($account.externalId)"

                if ((-not [string]::IsNullOrEmpty($account.UserName)) -and $responseEmployee.gebruikersnaam -ne $account.UserName) {
                    $updateElement.gewijzigdeMedewerker | Add-XmlElement -ElementName 'gebruikersnaam' -ElementValue $account.UserName
                    $updateRequired = $true
                }

                # Todo: Check if the email adres can be found in the [contactgegevens]
                $mailProperty = $responseEmployee.contactgegevens.contactgegeven | Where-Object { $_.soort.naam -eq 'mail' }
                if ((-not [string]::IsNullOrEmpty($account.EmailAddress)) -and ($mailProperty.contactgegeven -ne $account.EmailAddress)) {
                    $updateElement.gewijzigdeMedewerker.contactgegevens.contactgegeven.contactgegeven = "$($account.EmailAddress)"
                    $updateRequired = $true
                }

                if ($updateRequired) {
                    $splatSetEmployee = @{
                        Method = 'Post'
                        Uri    = "$($config.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
                        Body   = $soapEnvelopeUpdateEmployee.InnerXml
                    }
                    # Todo: Check possible the response!
                    $null = Invoke-RestMethod @splatSetEmployee -Verbose:$false
                    $auditLogs.Add([PSCustomObject]@{
                            Message = "Update account was successful. AccountReference is: [$($account.ExternalId)]"
                            IsError = $false
                        })
                } else {
                    $auditLogs.Add([PSCustomObject]@{
                            Message = "No Update account required. AccountReference is: [$($account.ExternalId)]"
                            IsError = $false
                        })
                }
                $accountReference = "$($account.ExternalId)"
                break
            }

            'NotFound' {
                throw "No account found with ExternalId [$($account.ExternalId)]"
            }
        }
        $success = $true

    }
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Eduarte-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not Update Eduarte-Employee account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not Update Eduarte-Employee account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
} finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
