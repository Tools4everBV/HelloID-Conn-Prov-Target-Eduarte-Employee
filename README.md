
# HelloID-Conn-Prov-Target-Eduarte-Employee
> :warning: <b> This connector is not tested with HelloID or with a Eduarte environment! </b>


| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://www.eduarte.nl/wp-content/uploads/2018/06/eduarte-logo.png">
  </p>

## Table of contents

- [HelloID-Conn-Prov-Target-Eduarte-Employee](#helloid-conn-prov-target-eduarte-employee)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
  - [Setup the connector](#setup-the-connector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Eduarte-Employee_ is a _target_ connector. Eduarte-Employee provides a set of SOAP API's that allow you to programmatically interact with its data. This connector only correlates HelloID persons with an employee Eduarte accounts and updates the Email Address or Username.

The following lifecycle events are available:

| Event  | Description | Notes |
|---	 |---	|---	|
| create.ps1 | Create-correlate, update-correlate and correlate an account Account, update Mail and Username also | - |
| update.ps1 | Update the Account | - |
| enable.ps1 | Enable the Account | - |
| disable.ps1 | Disable the Account | - |
| delete.ps1 | n/a | - |



## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| ApiKey       | The ApiKey to connect to the API   | Yes         |
| BaseUrl      | The URL to the API                 | Yes         |

### Prerequisites
 -

### Remarks
- The property email does not exist as a fixed property on the employee object. I have made an assumption about where to find it. During implementation, it still needs to be verified. It is used to check whether an update needs to take place or not.
- The scripts contains several To-do comments. Please look into these statements during implementation.
- An exception is made in the comparison of the contact details 'contactgegeven' property update. This is due to it being a complex object.

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
