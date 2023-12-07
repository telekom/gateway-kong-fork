<!--
SPDX-FileCopyrightText: 2023 Deutsche Telekom AG

SPDX-License-Identifier: CC0-1.0
-->

# Stargate and Kong plugins
In this document we will talk about the Kong gateway plugins and how Stargate uses them to provide its features.

Last updated on 2023-11-03.

## Contents
- What are Kong plugins and why do we use them
- Custom plugins of Stargate
    - Prometheus
    - JWT
    - Zipkin

## What are Kong plugins and why do we use them
Kong is an API gateway with strong support for plugins.
These additional modules can extend or customize the gateways behavior to fit business requirements.
For more details, please see the official [documentation](https://docs.konghq.com/gateway/latest/kong-plugins/).

Stargate uses Kong plugins to facilitate some of its features, like for example:
- security - ACL plugin
- provide external authentication for upstream APIs - Request transformer plugin
- gather observability data - Prometheus and Zipkin plugins
- support OAuth features - JWT Keycloak plugin
- rate limiting
- request size limiting
- cors

All plugins with or without customizations are bundled in the docker image.

## Customization of plugins for Stargate
### Prometheus
- official website - https://docs.konghq.com/hub/kong-inc/prometheus/
#### Customization
- we are using version 3.1 with some features backported from 2.8 (for example the way we collect the number of connections etc.)
- in addition to data already provided in the metrics, we are adding the HTTP method
- the HTTP method is included in the response of the metrics endpoint exposed by the plugin, we did not create a whole new metrics
```lua
  metrics.status = prometheus:counter("http_requests_total",
    "HTTP status codes per consumer/method/route in Kong",
    {"route", "method", "consumer", "source", "code"})
```
- in general there are no functional changes to the plugin itself, only extended data in the metrics endpoint response

### Zipkin
- official website - https://docs.konghq.com/hub/kong-inc/zipkin/
- we are currently considering the replacement of Zipkin with OpenTelemetry, so it might be the tracing solution in the future
- we are currently not using the queueing feature of Zipkin
- our spans are using the B3 format
#### Customization
- originally, every request reported 8 spans - 3 for kong and 5 for the jumper component, we combined the 3 kong spans into one
    - since we have disabled the kong balancer, we are only using the Request and Proxy spans, while the relevant balancer span events are moved to the proxy span
- replaced the kong consumer id by kong consumer name which is more human-readable
- related to Horizon - the eventing component - we added the publisher and subscriber id - to improve readability and make it easier to debug problems
- added the X-tardis-traceid - included in all spans - helps to collect all spans related to the lifecycle of a request across all T‧AR‧D‧I‧S components
- added the X-tardis-consumer-side tag which helps identify the first span of the request and this then helps calculate how long it took T‧AR‧D‧I‧S to handle the request

### JWT Keycloak
- official website - https://github.com/gbbirkisson/kong-plugin-jwt-keycloak
- this plugin is not directly bundled with Kong, so we are explicitly including it
#### Customization
- we added extensive logging of events when the authentication fails
- we call this feature the security log
- it covers most of the scenarios that can happen, including
    - public key not available
    - invalid token signature
    - missing token
    - expired token
    - verification of scopes/roles
- the additional data is added to the kong log entry
- this is very helpful when either trying to solve a problem or even detect possible attacks

## Code of Conduct

This project has adopted the [Contributor Covenant](https://www.contributor-covenant.org/) in version 2.1 as our code of conduct. Please see the details in our [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). All contributors must abide by the code of conduct.

By participating in this project, you agree to abide by its [Code of Conduct](./CODE_OF_CONDUCT.md) at all times.

## Licensing

This project follows the [REUSE standard for software licensing](https://reuse.software/).
Each file contains copyright and license information, and license texts can be found in the [./LICENSES](./LICENSES) folder. For more information visit https://reuse.software/.

### REUSE

For a comprehensive guide on how to use REUSE for licensing in this repository, visit https://telekom.github.io/reuse-template/.   
A brief summary follows below:

The [reuse tool](https://github.com/fsfe/reuse-tool) can be used to verify and establish compliance when new files are added. 

For more information on the reuse tool visit https://github.com/fsfe/reuse-tool.

**Check for incompliant files (= not properly licensed)**

Run `pipx run reuse lint`

**Get an SPDX file with all licensing information for this project (not for dependencies!)**

Run `pipx run reuse spdx`

**Add licensing and copyright statements to a new file**

Run `pipx run reuse annotate -c="<COPYRIGHT>" -l="<LICENSE-SPDX-IDENTIFIER>" <file>`

Replace `<COPYRIGHT>` with the copyright holder, e.g "Deutsche Telekom AG", and `<LICENSE-SPDX-IDENTIFIER>` with the ID of the license the file should be under. For possible IDs see https://spdx.org/licenses/.

**Add a new license text**

Run `pipx run reuse download --all` to add license texts for all licenses detected in the project.

