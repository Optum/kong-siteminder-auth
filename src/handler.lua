local url = require "socket.url"
local http = require "resty.http"
local ck = require "resty.cookie"
local mlcache = require "resty.mlcache"
local kong = kong
local find = string.find


local ngx_encode_base64 = ngx.encode_base64
local fmt = string.format


local KongSiteminder = {}


KongSiteminder.PRIORITY = 998
KongSiteminder.VERSION = "1.0.0"

local parsed_urls_cache = {}


-- Parse host url.
-- @param `url` host url
-- @return `parsed_url` a table with host details:
-- scheme, host, port, path, query, userinfo


local function parse_url(host_url)
  local parsed_url = parsed_urls_cache[host_url]

  if parsed_url then
    return parsed_url
  end

  parsed_url = url.parse(host_url)
  if not parsed_url.port then
    if parsed_url.scheme == "http" then
      parsed_url.port = 80
    elseif parsed_url.scheme == "https" then
      parsed_url.port = 443
    end
  end
  if not parsed_url.path then
    parsed_url.path = "/"
  end

  parsed_urls_cache[host_url] = parsed_url

  return parsed_url
end


-- Sends the provided payload (a string) to the configured plugin host
-- @return true if everything was sent correctly, falsy if error
-- @return error message if there was an error
local function send_payload(self, conf, sitemindertoken)
  local method = conf.method
  local timeout = conf.timeout
  local keepalive = conf.keepalive
  local content_type = conf.content_type
  local http_endpoint = conf.siteminder_endpoint

  local payload = "<authorizationRequest><action>POST</action><resource>/OIDAuthentication</resource><sessionToken>" .. (sitemindertoken or "") .. "</sessionToken></authorizationRequest>"

  local ok, err
  local parsed_url = parse_url(http_endpoint)
  local host = parsed_url.host
  local port = tonumber(parsed_url.port)

  local httpc = http.new()
  httpc:set_timeout(timeout)
  ok, err = httpc:connect(host, port)
  if not ok then
    return nil, "failed to connect to " .. host .. ":" .. tostring(port) .. ": " .. err
  end

  if parsed_url.scheme == "https" then
    local _, err = httpc:ssl_handshake(true, host, false)
    if err then
      return nil, "failed to do SSL handshake with " ..
                  host .. ":" .. tostring(port) .. ": " .. err
    end
  end

  local res, err = httpc:request({
    method = method,
    path = parsed_url.path,
    query = parsed_url.query,
    headers = {
      ["Host"] = parsed_url.host,
      ["Content-Type"] = content_type,
      ["Content-Length"] = #payload,
      ["Cookie"] = "SMSESSION=" .. (sitemindertoken or ""),
    },
    body = payload,
  })
  if not res then
    return nil, "Failed request to " .. host .. ":" .. tostring(port) .. ": " .. err
  end

  -- always read response body, even if we discard it without using it on success
  local response_body = res:read_body()

  -- Evaluate response body payload for success or failure
  if not find(response_body, "Authorization successful") then
    return nil, "Failed to authenticate to Siteminder: " ..  response_body
  end


  ok, err = httpc:set_keepalive(keepalive)
  if not ok then
    -- the batch might already be processed at this point, so not being able to set the keepalive
    -- will not return false (the batch might not need to be reprocessed)
    kong.log.err("Failed keepalive for ", host, ":", tostring(port), ": ", err)
  end

  return response_body, nil
end

function KongSiteminder:init_worker()

  local sitemindercache, err = mlcache.new("kong_sm_cache", "kong_sm_cache", {
    shm_miss         = "kong_sm_cache_miss",
    shm_locks        = "kong_sm_cache_locks",
    shm_set_retries  = 3,
    lru_size         = 1000,
    ttl              = 43200,
    neg_ttl          = 30,
    resty_lock_opts  = {exptime = 10, timeout = 5,},
  })

  if not sitemindercache then
    kong.log.err("failed to instantiate siteminder mlcache: " .. err)
    return
  end

  kong.siteminder_cache = sitemindercache
end



function KongSiteminder:access(conf)

  local cookie, err = ck:new()
  if not cookie then
      ngx.log(ngx.ERR, err)
      return
  end

   -- get single cookie
  local sitemindertoken, err = cookie:get("SMSESSION")
  if not sitemindertoken then
      sitemindertoken = kong.request.get_header("siteminderToken")
      if sitemindertoken == nil and conf.authenticated_group == nil then
       return kong.response.exit(401, { message = "Unauthorized" })
      end
  end

  local xml, err = kong.siteminder_cache:get((sitemindertoken or ""), { ttl = 120 }, send_payload, self, conf, (sitemindertoken or ""))
  if err and conf.authenticated_group == nil then -- Not Multi-auth go ahead and fail out due to error
   kong.log.err(err)
   return kong.response.exit(401, { message = err })
  elseif err and conf.authenticated_group then -- Multi-auth and this plugin failed to auth so break out of plugin allow acl to fail it.
   return  
  end
  
  --Success, add support for multi-auth, plays nice with programmatic auth and acl plugin, success case
  if xml then
    if conf.authenticated_group == "by_route_id" then -- Multi-auth set "group" to route_id, Optum Standard
      kong.ctx.shared.authenticated_groups = { conf.route_id }
    elseif conf.authenticated_group then -- Multi-auth set "group" to whatever custom group desired, users choice
      kong.ctx.shared.authenticated_groups = { conf.authenticated_group }
    end -- Potentially todo could be by_service_id if people use that as a pattern of auth?
  
    local openingTagToFind = "<value>"
    local closingTagToFind = "</value>"
    local userid = xml:sub(xml:find(openingTagToFind) + #openingTagToFind, xml:find(closingTagToFind) - 1)

    -- Authenticate the consumer
    ngx.ctx.authenticated_consumer = {}
    ngx.ctx.authenticated_consumer["username"] = userid  

    return kong.service.request.set_header("X-Userinfo", xml)
  end
end

return KongSiteminder
