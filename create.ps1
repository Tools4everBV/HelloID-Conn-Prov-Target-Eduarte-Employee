#################################################
# HelloID-Conn-Prov-Target-Eduarte-Medewerker-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Get-EduarteEmployeeMetGebruikersnaam {
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
            $medewerker = $rawResponse.getMedewerkerMetGebruikersnaamResponse.medewerker

            if ([String]::IsNullOrEmpty($medewerker)) {
                return $null
            } else {
                Write-Information "Correlated Eduarte-employee (medewerker) for: [$($userName)]"

                return $medewerker
            }
        } catch {
            throw $_
        }
    }
}

function Get-EduarteMedewerkerMetAfkorting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Afkorting
    )
    process {
        try {
            Write-Verbose "Getting Eduarte employee for: [$($Afkorting)]"

            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
                <soapenv:Header/>
                <soapenv:Body>
                <api:getMedewerkerMetAfkorting>
                </api:getMedewerkerMetAfkorting>
                </soapenv:Body>
            </soapenv:Envelope>'

            $element = $soapEnvelope.envelope.body.ChildNodes | Where-Object { $_.LocalName -eq 'getMedewerkerMetAfkorting' }
            $element | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($actionContext.Configuration.ApiKey)"
            $element | Add-XmlElement -ElementName 'afkorting' -ElementValue "$($Afkorting)"

            $splatGetEmployee = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
                ContentType     = 'text/xml;charset=utf-8'
                Body            = $soapEnvelope.InnerXml
                UseBasicParsing = $true
            }

            $response = Invoke-WebRequest @splatGetEmployee

            # Check if the response is valid
            if ($response.StatusCode -ne '200') {
                Write-Error "Invalid response: $($response.StatusCode)"
                return $null
            }

            $rawResponse = ([xml]$response.content).Envelope.body
            $medewerker = $rawResponse.getMedewerkerMetAfkortingResponse.medewerker

            if ([String]::IsNullOrEmpty($medewerker)) {
                return $null
            } else {
                Write-Verbose "Correlated Eduarte employee for: [$($Afkorting)]"
                return $medewerker
            }
        } catch {
            throw $_
        }
    }
}

