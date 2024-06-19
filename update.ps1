#################################################
# HelloID-Conn-Prov-Target-Eduarte-Medewerker-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#extra mapping to ensure the properties are in aplhabetical order
$account = Sort-EduartePSCustomObjectProperties -InputObject $actionContext.Data

#region functions
function Get-EduarteEmployee {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$userName
    )
    process {
        try {
            Write-Information "Getting Eduarte employee for: [$($userName)]"

            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
    <soapenv:Header/>
    <soapenv:Body>
    <api:getMedewerkerMetGebruikersnaam>
    </api:getMedewerkerMetGebruikersnaam>
    </soapenv:Body>
</soapenv:Envelope>'

            $element = $soapEnvelope.envelope.body.ChildNodes | Where-Object { $_.LocalName -eq 'getMedewerkerMetGebruikersnaam' }
            $element | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($actionContext.Configuration.ApiKey)"
            $element | Add-XmlElement -ElementName 'gebruikersnaam' -ElementValue "$($userName)"

            $splatGetEmployee = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
                ContentType     = "text/xml"
                Body            = $soapEnvelope.InnerXml
                UseBasicParsing = $true
            }

            $response = Invoke-WebRequest @splatGetEmployee

            # Check if the response is valid
            if ($response.StatusCode -ne "200") {
                Write-Error "Invalid response: $($response.StatusCode)"
                return $null
            }

            $rawResponse = ([xml]$response.content).Envelope.body
            $employee = $rawResponse.getMedewerkerMetGebruikersnaamResponse.medewerker

            if ([String]::IsNullOrEmpty($employee)) {
                return $null
            }
            else {
                Write-Information "Correlated Eduarte employee for: [$($userName)]"

                return $employee
            }
        }
        catch {
            throw $_
        }
    }
}

function Set-EduarteEmployee {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$employee,
        [Parameter(Mandatory)]
        [object]$Account
    )
    process {
        try {
            Write-Information "Updating Eduarte employee for: [$($Account.afkorting)]"

            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
                <soapenv:Header/>
                    <soapenv:Body>
                       <api:update>
                            <apiSleutel>?</apiSleutel>
                            <gewijzigdeMedewerker></gewijzigdeMedewerker>
                        </api:update>
                    </soapenv:Body>
                </soapenv:Envelope>'

            # Add the apiSleutel
            $soapEnvelope.envelope.body.update.apiSleutel = $actionContext.Configuration.ApiKey

            # Add the medewerker id to the account object
            $Account.id = $employee.id

            # Remove contactgegevens to add later with the function Write-ContactGegevensToXmlDocument
            $Account.PSObject.Properties.Remove('contactgegevens')

            # Add account mapping attributes
            $updateElement = $soapEnvelope.envelope.body.update.ChildNodes | Where-Object { $_.LocalName -eq 'gewijzigdeMedewerker' }
            $Account | Write-ToXmlDocument -XmlDocument $soapEnvelope -XmlParentDocument $updateElement

            # Add contactgegevens
            Write-ContactGegevensToXmlDocument -ContactGegevens @($account.contactgegevens) -XmlElement $updateElement

            $splatUpdateEmployee = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
                Body            = $soapEnvelope.InnerXml
                ContentType     = "text/xml"
                UseBasicParsing = $true
            }

            # Parse the response and get the generated account reference
            $updateEmployeeResponse = Invoke-WebRequest @splatUpdateEmployee
            $rawResponse = ([xml]$updateEmployeeResponse.content).Envelope.body
            $employee = $rawResponse.updateResponse.medewerker

            if ([String]::IsNullOrEmpty($employee)) {
                return $null
            }
            else {
                Write-Information "Updated Eduarte employee for: [$($Account.afkorting)]"

                return $employee
            }
        }
        catch {
            Write-Error $_

            return $null

        }
    }
}

function Sort-EduartePSCustomObjectProperties {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$InputObject
    )

    $sortedObject = [PSCustomObject]@{}

    $sortedProperties = $InputObject.PSObject.Properties.Name | Sort-Object

    foreach ($property in $sortedProperties) {
        $value = $InputObject.$property

        if ($value -is [PSCustomObject]) {
            $sortedObject | Add-Member -NotePropertyName $property -NotePropertyValue (Sort-EduartePSCustomObjectProperties -InputObject $value)
        } elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
            $sortedArray = @()
            foreach ($item in $value) {
                if ($item -is [PSCustomObject]) {
                    $sortedArray += Sort-EduartePSCustomObjectProperties -InputObject $item
                } else {
                    $sortedArray += $item
                }
            }
            $sortedObject | Add-Member -NotePropertyName $property -NotePropertyValue $sortedArray
        } else {
            $sortedObject | Add-Member -NotePropertyName $property -NotePropertyValue $value
        }
    }

    return $sortedObject
}

