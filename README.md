
# HelloID-Conn-Prov-Target-Eduarte-Medewerker

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Eduarte-Employee/blob/main/Logo.png?raw=true">
  </p>

## Table of contents

- [HelloID-Conn-Prov-Target-Eduarte-Medewerker](#helloid-conn-prov-target-eduarte-medewerker)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
      - [Concurrent actions](#concurrent-actions)
      - [Employee and User account](#employee-and-user-account)
      - [Active status](#active-status)
      - [API specifications](#api-specifications)
      - [FieldMapping](#fieldmapping)
  - [Setup the connector](#setup-the-connector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Eduarte-Employee_ is a _target_ connector. Eduarte-Employee provides a set of SOAP API's that allow you to programmatically interact with its data. This connector create and correlates HelloID persons with an employee and user account in eduarte.

The following lifecycle events are available:

| Event                                  | Description                                         |
| -------------------------------------- | --------------------------------------------------- |
| create.ps1                             | Create the employee and user account                |
| update.ps1                             | Update the employee account and create user account |
| enable.ps1                             | Enable the User account                             |
| disable.ps1                            | Disable the User account                            |
| delete.ps1                             | Disable the User account                            |
| permissions/roles/permissions.ps1      | List roles as permissions                           |
| permissions/roles/revokePermission.ps1 | Grant roles to an account                           |
| permissions/roles/grantPermission.ps1  | Revoke roles from an account                        |
| configuration.json                     | Default _configuration.json_                        |
| fieldMapping.json                      | Default _fieldMapping.json_                         |

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Eduarte-Employee/refs/heads/main/Icon.png
```

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
    | Account correlation field | `afkorting`                       |

> [!NOTE]
> *The connectors correlates the **User** account with the property `gebruiker.gebruikernaam`*

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Connection settings

The following settings are required to connect to the API.

| Setting | Description                      | Mandatory |
| ------- | -------------------------------- | --------- |
| ApiKey  | The ApiKey to connect to the API | Yes       |
| BaseUrl | The URL to the API               | Yes       |

### Prerequisites
- Create a custom property for the field mapping for correlation. A Person property named `personAfkortingscode`.

### Remarks

#### Concurrent actions
> [!IMPORTANT]
> Granting and revoking roles is done by editing roles after receiving the roles from an account. For this reason, the concurrent actions need to be set to `1`.

#### Employee and User account
- The connector facilitates the creation of both an employee account and a user account. The user account is dependent on the employee account and can only be created once the employee account exists.
- The user account is created during the initial creation process and will be re-created during updates if the account has been removed.
- The `gebruikersnaam` property in the employee object will appear once the user account is created.
- The connector checks if the existing `gebruikersnaam` differs from the desired username in HelloID. If a discrepancy is found, an error is thrown, which must be resolved manually.

#### Active status
- The employee object will be created in an active state and will not be set to inactive during its lifecycle.
- The BeginDate determines the Active property, although the Active property is mandatory in the API.
- The enable and disable scripts only enable or disable the user account, leaving the employee account untouched.

#### API specifications
- The connector uses a sort function in the create and update scripts because the API expects the properties of the XML object to be in alphabetical order, except for `contactgegevens`.
- The functions `Name` and `Code` should be existing functions within Eduarte.
- Username (`Gebruikersnaam`) changes are supported by the API through a specific web request, but this functionality is not implemented in the connector.
- The `afkorting` property is unique during account creation. However, it can be updated during an account update, which can result in duplicate accounts.
  - When this occurs, the correlation action fails because the function `getMedewerkerMetAfkorting` no longer returns the account, leading the connector to assume that the account does not exist and attempting to create a new one.


#### FieldMapping
- The field mapping includes `gebruiker`. and `contactgegevens`. objects to create nested structures. These mappings are hardcoded, sorted, and compared within the connector. Therefore, any changes to these mappings require a code adjustment.
- The current field mapping implements a custom field, `Person.Custom.personAfkortingscode`. This may be necessary based on the customer's requirements, but it depends on their specific implementation. In some cases, the ExternalId might also be a suitable alternative.

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
