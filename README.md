
# HelloID-Conn-Prov-Target-Eduarte-Employee

> [!IMPORTANT]
> This connector is not tested with HelloID or with a Eduarte environment!

> [!IMPORTANT]
> This connector is not completly finished, it's still required to create the compare in the update script.

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://www.eduarte.nl/wp-content/uploads/2018/06/eduarte-logo.png">
  </p>

## Table of contents

- [HelloID-Conn-Prov-Target-test](#helloid-conn-prov-target-test)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
  - [Setup the connector](#setup-the-connector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Eduarte-Employee_ is a _target_ connector. Eduarte-Employee provides a set of SOAP API's that allow you to programmatically interact with its data. This connector only correlates HelloID persons with an employee and user account in eduarte.

The following lifecycle events are available:

| Event  | Description | Notes |
|---	 |---	|---	|
| create.ps1 | Create the employee and user account | - |
| update.ps1 | Update the employee account | - |
| enable.ps1 | Enable the employee account | - |
| disable.ps1 | Disable the employee account | - |
| delete.ps1 | n/a | - |

## Getting started

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _test_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value                             |
    | ------------------------- | --------------------------------- |
    | Enable correlation        | `True`                            |
    | Person correlation field  | `PersonContext.Person.ExternalId` |
    | Account correlation field | ``                                |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| ApiKey       | The ApiKey to connect to the API   | Yes         |
| BaseUrl      | The URL to the API                 | Yes         |

### Prerequisites

### Remarks
- There is currently no comparison implemented. If this is required for the implementation, it needs to be added. This comparison is listed as a ToDo comment in the Update.ps1
- the connector facilitates the creation of an employee account as well as an user account. The user account can only be created after the employee account is created. This is because the id of the employee account is necessary in the user account
- the connector utilizes a sort function in the create and update script. This is because the api expects the properties of the xml object to be in alphabetical order.
- The current implementation uses `custom.person.afkortingscode` in the field mapping for `afkorting`. Populate this with the value needed for your implementation.
- The field mapping uses `gebruiker.` and `contactgegevens.` to create nested objects.
- By default, the connector correlates with the username and uses it as the account reference. It also assigns the employee a username during the correlation process. However, this could be different in your Eduarte environment. There is an alternative option to correlate using the abbreviation and use that as the account reference. Please verify this during implementation.


  In the code example below you can find a function that retrieves the employee based on the abbreviation

```
function Get-EduarteMedewerkerWithAbbreviation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Abbreviation
    )
    process {
        try {
            Write-Information "Getting Eduarte employee for: [$($Abbreviation)]"

            [xml]$soapEnvelope = '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:api="http://api.algemeen.webservices.eduarte.topicus.nl/">
    <soapenv:Header/>
    <soapenv:Body>
    <api:getMedewerkerMetAfkorting>
    </api:getMedewerkerMetAfkorting>
    </soapenv:Body>
</soapenv:Envelope>'

            $element = $soapEnvelope.envelope.body.ChildNodes | Where-Object { $_.LocalName -eq 'getMedewerkerMetAfkorting' }
            $element | Add-XmlElement -ElementName 'apiSleutel' -ElementValue "$($actionContext.configuration.ApiKey)"
            $element | Add-XmlElement -ElementName 'afkorting' -ElementValue "$($Abbreviation)"

            $splatGetEmployee = @{
                Method          = 'POST'
                Uri             = "$($actionContext.configuration.BaseUrl.TrimEnd('/'))/services/api/algemeen/medewerkers"
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
            $employee = $rawResponse.getMedewerkerMetAfkortingResponse.medewerker

            if ([String]::IsNullOrEmpty($employee)) {
                return $null
            }
            else {
                Write-Information "Correlated Eduarte employee for: [$($Abbreviation)]"

                return $employee
            }
        }
        catch {
            throw $_
        }
    }
}
```

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/