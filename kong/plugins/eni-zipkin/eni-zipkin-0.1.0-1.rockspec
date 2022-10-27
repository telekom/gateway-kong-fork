package = "eni-zipkin"
version = "0.1.0-1"

source = {
  url = "https://ceiser-wbench.workbench.telekom.de/gitlab/tif/ops/images/kong-plugins/-/archive/1.0.1/kong-plugins-1.0.1.zip",
  dir = "eni-zipkin",
}

description = {
  summary = "This plugin allows Kong to propagate Zipkin headers and report to a Zipkin server",
  homepage = "https://ceiser-wbench.workbench.telekom.de/gitlab/tif/ops/images/kong-plugins",
  license = "private",
}

dependencies = {
  "lua >= 5.1",
  "lua-cjson",
  "lua-resty-http >= 0.11",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.eni-zipkin.handler"] = "kong/plugins/zipkin/handler.lua",
    ["kong.plugins.eni-zipkin.reporter"] = "kong/plugins/zipkin/reporter.lua",
    ["kong.plugins.eni-zipkin.span"] = "kong/plugins/zipkin/span.lua",
    ["kong.plugins.eni-zipkin.tracing_headers"] = "kong/plugins/zipkin/tracing_headers.lua",
    ["kong.plugins.eni-zipkin.schema"] = "kong/plugins/zipkin/schema.lua",
    ["kong.plugins.eni-zipkin.request_tags"] = "kong/plugins/zipkin/request_tags.lua",
  },
}
