##################################################
# HelloID-Conn-Prov-Target-Eduarte-Employee-Create
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
    id                  = $p.ExternalId
    gebruikersnaam      = $p.UserName
    contactgegeven      = $p.Accounts.MicrosoftActiveDirectory.mail
    achternaam          = $p.Name.FamilyName
    actief              = $false
    afkorting           = ""
    begindatum          = $p.PrimaryContract.StartDate
    einddatum           = $p.PrimaryContract.EndDate
    geboorteAchternaam  = $p.Name.FamilyName
    geboorteVoorvoegsel = $p.Name.FamilyNamePrefix
    geslacht            = $p.Details.Gender
    voornamen           = $p.GivenName
    voorletters         = $p.Name.Initials
    voorvoegsel         = ""
    functie             = [PSCustomObject]@{
        code = $p.PrimaryContract.Title.Code
        naam = $p.PrimaryContract.Title.Name
    }
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
        $ParameterList = @{ }
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
    $getMedewerkerMetIdElement | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($config.ApiKey)"
    $getMedewerkerMetIdElement | Add-XmlElement -ElementName 'personeelsnummer' -ElementValue "$($account.ExternalId)"

    $splatGetEmployee = @{
        Method      = 'Post'
        Uri         = "$($config.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
        ContentType = "text/xml" 
        Body        = $soapEnvelopegetMedewerkerMetId.InnerXml
    }
    $responseEmployee = Invoke-RestMethod @splatGetEmployee -Verbose:$false

    # Todo: Check if correlation condition works as expected
    if ($null -eq $responseEmployee) {
        $action = 'Create-Correlate'
    }
    elseif ($config.updatePersonOnCorrelate -eq $true) {
        $action = 'Update-Correlate'
    }
    else {
        $action = 'Correlate'
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $action Eduarte-Employee account for: [$($p.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                [xml]$createEmployee = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
                    <soapenv:Header/>
                    <soapenv:Body>
                    <api:create>
                        <apiSleutel>X</apiSleutel>
                        <nieuweMedewerker>
                            <contactgegevens>
                                <contactgegeven>
                                    <contactgegeven>X</contactgegeven>
                                    <soort> 
                                        <code>X</code>
                                        <naam>X</naam>
                                    </soort>
                                </contactgegeven>
                            </contactgegevens>
                        </nieuweMedewerker>
                    </api:create>
                    </soapenv:Body>
                </soapenv:Envelope>'

                $createEmployee.envelope.body.create.apiSleutel = "$($config.ApiKey)"
                $createEmployee.envelope.body.create.nieuweMedewerker.contactgegevens.contactgegeven.contactgegeven = "$($account.contactgegeven)"

                $updateElement = $createEmployee.envelope.body.create.nieuweMedewerker
                ($account | Select-Object * -ExcludeProperty "contactgegeven") | Write-ToXmlDocument -XmlDocument $createEmployee -XmlParentDocument $updateElement

                $splatCreateEmployee = @{
                    Method      = 'Post'
                    Uri         = "$($config.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
                    ContentType = "text/xml" 
                    Body        = $createEmployee.InnerXml
                }

                # Todo: Check possible the response!
                $null = Invoke-RestMethod @splatCreateEmployee -Verbose:$false

                $accountReference = $account.ExternalId
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Create account was successful. AccountReference is: [$accountReference]"
                        IsError = $false
                    })

                break
            }
            'Update' {
                # Verify if the account must be updated
                # Todo change update check to your needs
                $propertiesChanged = $false
                $changedAccount = [PSCustomObject]@{}

                # compare voor het plate object en functie
                foreach ($prop in ($account | Select-Object * -ExcludeProperty contactgegeven, functie).psobject.properties ) {
                    if ($responseEmployee.Envelope.body.update.gewijzigdeMedewerker."$($prop.name)" -eq $prop.value) {
                        # Write-Verbose   "Noting Changed" -verbose
                    }
                    else {
                        # Write-Verbose "property changed: $($prop.name)" -verbose
                        $propertiesChanged = $true
                    }  
                    # write-verbose "old value: $($responseEmployee.Envelope.body.update.gewijzigdeMedewerker."$($prop.name)")" -verbose
                    # Todo check if it is necessary to add not changed value's to the XML object, otherwise remove the line below.
                    $changedAccount | Add-Member -MemberType NoteProperty -Name $prop.name -Value $prop.value  
                }
                
                if ($responseEmployee.Envelope.body.update.gewijzigdeMedewerker.functie.naam -eq $account.functie.naam) {
                    # Todo check if it is necessary to add not changed value's to the XML object, otherwise remove the line below.
                    $changedAccount | Add-Member -NotePropertyMembers @{
                        functie = $account.functie
                    }
                }
                else {
                    $propertiesChanged = $true
                    $changedAccount | Add-Member -NotePropertyMembers @{
                        functie = $account.functie
                    }        
                }

                # compare voor het email object
                # Todo: Check if the email adres can be found in the [contactgegevens]
                $mailProperty = $responseEmployee.contactgegevens.contactgegeven | Where-Object { $_.soort.naam -eq 'mail' }
                if ((-not [string]::IsNullOrEmpty($account.contactgegeven)) -and ($mailProperty.contactgegeven -ne $account.contactgegeven)) {
                    $changedEmail = $account.email
                }

                if ($propertiesChanged -or (-not [string]::IsNullOrEmpty($($changedEmail)))) {
                    # Todo check if update adds another contactgegeven or that the existing contactgegeven is updated
                    [xml]$soapEnvelopeUpdateEmployee = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.umra.webservices.eduarte.topicus.nl/">
                        <soapenv:Header/>
                        <soapenv:Body>
                            <update xmlns="http://api.algemeen.webservices.eduarte.topicus.nl/">
                                <apiSleutel>X</apiSleutel>
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
                    $soapEnvelopeUpdateEmployee.envelope.body.update.apiSleutel = "$($config.ApiKey)"

                    $updateElement = $soapEnvelopeUpdateEmployee.envelope.body.update.gewijzigdeMedewerker
                    ($changedAccount | Select-Object * -ExcludeProperty "contactgegeven") | Write-ToXmlDocument -XmlDocument $soapEnvelopeUpdateEmployee -XmlParentDocument $updateElement

                    # Todo: Check if the email adres can be found in the [contactgegevens]
                    if (-not [string]::IsNullOrEmpty($($changedEmail))) {
                        $soapEnvelopeUpdateEmployee.envelope.body.update.gewijzigdeMedewerker.contactgegevens.contactgegeven.contactgegeven = "$($account.contactgegeven)"
                    }
           
                    $splatSetEmployee = @{
                        Method      = 'Post'
                        Uri         = "$($config.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
                        Body        = $soapEnvelopeUpdateEmployee.InnerXml
                        ContentType = "text/xml"
                    }
                    # Todo: Check possible the response!
                    $null = Invoke-RestMethod @splatSetEmployee -Verbose:$false

                    $success = $true
                    $auditLogs.Add([PSCustomObject]@{
                            Message = 'Update account was successful'
                            IsError = $false
                        })
                }
                else {
                    $success = $true
                    $auditLogs.Add([PSCustomObject]@{
                            Message = 'No changes will be made to the account during enforcement'
                            IsError = $false
                        })
                }
                break
            }

            'Correlate' {
                Write-Verbose 'Correlating Eduarte employee'
                $accountReference = $responseEmployee.deelnemerNummer
                break
            }
        }
        $success = $true

    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Eduarte-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not Update Eduarte-Employee account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not Update Eduarte-Employee account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
