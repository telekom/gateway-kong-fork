local prometheus = require "kong.plugins.eni-prometheus.exporter"
local kong = kong


prometheus.init()


local PrometheusHandler = {
  PRIORITY = 13,
  VERSION  = "1.2.1",
}

function PrometheusHandler.init_worker()
  prometheus.init_worker()
end


function PrometheusHandler.log(self, conf)
  local message = kong.log.serialize()

  local serialized = {}
  if conf.eni_stat then
    if message.consumer ~= nil then
      serialized.consumer = message.consumer.username
    else
      serialized.consumer = "anonymous"
    end
    if message.request and message.request.method ~= nil then
      serialized.method = message.request.method
    else
      serialized.method = "default"
    end
    serialized.customer_facing = conf.customer_facing
  end

  prometheus.log(message, serialized)
end


return PrometheusHandler
