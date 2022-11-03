local errlog = require "ngx.errlog"

local function security_event(event_code, event_details)
    errlog.raw_log(ngx.DEBUG, '[security-event] code=' .. event_code .. ', details=' .. event_details)
    ngx.var.sec_event_code=event_code
    ngx.var.sec_event_details=event_details
end

return {
    security_event = security_event
}