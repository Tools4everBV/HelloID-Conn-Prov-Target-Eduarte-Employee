#################################################
# HelloID-Conn-Prov-Target-Eduarte-Medewerker-RevokePermission-Rolls
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Get-EduarteGebruikerRollen {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$userName
    )
    process {
        try {
            Write-Information "Getting Eduarte rolls for: [$($userName)]"

            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
                <soapenv:Header/>
                <soapenv:Body>
                <api:getGebruikerRollen>
                </api:getGebruikerRollen>
                </soapenv:Body>
            </soapenv:Envelope>'

            $element = $soapEnvelope.envelope.body.ChildNodes | Where-Object { $_.LocalName -eq 'getGebruikerRollen' }
            $element | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($actionContext.Configuration.ApiKey)"
            $element | Add-XmlElement -ElementName 'gebruikernaam' -ElementValue "$($userName)"

            $splatGetGebruikerRollen = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/gebruikers"
                ContentType     = 'text/xml;charset=utf-8'
                Body            = $soapEnvelope.InnerXml
                UseBasicParsing = $true
            }

            $response = Invoke-WebRequest @splatGetGebruikerRollen

            # Check if the response is valid
            if ($response.StatusCode -ne "200") {
                Write-Error "Invalid response: $($response.StatusCode)"
                return $null
            }

            $rawResponse = ([xml]$response.content).Envelope.body
            $userRolls = $rawResponse.getGebruikerRollenResponse.rol.naam

            if ([String]::IsNullOrEmpty($userRolls)) {
                return $null
            }
            else {
                Write-Information "Successfully queried [$($userRolls.count)] Eduarte rolls for: [$($userName)]"

                return $userRolls
            }
        }
        catch {
            throw $_
        }
    }
}

function Add-EduarteGebruikerRollen {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$userName,

        [array]$rolls
    )
    process {
        try {
            Write-Information "Updating Eduarte rolls for: [$($userName)]"

            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
                <soapenv:Header/>
                <soapenv:Body>
                <api:wijzigGebruikerRollen>
                </api:wijzigGebruikerRollen>
                </soapenv:Body>
            </soapenv:Envelope>'

            $element = $soapEnvelope.envelope.body.ChildNodes | Where-Object { $_.LocalName -eq 'wijzigGebruikerRollen' }
            $element | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($actionContext.Configuration.ApiKey)"
            $element | Add-XmlElement -ElementName 'gebruikernaam' -ElementValue "$($userName)"
            if ($rolls -ne $null) {
                foreach ($rol in $rolls) {
                    $element | Add-XmlElement -ElementName "rollen" -ElementValue "$($rol)" -AsChildElement
                }
            }

            $splatAddGebruikerRollen = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/gebruikers"
                ContentType     = 'text/xml;charset=utf-8'
                Body            = $soapEnvelope.InnerXml
                UseBasicParsing = $true
            }

            $response = Invoke-WebRequest @splatAddGebruikerRollen

            # Check if the response is valid
            if ($response.StatusCode -ne "200") {
                Write-Error "Invalid response: $($response.StatusCode)"
            }
        }
        catch {
            throw $_
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
        $ElementValue,

        [Parameter()]
        [switch]
        $AsChildElement
    )
    process {
        try {
            $child = $XmlParentDocument.OwnerDocument.CreateElement($ElementName)

            if ($AsChildElement) {
                $grandChild = $XmlParentDocument.OwnerDocument.CreateElement('naam')
                $grandChild.InnerText = $ElementValue
                $null = $child.AppendChild($grandChild)
            }
            else {
                $child.InnerText = "$ElementValue"
            }

            $null = $XmlParentDocument.AppendChild($child)
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
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
    if ([string]::IsNullOrEmpty($($actionContext.References.Account.user))) {
        throw 'The account reference could not be found'
    }

    [array]$currentUserRolls = Get-EduarteGebruikerRollen -userName $actionContext.References.Account.user

    #region Calulate action
    if ($currentUserRolls -contains $actionContext.References.Permission.Name) {
        $action = "RevokePermission"
    }
    else {
        $action = 'NoChanges'   
    }
    Write-Information "Calculated action [$action]"
    #endregion Calulate action
   
    #region Process
    switch ($action) {
        "RevokePermission" { 
            $newUserRolls = $currentUserRolls
            $newUserRolls = $newUserRolls | Where-Object { $_ -ne $actionContext.References.Permission.Name }
   
            if (-Not($actionContext.DryRun -eq $true)) {
                Add-EduarteGebruikerRollen -userName $actionContext.References.Account.user -rolls $newUserRolls
   
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Permission with name [$($actionContext.References.Permission.Name)] revoked from account with userName [$($actionContext.References.Account.user)]."
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun: Would revoke permission with name [$($actionContext.References.Permission.Name)] from account with userName [$($actionContext.References.Account.user)]."
            }
               
            break
        }
   
        'NoChanges' {
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Permission with name [$($actionContext.References.Permission.Name)] already revoked from account with userName [$($actionContext.References.Account.user)]."
                    IsError = $false
                })
   
            break
        }
    }
    # #endregion Process
    $outputContext.success = $true
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Eduarte-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Eduarte-employee (medewerker) account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not create or correlate Eduarte-employee (medewerker) account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}