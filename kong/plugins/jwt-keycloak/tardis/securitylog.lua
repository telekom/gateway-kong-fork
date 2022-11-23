local errlog = require "ngx.errlog"

local function security_event(event_code, event_details)
    errlog.raw_log(ngx.DEBUG, '[security-event] code=' .. event_code .. ', details=' .. event_details)
    ngx.var.sec_event_code=event_code
    ngx.var.sec_event_details=event_details
end

local function collect_tardis_data(jwt)
    ngx.var.tardis_consumer="anonymous"
    if jwt and jwt.claims then
      local clientId = jwt.claims["clientId"]
      if type(clientId) == "string" then
        ngx.var.tardis_consumer=clientId
      end
    end
end

return {
    security_event = security_event,
    collect_tardis_data = collect_tardis_data
}
