local function validate_shared_dict()
  if not ngx.shared.prometheus_metrics then
    return nil,
           "ngx shared dict 'prometheus_metrics' not found"
  end
  return true
end


return {
  name = "prometheus",
  fields = {
    { config = {
        type = "record",
        fields = {
          { eni_stat = { type = "boolean", default = false }, },
          { customer_facing = { type = "string", default = "false" }, },
        },
        custom_validator = validate_shared_dict,
    }, },
  },
}
