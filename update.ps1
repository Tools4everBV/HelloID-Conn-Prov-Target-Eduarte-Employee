#################################################
# HelloID-Conn-Prov-Target-Eduarte-Medewerker-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Get-EduarteEmployeeById {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Id
    )
    process {
        try {
            Write-Information "Getting Eduarte employee for: [$($Id)]"

            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
                <soapenv:Header/>
                <soapenv:Body>
                <api:getMedewerkerMetId>
                </api:getMedewerkerMetId>
                </soapenv:Body>
            </soapenv:Envelope>'

            $element = $soapEnvelope.envelope.body.ChildNodes | Where-Object { $_.LocalName -eq 'getMedewerkerMetId' }
            $element | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($actionContext.Configuration.ApiKey)"
            $element | Add-XmlElement -ElementName 'id' -ElementValue "$($Id)"

            $splatGetEmployee = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
                ContentType     = 'text/xml;charset=utf-8'
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
            $employee = $rawResponse.getMedewerkerMetIdResponse.medewerker

            if ([String]::IsNullOrEmpty($employee)) {
                return $null
            } else {
                Write-Information "Correlated Eduarte employee for: [$($Id)]"

                return $employee
            }
        } catch {
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

            # Add account mapping attributes
            $element = $soapEnvelope.envelope.body.update.ChildNodes | Where-Object { $_.LocalName -eq 'gewijzigdeMedewerker' }

            $Account | Select-Object * -ExcludeProperty contactgegevens | Write-ToXmlDocument -XmlDocument $soapEnvelope -XmlParentDocument $element | Out-Null

            # Add contactgegevens
            Write-ContactGegevensToXmlDocument -ContactGegevens @($account.contactgegevens) -XmlElement $element | Out-Null

            $splatUpdateEmployee = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
                Body            = $soapEnvelope.InnerXml
                ContentType     = 'text/xml;charset=utf-8'
                UseBasicParsing = $true
            }

            # Parse the response and get the generated account reference
            $updateEmployeeResponse = Invoke-WebRequest @splatUpdateEmployee
            $rawResponse = ([xml]$updateEmployeeResponse.content).Envelope.body
            $employee = $rawResponse.updateResponse.medewerker

            if ([String]::IsNullOrEmpty($employee)) {
                return $null
            } else {
                Write-Information "Updated Eduarte employee for: [$($Account.afkorting)]"
                return $employee
            }
        } catch {
            throw $_
        }
    }
}

