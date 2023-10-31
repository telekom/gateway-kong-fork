**Table of contents**

This document show changes done by ENI teams to original Kong.

[[_TOC_]]
## 2.8.3.9
- keep eni metrics, enable adapted metrics - provided both

## 2.8.3.8
- zipkin fix

## 2.8.3.7
- skipped due to cequence version

## 2.8.3.6
 - Bugfix: Wrong Kong version in admin API

## 2.8.3.5
 - decreased log level for msg "Mismatched header types. conf"

## 2.8.3.4
 - tracing adjusted

## 2.8.3.3
 - Prometheus plugin: use X-Pubsub-Subscriber-Id header as consumer in prometheus metrics
 - jwt-keycloak and acl plugins: Use ua-prefix to distinguish between http-code and security-events
 - Kong: Security event ua209 added in case of "404, no Route matched..."

## 2.8.3.2
 - Prometheus plugin: renamed Nginx connections for 2.8. compatibility
 - Prometheus plugin: dedicated old bucket size for ENI metrics
 - Prometheus plugin: ENI metrics source variables fixed

## 2.8.3.1
 - Updated Prometheus plugin to version from Kong 3.1.1
 - ENI version indicator added to Kong version creation

## 2.8.3.0
 - Updated Kong to 2.8.3

## 2.8.1.2
 - JWT-Keycloak plugin: collect tardis data

## 2.8.1.1
 - JWT-Keycloak plugin: set tardis_consumer variable
 - ACL plugin: Create security event 207

## 2.8.1.0
 - ENI flavoured original Zipkin (non eni-prefixed)
 - ENI flavoured original Prometheus (non eni-prefixed)
 - Added jwt-keycloak plugin
