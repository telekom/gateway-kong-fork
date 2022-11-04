package = "kong-plugin-eni-prometheus"
version = "1.2.1-1"

source = {
  url = "git://github.com/Kong/kong-plugin-prometheus",
  dir = "kong-plugin-eni-prometheus",
  tag = "1.2.1"
}

supported_platforms = {"linux", "macosx"}
description = {
  summary = "Prometheus metrics for Kong and upstreams configured in Kong",
  license = "Apache 2.0",
}

dependencies = {
  "lua-resty-counter >= 0.2.0",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.eni-prometheus.api"] = "kong/plugins/eni-prometheus/api.lua",
    ["kong.plugins.eni-prometheus.status_api"] = "kong/plugins/eni-prometheus/status_api.lua",
    ["kong.plugins.eni-prometheus.exporter"] = "kong/plugins/eni-prometheus/exporter.lua",
    ["kong.plugins.eni-prometheus.enterprise.exporter"] = "kong/plugins/eni-prometheus/enterprise/exporter.lua",
    ["kong.plugins.eni-prometheus.handler"] = "kong/plugins/eni-prometheus/handler.lua",
    ["kong.plugins.eni-prometheus.prometheus"] = "kong/plugins/eni-prometheus/prometheus.lua",
    ["kong.plugins.eni-prometheus.serve"] = "kong/plugins/eni-prometheus/serve.lua",
    ["kong.plugins.eni-prometheus.schema"] = "kong/plugins/eni-prometheus/schema.lua",
  }
}