function New-EduarteEmployee {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Account
    )
    process {
        try {
            Write-Information "Creating Eduarte-employee (medewerker) for: [$($Account.gebruikersnaam)]"

            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
        <soapenv:Header/>
        <soapenv:Body>
        <api:create>
            <apiSleutel>X</apiSleutel>
            <nieuweMedewerker></nieuweMedewerker>
        </api:create>
        </soapenv:Body>
    </soapenv:Envelope>'

            # Add the apiSleutel
            $soapEnvelope.envelope.body.create.apiSleutel = $actionContext.Configuration.ApiKey

            # Add account mapping attributes
            $element = $soapEnvelope.envelope.body.create.ChildNodes | Where-Object { $_.LocalName -eq 'nieuweMedewerker' }

            # Remove id attribute, must be empty on create
            $null = $Account.PSObject.Properties.Remove('id')

            # Remove contactgegevens to add later with the function Write-ContactGegevensToXmlDocument
            $Account | Select-Object * -ExcludeProperty contactgegevens | Write-ToXmlDocument -XmlDocument $soapEnvelope -XmlParentDocument $element | Out-Null

            # Add contactgegevens
            Write-ContactGegevensToXmlDocument -ContactGegevens @($account.contactgegevens) -XmlElement $element  | Out-Null

            $splatCreateEmployee = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
                ContentType     = 'text/xml;charset=utf-8'
                Body            = $soapEnvelope.InnerXml
                UseBasicParsing = $true
            }

            # Parse the response and get the generated id attribute
            $createEmployeeResponse = Invoke-WebRequest @splatCreateEmployee
            $rawResponse = ([xml]$createEmployeeResponse.content).Envelope.body
            $medewerker = $rawResponse.createResponse.medewerker

            if ([String]::IsNullOrEmpty($medewerker)) {
                return $null
            } else {
                Write-Information "Created Eduarte-employee (medewerker) for: [$($Account.afkorting)]"
                return $medewerker
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
    # Initial Assignments
    $outputContext.AccountReference = [pscustomobject]@{
        id   = 'Currently not available'
        user = 'Currently not available'
    }

    # Extra mapping to ensure the properties are in alphabetical order
    $account = Sort-EduartePSCustomObjectProperties -InputObject $actionContext.Data

    if ([String]::IsNullOrEmpty($account.gebruikersnaam)) {
        throw 'Gebruikersnaam is empty, cannot continue...'
    }

    if ([String]::IsNullOrEmpty($account.afkorting)) {
        throw 'Afkorting is empty, cannot continue...'
    }

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        if ($correlationField -eq 'afkorting') {
            $correlatedEmployeeAccount = Get-EduarteMedewerkerMetAfkorting -Afkorting $correlationValue
        } elseif ($correlationField -eq 'gebruikersnaam') {
            $correlatedEmployeeAccount = Get-EduarteEmployeeMetGebruikersnaam -userName $correlationValue
        } else {
            throw "No valid correlate implementation found for correlationField [$($correlationField )]"
        }


        $account.id = $correlatedEmployeeAccount.id
        $account.gebruiker.medewerker = $correlatedEmployeeAccount.id

        if (-not [string]::IsNullOrEmpty($account.gebruiker.gebruikernaam) ) {
            $correlatedUserAccount = $true
            if ($null -eq $correlatedAccount.gebruikersnaam ) {
                $correlatedUserAccount = $false
            } elseif ($account.gebruiker.gebruikernaam -ne $correlatedAccount.gebruikersnaam ) {
                throw "HelloID provided username [$($account.gebruiker.gebruikernaam)] differs from the existing username [$($correlatedAccount.gebruikersnaam)] of the correlated account"
            }
        }
    }
    # Verify if a user must be either [created] or just [correlated]
    if (($null -ne $correlatedEmployeeAccount) -and ($null -ne $correlatedUserAccount)) {
        $action = 'CorrelateAccount'
    } elseif ($null -ne $correlatedEmployeeAccount -and ($null -eq $correlatedUserAccount)) {
        $action = 'CreateUser'
    } else {
        $action = 'CreateAccount'
    }
    
    Write-Information "determined action: [$action]"

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $action Eduarte-employee (medewerker) account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'CreateAccount' {
                Write-Information 'Creating and correlating Eduarte-employee (medewerker) account'

                $accountWithoutUser = ($account | Select-Object -Property * -ExcludeProperty gebruiker)
                $employee = New-EduarteEmployee -Account $accountWithoutUser

                if ($null -eq $employee) {
                    throw "Executing New-EduarteEmployee function failed. Check process logging"
                }
                $null = New-EduarteUser -Employee $employee -User $account.gebruiker

                $outputContext.AccountReference = [pscustomobject]@{
                    id   = $employee.id
                    user = $account.gebruiker.gebruikernaam
                }
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = $action
                        Message = "Create Eduarte-employee (medewerker) account was successful. AccountReference is: [$($outputContext.AccountReference.Id)]"
                        IsError = $false
                    })

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = $action
                        Message = "Creating Eduarte-user (gebruiker) account was successful. AccountReference is: [$($outputContext.AccountReference.User)]"
                        IsError = $false
                    })
                $outputContext.Data = $employee
                break
            }
            'CreateUser' {
                $null = New-EduarteUser -Employee $correlatedEmployeeAccount -User $account.gebruiker
                $outputContext.AccountReference = [pscustomobject]@{
                    id   = $correlatedEmployeeAccount.id
                    user = $account.gebruiker.gebruikernaam
                }
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'CreateAccount'
                        Message = "Creating Eduarte-user (gebruiker) account was successful. AccountReference is: [$($outputContext.AccountReference.User)]"
                        IsError = $false
                    })

                $outputContext.Data = $correlatedEmployeeAccount
                break
            }

            'CorrelateAccount' {
                Write-Information 'Correlating Eduarte-employee (medewerker) account'
                $outputContext.Data = $correlatedEmployeeAccount
                $outputContext.AccountReference = [pscustomobject]@{
                    id   = $correlatedEmployeeAccount.id
                    user = $account.gebruiker.gebruikernaam
                }
                $outputContext.AccountCorrelated = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = $action
                        Message = "Correlated account: [$($account.gebruiker.gebruikernaam)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                        IsError = $false
                    })

                break
            }
        }
    }
    $outputContext.success = $true
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Eduarte-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Eduarte-employee (medewerker) account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate Eduarte-employee (medewerker) account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
