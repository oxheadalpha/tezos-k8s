## Pyrometer chart

A chart to deploy the [pyrometer](https://gitlab.com/tezos-kiln/pyrometer) Tezos monitoring tool.

Pass a complete pyrometer configuration with the `config` key in values, yaml, it will be transparently applied to pyrometer.

### Prometheus exporter

Pyrometer is a self-sustaining tool that manages its own alerts and alerting channels.

Quoting pyrometer [architecture doc](https://gitlab.com/tezos-kiln/pyrometer/-/blob/main/doc/monitoring.md):

> Primary installation target for initial monitoring implementation is a
personal computer. Consequently, implementation should prioritize
simplicity when it comes to number of individual, isolated components,
processes, their runtime dependencies,
administration/configuration.


The Prometheus exporter for Pyrometer consumes pyrometer events using webhooks and monitors only one of them: baker health status. It then aggregates the number of unhealthy bakers and exposes this as a prometheus metric.

The ServiceMonitor and PrometheusRule are also included in the chart.

This gives you:

* the concept of an active alert that can be fed into an incident management system such as pagerduty.
* the ability to monitor a baker baking for several addresses, where it is not desirable to alert for an individual unhealthy address, but only when all the configured bakers are unhealtly. The threshold is configurable in the chart.
