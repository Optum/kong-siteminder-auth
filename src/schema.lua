local typedefs = require "kong.db.schema.typedefs"

return {
  name = "kong-siteminder-auth",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { siteminder_endpoint = typedefs.url({ required = true }) },
          { method = { type = "string", default = "POST", one_of = { "POST", "PUT", "PATCH" }, }, },
          { content_type = { type = "string", default = "application/xml", one_of = { "application/xml" }, }, },
          { timeout = { type = "number", default = 10000 }, },
          { keepalive = { type = "number", default = 60000 }, },
          { authenticated_group = { type = "string" }, },
      }, }, },
  },
}