function Write-ToXmlDocument {
    [Cmdletbinding()]
    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline = $True,
            Position = 0)]
        $Properties,

        [Parameter(Mandatory)]
        [System.Xml.XmlDocument]
        $XmlDocument,

        [Parameter(Mandatory)]
        [System.Xml.XmlElement]
        $XmlParentDocument
    )
    if ($Properties.GetType().Name -eq "PSCustomObject") {
        $ParameterList = [ordered]@{}
        foreach ($prop in $Properties.PSObject.Properties) {
            $ParameterList[$prop.Name] = $prop.Value
        }
    }
    else {
        $ParameterList = $Properties
    }
    foreach ($param in $ParameterList.GetEnumerator()) {
        if (($param.Value) -is [PSCustomObject] -or ($param.Value) -is [Hashtable] -and $null -ne $param.Value) {
            $parent = $XmlDocument.CreateElement($param.Name)
            $ParameterList[$param.Name] | Write-ToXmlDocument -XmlDocument  $XmlDocument -XmlParentDocument $parent
            $null = $XmlParentDocument.AppendChild($parent)
        }
        else {
            $child = $XmlDocument.CreateElement($param.Name)
            $null = $child.InnerText = "$($param.Value)"
            $null = $XmlParentDocument.AppendChild($child)
        }
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

function Write-ContactGegevensToXmlDocument {
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        $ContactGegevens,

        [Parameter(Mandatory)]
        [System.Xml.XmlElement]
        $XmlElement
    )
    # Add contactgegevens
    $contactgegevensElement = $XmlElement.ChildNodes | Where-Object { $_.LocalName -eq 'contactgegevens' }

    if ($null -eq $contactgegevensElement) {
        throw "Could not find the contactgegevens element"
    }

    foreach ($contactgegeven in $ContactGegevens) {
        # Create the contactgegeven element
        $contactgegevenElement = $contactgegevensElement.OwnerDocument.CreateElement("contactgegeven")
        $null = $contactgegevensElement.AppendChild($contactgegevenElement)

        Add-XmlElement -XmlParentDocument $contactgegevenElement -ElementName 'contactgegeven' -ElementValue "$($contactgegeven.waarde)"

        # Create the soort element
        $soortElement = $contactgegevensElement.OwnerDocument.CreateElement("soort")
        $null = $contactgegevenElement.AppendChild($soortElement)

        Add-XmlElement -XmlParentDocument $soortElement -ElementName 'code' -ElementValue "$($contactgegeven.code)"
        Add-XmlElement -XmlParentDocument $soortElement -ElementName 'naam' -ElementValue "$($contactgegeven.naam)"
        Add-XmlElement -XmlParentDocument $contactgegevenElement -ElementName 'geheim' -ElementValue "$($contactgegeven.geheim)"
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
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information "Verifying if a Eduarte-employee (medewerker) account for [$($personContext.Person.DisplayName)] exists"
    $correlatedAccount = Get-EduarteEmployee -userName $actionContext.References.Account

    $outputContext.PreviousData = $correlatedAccount

if ($null -ne $correlatedAccount) {
        # TODO Always compare the account against the current account in target system
        # $splatCompareProperties = @{
        #     ReferenceObject  = @($correlatedAccount.PSObject.Properties)
        #     DifferenceObject = @($account.PSObject.Properties)
        # }  
        # $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        # if ($propertiesChanged) {
        #     $action = 'UpdateAccount'
        #     $dryRunMessage = "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
        # } else {
        #     $action = 'NoChanges'
        #     $dryRunMessage = 'No changes will be made to the account during enforcement'
        # }
        $action = 'UpdateAccount'
        $dryRunMessage = "Employee account will be updated during enforcement"
    } else {
        $action = 'NotFound'
        $dryRunMessage = "Eduarte-employee (medewerker) account for: [$($personContext.Person.DisplayName)] not found. Possibly deleted."
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'UpdateAccount' {
                Write-Information "Updating Eduarte-employee (medewerker) account with accountReference: [$($actionContext.References.Account)]"

                $accountWithoutUser = ($account | Select-Object -Property * -ExcludeProperty gebruiker)
                $null = Set-EduarteEmployee -Employee $correlatedAccount -Account $accountWithoutUser

                $outputContext.Success = $true
                # TODO Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Update account was successful'
                    IsError = $false
                })
                break
            }

            'NoChanges' {
                Write-Information "No changes to Eduarte-employee (medewerker) account with accountReference: [$($actionContext.References.Account)]"

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
                break
            }

            'NotFound' {
                $outputContext.Success  = $false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Eduarte-employee (medewerker) account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                    IsError = $true
                })
                break
            }
        }
    }
} catch {
    $outputContext.Success  = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Eduarte-MedewerkerError -ErrorObject $ex
        $auditMessage = "Could not update Eduarte-employee (medewerker) account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Eduarte-employee (medewerker) account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
