# Powerwall-Dashboard Usage Micro Service

This folder contains the sample setup files for a usage microservice that integrates
into Powerwall-Dashboard. This service provides a proxy that generates usage and 
cost/savings information based on utility usage plans. As of 4/6/2023, this service only
supports a general time of use plan, but the service is extensible to different plans.

For documentation on the micro-service, refer to: 
https://github.com/BuongiornoTexas/pwdusage.

The files in this folder are:

- `example_usage.json`, a sample configuration file for the microservice, which is a 
duplicate of the sample file in the `pwdusage` repository.
- `example-dashboard.json`, a sample grafana dashboard that demonstrates the output of 
the usage service with the sample configuration file.
- `Dockerfile` is the docker configuration file used to generate the containerised
microservice from the `pwdusage` python package.

The documentation for `pwdusage` details usage of these files.

