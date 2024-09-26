#################################################
# HelloID-Conn-Prov-Target-Eduarte-Medewerker-Permissions-Rolls
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Get-EduarteRollen {
    process {
        try {
            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
                <soapenv:Header/>
                <soapenv:Body>
                <api:getAlleRollen>
                </api:getAlleRollen>
                </soapenv:Body>
            </soapenv:Envelope>'

            $element = $soapEnvelope.envelope.body.ChildNodes | Where-Object { $_.LocalName -eq 'getAlleRollen' }
            $element | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($actionContext.Configuration.ApiKey)"

            $splatGetRollen = @{
                Method          = 'POST'
                Uri             = "$($actionContext.Configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/gebruikers"
                ContentType     = 'text/xml;charset=utf-8'
                Body            = $soapEnvelope.InnerXml
                UseBasicParsing = $true
            }

            $response = Invoke-WebRequest @splatGetRollen

            # Check if the response is valid
            if ($response.StatusCode -ne "200") {
                Write-Error "Invalid response: $($response.StatusCode)"
                return $null
            }

            $rawResponse = ([xml]$response.content).Envelope.body
            $rollen = $rawResponse.getAlleRollenResponse.rol

            if ([String]::IsNullOrEmpty($rollen)) {
                return $null
            }
            else {
                return $rollen
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
    $retrievedPermissions = Get-EduarteRollen
    Write-Information "Succesfully queried [$($retrievedPermissions.count)] permissions"

    foreach ($permission in $retrievedPermissions) {
        $outputContext.Permissions.Add(
            @{
                DisplayName    = "Rol - $($permission.naam)"
                Identification = @{
                    Name          = $permission.naam
                    Category      = $permission.categorie
                    Right         = $permission.rechtenSoort
                    Authorization = $permission.authorisatieNiveau
                }
            }
        )
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Eduarte-EmployeeError -ErrorObject $ex
        $auditMessage = "Could not retreive rolles from Eduarte. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not retreive rolles from Eduarte. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    Write-Warning $auditMessage
}
