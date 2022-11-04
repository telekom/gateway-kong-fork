local prometheus = require "kong.plugins.eni-prometheus.exporter"


return {
  ["/metrics"] = {
    GET = function()
      prometheus.collect()
    end,
  },
}