function New-EduarteUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Employee,
        [Parameter(Mandatory)]
        [object]$User
    )
    process {
        try {
            Write-Information "Creating Eduarte-user (gebruiker) for: [$($User.gebruikernaam)]"

            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
                <soapenv:Header/>
                <soapenv:Body>
                <api:createMedewerkerGebruiker>
                    <apiSleutel>X</apiSleutel>
                    <gebruikernaam>X</gebruikernaam>
                    <wachtwoord>X</wachtwoord>
                    <medewerker>X</medewerker>
                </api:createMedewerkerGebruiker>
                </soapenv:Body>
            </soapenv:Envelope>'

            # Add the apiSleutel (Not Dynamic because the order is not alphabetical)
            $soapEnvelope.envelope.body.createMedewerkerGebruiker.apiSleutel = "$($actionContext.Configuration.ApiKey)"
            $soapEnvelope.envelope.body.createMedewerkerGebruiker.gebruikernaam = "$($User.gebruikernaam)"
            $soapEnvelope.envelope.body.createMedewerkerGebruiker.wachtwoord = "$($user.wachtwoord)"
            $soapEnvelope.envelope.body.createMedewerkerGebruiker.medewerker = "$($Employee.id)"

            $splatParams = @{
                Method          = 'Post'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/gebruikers"
                ContentType     = 'text/xml;charset=utf-8'
                Body            = $soapEnvelope.InnerXml
                UseBasicParsing = $true
            }

            # Parse the response
            try {
                # When this call executes without an exception, we assume the account was created
                $response = Invoke-WebRequest @splatParams

                if ($response.Content -match "niet gevonden") {
                    throw "Could not create Eduarte-user (gebruiker) account '$($User.gebruikersnaam)'. $($response.Content)"
                }

                if ($response.Content -match "heeft reeds een account") {
                    throw "Could not create Eduarte-user (gebruiker) account '$($User.gebruikersnaam)'. Deelnemer already has an (other) account: $($response.Content)"
                }

                return $User.gebruikernaam
            } catch {
                if ($_.ErrorDetails -match "heeft reeds een account") {
                    throw "Could not create Eduarte-user (gebruiker) account '$($User.gebruikernaam)'. Medewerker already has an (other) account: $($_.ErrorDetails)"
                } else {
                    throw $_.ErrorDetails
                }
            }
        } catch {
            throw $_
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
    } else {
        $ParameterList = $Properties
    }
    foreach ($param in $ParameterList.GetEnumerator()) {
        if (($param.Value) -is [PSCustomObject] -or ($param.Value) -is [Hashtable] -and $null -ne $param.Value) {
            $parent = $XmlDocument.CreateElement($param.Name)
            $ParameterList[$param.Name] | Write-ToXmlDocument -XmlDocument  $XmlDocument -XmlParentDocument $parent
            $null = $XmlParentDocument.AppendChild($parent)
        } else {
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
        } catch {
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
        # Find the next property alphabetically after the begin letter of contactgegevens to insert the property contactGegevens before this element
        $refElement = ($XmlElement.ChildNodes | Sort-Object LocalName | Where-Object { $_.LocalName -gt 'c' } | Select-Object -First 1)

        $child = $XmlElement.OwnerDocument.CreateElement('contactgegevens')
        $XmlElement.InsertBefore($child, $refElement)
        $contactgegevensElement = $XmlElement.ChildNodes | Where-Object { $_.LocalName -eq 'contactgegevens' }
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
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account.Id))) {
        throw 'The account reference could not be found'
    }

    #extra mapping to ensure the properties are in alphabetical order
    $actionContext.Data | Add-Member @{id = $actionContext.References.Account.Id } -Force
    $account = Sort-EduartePSCustomObjectProperties -InputObject $actionContext.Data

    Write-Information "Verifying if a Eduarte-employee (medewerker) account for [$($personContext.Person.DisplayName)] exists"
    $correlatedAccountXML = Get-EduarteEmployeeById -Id "$($actionContext.References.Account.Id)"


    # Format Correlated account to $outputContext.PreviousPerson
    $correlatedAccount = [pscustomobject]@{}
    foreach ($node in $correlatedAccountXML.ChildNodes ) {
        if ($node.name -notin @('contactgegevens', 'functie')) {
            $correlatedAccount | Add-Member @{"$($node.Name)" = $node.InnerText } -Force
        }
        if ($node.name -eq 'contactgegevens') {
            $contactgegeven = ($node | Where-Object { $_.contactgegeven.soort.code -eq 'E' }).contactgegeven
            $correlatedAccount | Add-Member @{
                contactgegevens = [PSCustomObject]@{
                    waarde = $contactgegeven.contactgegeven
                    geheim = $contactgegeven.geheim
                    naam   = $contactgegeven.soort.naam
                    code   = $contactgegeven.soort.code
                }
            }
        }
        if ($node.name -eq 'functie') {
            $correlatedAccount | Add-Member @{
                functie = [PSCustomObject]@{
                    code = $node.code
                    naam = $node.naam
                }
            }
        }
    }

    if ($actionContext.Data.gebruiker) {
        $correlatedAccount | Add-Member @{
            gebruiker = $actionContext.Data.gebruiker
        }
    }

    $outputContext.PreviousData = $correlatedAccount

    if ($null -ne $correlatedAccount) {
        # TODO Always compare the account against the current account in target system
        $splatCompareProperties = @{
            ReferenceObject  = @($outputContext.PreviousData.PSObject.Properties)
            DifferenceObject = @(($actionContext.data | Select-Object * -ExcludeProperty contactgegevens, functie , gebruiker, id).PSObject.Properties)
        }
        $propertiesChangedObject = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        $propertiesChanged = @{}
        $propertiesChangedObject | ForEach-Object { $propertiesChanged[$_.Name] = $_.Value }

        # Additional compare for contactgegevens
        if ((-not [string]::IsNullOrEmpty($actionContext.Data.contactgegevens.waarde)) -and $actionContext.Data.contactgegevens.waarde -ne $outputContext.PreviousData.contactgegevens.waarde) {
            $propertiesChanged['contactgegeven-Email'] = $actionContext.Data.contactgegevens.waarde
        }

        # Additional compare for functie
        if (-not [string]::IsNullOrEmpty($actionContext.Data.functie)) {
            $functie = $actionContext.Data.functie
            if ($functie.code -ne $correlatedAccount.functie.code) {
                $propertiesChanged['functie-code'] = $actionContext.Data.functie.code
            }
            if ($functie.naam -ne $correlatedAccount.functie.naam) {
                $propertiesChanged['functie-naam'] = $actionContext.Data.functie.naam
            }
        }

        if ($propertiesChanged.Count -gt 0) {
            $action = 'UpdateAccount'
            $dryRunMessage = "Account property(s) required to update: [$($propertiesChanged.Keys -join ', ')]"
        } else {
            $action = 'NoChanges'
            $dryRunMessage = 'No changes will be made to the account during enforcement'
        }
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
                Write-Information "Updating Eduarte-employee (medewerker) account with accountReference: [$($actionContext.References.Account.Id)]"

                $accountWithoutUser = ($account | Select-Object -Property * -ExcludeProperty gebruiker)
                $null = Set-EduarteEmployee -Employee $correlatedAccount -Account $accountWithoutUser

                if (-not [string]::IsNullOrEmpty($account.gebruiker.gebruikernaam) -and $correlatedAccount.gebruikersnaam -ne $account.gebruiker.gebruikernaam) {
                    $null = New-EduarteUser -Employee $correlatedAccount -User $account.gebruiker
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Creating Eduarte-user (gebruiker) account was successful. AccountReference is: [$($outputContext.AccountReference.User)]"
                            IsError = $false
                        })
                }

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.Keys -join ', ')]"
                        IsError = $false
                    })
                break
            }

            'NoChanges' {
                Write-Information "No changes to Eduarte-employee (medewerker) account with accountReference: [$($actionContext.References.Account.Id)]"

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = 'No changes will be made to the account during enforcement'
                        IsError = $false
                    })
                break
            }

            'NotFound' {
                $outputContext.Success = $false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Eduarte-employee (medewerker) account with accountReference: [$($actionContext.References.Account.Id)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                        IsError = $true
                    })
                break
            }
        }
    }
} catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Eduarte-EmployeeError -ErrorObject $ex
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
