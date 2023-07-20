-- Copyright (C) 2023 Cequence Security, Inc - All Rights Reserved
--
-- Unauthorized copying of this file, via any medium is strictly prohibited
--
-- Proprietary and confidential
--
-- Shailesh Goel, July 2023
--

--------------------------------- References ---------------------------------------------------
-- https://github.com/Kong/kong/blob/release/3.3.x/kong/plugins/http-log/handler.lua
-- https://github.com/Kong/kong/blob/release/2.8.x/kong/plugins/http-log/handler.lua
-- https://konghq.com/blog/product-releases/reworked-plugin-queues-in-kong-gateway-3-3
-- https://github.com/Kong/kong/pull/10172
-- https://github.com/Kong/kong/blob/release/3.3.x/kong/tools/queue.lua
-- https://github.com/Kong/kong/blob/release/2.8.x/kong/tools/batch_queue.lua
------------------------------------------------------------------------------------

-- Required modules --
local httpr               = require 'resty.http'

-- Constants --
local OLD_QUEUE_ID        = 'cequence-ai-unified-oldBatchQueue'
local NEW_QUEUE_ID        = 'cequence-ai-unified-newQueue'
local CACHE_KEY           = 'cequence-client-m2m-access-token'

-- Local variables --
local deprecatedQueues    = {}

local CequenceAIUnifiedHandler = {
  VERSION  = '1.0.0',
  PRIORITY = 10,
}

-- HTTP parameters
local httpParams = {
  keepalive = true,
  keepalive_timeout = 60000,
  keepalive_pool = 30,
}

local ttl = 1800
local queue_check_evaluated = false
local kong_batch_queue_construct = false

-- In future this will be configurable flag and will be set only if debugging is required.
local debug_enabled = true

-----------------------------------------------------------------------
-- Set Queue modules based on Kong version
-- Old batch_queue module was deprecated starting from 3.3x
-- https://github.com/Kong/kong/pull/10172
-- https://konghq.com/blog/product-releases/reworked-plugin-queues-in-kong-gateway-3-3
-----------------------------------------------------------------------

-- json lua implementation from https://github.com/rxi/json.lua

--[[

Copyright (c) 2020 rxi

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

--]]

local encode

local escape_char_map = {
  [ "\\" ] = "\\",
  [ "\"" ] = "\"",
  [ "\b" ] = "b",
  [ "\f" ] = "f",
  [ "\n" ] = "n",
  [ "\r" ] = "r",
  [ "\t" ] = "t",
}

local escape_char_map_inv = { [ "/" ] = "/" }
for k, v in pairs(escape_char_map) do
  escape_char_map_inv[v] = k
end


local function escape_char(c)
  return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte()))
end


local function encode_nil(val)
  return "null"
end


local function encode_table(val, stack)
  local res = {}
  stack = stack or {}

  -- Circular reference?
  if stack[val] then
    error("circular reference")
  end

  stack[val] = true
  if rawget(val, 1) ~= nil or next(val) == nil then
    -- Treat as array -- check keys are valid and it is not sparse
    local n = 0
    for k in pairs(val) do
      if type(k) ~= "number" then
      error("invalid table: mixed or invalid key types")
      end
      n = n + 1
    end

    if n ~= #val then
      error("invalid table: sparse array")
    end

    -- Encode
    for i, v in ipairs(val) do
      table.insert(res, encode(v, stack))
    end
    stack[val] = nil
    return "[" .. table.concat(res, ",") .. "]"
  else
    -- Treat as an object
    for k, v in pairs(val) do
      if type(k) ~= "string" then
      error("invalid table: mixed or invalid key types")
      end
      table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
    end

    stack[val] = nil
    return "{" .. table.concat(res, ",") .. "}"
  end
end


local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end


local function encode_number(val)
  -- Check for NaN, -inf and inf
  if val ~= val or val <= -math.huge or val >= math.huge then
    error("unexpected number value '" .. tostring(val) .. "'")
  end

  return string.format("%.14g", val)
end


local type_func_map = {
  [ "nil"   ] = encode_nil,
  [ "table"   ] = encode_table,
  [ "string"  ] = encode_string,
  [ "number"  ] = encode_number,
  [ "boolean" ] = tostring,
}


encode = function(val, stack)
  local t = type(val)
  local f = type_func_map[t]

  if f then
    return f(val, stack)
  end

  error("unexpected type '" .. t .. "'")
end

-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
  local res = {}

  for i = 1, select("#", ...) do
    res[ select(i, ...) ] = true
  end

  return res
end

local space_chars   = create_set(" ", "\t", "\r", "\n")
local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals    = create_set("true", "false", "null")

local literal_map = {
  [ "true"  ] = true,
  [ "false" ] = false,
  [ "null"  ] = nil,
}


local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[str:sub(i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end


local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if str:sub(i, i) == "\n" then
      line_count = line_count + 1
      col_count = 1
    end
  end
  error( string.format("%s at line %d col %d", msg, line_count, col_count) )
end


local function codepoint_to_utf8(n)
  -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
  local f = math.floor
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    return string.char(f(n / 64) + 192, n % 64 + 128)
  elseif n <= 0xffff then
    return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
  elseif n <= 0x10ffff then
    return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                       f(n % 4096 / 64) + 128, n % 64 + 128)
  end
  error( string.format("invalid unicode codepoint '%x'", n) )
end


local function parse_unicode_escape(s)
  local n1 = tonumber( s:sub(1, 4),  16 )
  local n2 = tonumber( s:sub(7, 10), 16 )
   -- Surrogate pair?
  if n2 then
    return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
  else
    return codepoint_to_utf8(n1)
  end
end


local function parse_string(str, i)
  local res = ""
  local j = i + 1
  local k = j

  while j <= #str do
  local x = str:byte(j)

  if x < 32 then
    decode_error(str, j, "control character in string")
  elseif x == 92 then -- `\`: Escape
    res = res .. str:sub(k, j - 1)
    j = j + 1
    local c = str:sub(j, j)
    if c == "u" then
      local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
                    or str:match("^%x%x%x%x", j + 1)
                    or decode_error(str, j - 1, "invalid unicode escape in string")
      res = res .. parse_unicode_escape(hex)
      j = j + #hex
    else
      if not escape_chars[c] then
        decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
      end
      res = res .. escape_char_map_inv[c]
    end
    k = j + 1

  elseif x == 34 then -- `"`: End of string
    res = res .. str:sub(k, j - 1)
    return res, j + 1
  end

  j = j + 1
  end

  decode_error(str, i, "expected closing quote for string")
end


local function parse_number(str, i)
  local x = next_char(str, i, delim_chars)
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  return n, x
end


local function parse_literal(str, i)
  local x = next_char(str, i, delim_chars)
  local word = str:sub(i, x - 1)
  if not literals[word] then
    decode_error(str, i, "invalid literal '" .. word .. "'")
  end
  return literal_map[word], x
end


local function parse_array(str, i)
  local res = {}
  local n = 1
  i = i + 1

  while 1 do
    local x
    i = next_char(str, i, space_chars, true)
    -- Empty / end of array?
    if str:sub(i, i) == "]" then
      i = i + 1
      break
    end
    -- Read token
    x, i = parse(str, i)
    res[n] = x
    n = n + 1
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "]" then
      break
    end
    if chr ~= "," then
      decode_error(str, i, "expected ']' or ','")
    end
  end

  return res, i
end


local function parse_object(str, i)
  local res = {}
  i = i + 1
  while 1 do
    local key, val
    i = next_char(str, i, space_chars, true)

    -- Empty / end of object?
    if str:sub(i, i) == "}" then
      i = i + 1
      break
    end

    -- Read key
    if str:sub(i, i) ~= '"' then
      decode_error(str, i, "expected string for key")
    end
    key, i = parse(str, i)

    -- Read ':' delimiter
    i = next_char(str, i, space_chars, true)
    if str:sub(i, i) ~= ":" then
      decode_error(str, i, "expected ':' after key")
    end
    i = next_char(str, i + 1, space_chars, true)

    -- Read value
    val, i = parse(str, i)
    -- Set
    res[key] = val
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1

    if chr == "}" then
      break
    end

    if chr ~= "," then
      decode_error(str, i, "expected '}' or ','")
    end
  end

  return res, i
end


local char_func_map = {
  [ '"' ] = parse_string,
  [ "0" ] = parse_number,
  [ "1" ] = parse_number,
  [ "2" ] = parse_number,
  [ "3" ] = parse_number,
  [ "4" ] = parse_number,
  [ "5" ] = parse_number,
  [ "6" ] = parse_number,
  [ "7" ] = parse_number,
  [ "8" ] = parse_number,
  [ "9" ] = parse_number,
  [ "-" ] = parse_number,
  [ "t" ] = parse_literal,
  [ "f" ] = parse_literal,
  [ "n" ] = parse_literal,
  [ "[" ] = parse_array,
  [ "{" ] = parse_object,
}


parse = function(str, idx)
  local chr = str:sub(idx, idx)
  local f = char_func_map[chr]

  if f then
    return f(str, idx)
  end

  decode_error(str, idx, "unexpected character '" .. chr .. "'")
end


function decode(str)
  if type(str) ~= "string" then
    error("expected argument of type string, got " .. type(str))
  end

  local res, idx = parse(str, next_char(str, 1, space_chars, true))
  idx = next_char(str, idx, space_chars, true)

  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end

  return res
end

--  End of Json ----------------------------------------------------------------------


-- Cequence Kong plugin --------------------------------------------------------------

local function str_split(str, split_char)
  local arr = {}
  if split_char == nil or split_char == '' then split_char = ',' end
  for w in string.gmatch(str, '([^'..split_char..']+)') do
    table.insert(arr, w)
  end
  return arr
end

function file_exists(file)
  local f = io.open(file, "rb")

  if f then
    f:close()
  end

  return f ~= nil
end

function get_batch_queue_construct_type()
  local batch_queue = os.getenv("KONG_BATCH_QUEUE")
  if batch_queue ~= nil then
    return batch_queue
  end

  local batch_queue_path = "/usr/local/share/lua/5.1/kong/tools/batch_queue.lua"
  if not file_exists(batch_queue_path) then
    return false
  end

  for line in io.lines(batch_queue_path) do
    if string.match(line, "function Queue.new%(name") then
      return true
    end
  end

  return false
end

local DeprecatedBatchQueue, NewQueue
if kong.version_num >= 3003000 then
  NewQueue = require 'kong.tools.queue'
else
  DeprecatedBatchQueue = require 'kong.tools.batch_queue'
end

--------------------------------------------------------------------
-- Change the constructor of the deprecated queue for certain old versions
-- The DeprecatedBatchQueue.new constrcutor is different for different versions of kong
-- some expect a function as the first argument and some expect queue name as the first argument
-- Plugin fails if we give incorrect arguments
-- Not able to code around the verion like -- if kong.version_num >= 3001000 then
-- because some versions like 2.8.4.1 (200841) expect name as first argument
-- while 2.8.1.0 (200810) expects a function as the first argument and does not expect a name
-- and code will fail if we say above version 3.1 (300100) because 200841 is lower
-- So, need to look inside kong's modules while running the install script
-- to pick the right constructor depending on the version
-- can also try something like debug.getinfo() to calculate during runtime
-- but it might be too much determining every time the plugin runs
-- so, better to set the constructor just once while installing the plugin
-- by making the below true
--------------------------------------------------------------------
local deprecatedBatchQueueopts, newQueueopts

local function setQueueOptions(conf)
  -------------------------------------------------------
  -- see readme.md for more details
  -------------------------------------------------------
  -- maximum number of entries in one batch (default 1 if batch processing is disabled)
  local max_batch_size = conf.batch_processing_enabled and conf.max_batch_size or 1

  -- Set options for old Deprecated Batch Queue
  -- https://github.com/Kong/kong/blob/release/2.8.x/kong/tools/batch_queue.lua
  deprecatedBatchQueueopts = {
    -- number of times to retry processing (default 0)
    retry_count = conf.retry_count_pre_v_3_3x or 7,

    -- max number of entries that can be queued before queued is drained (default 1000)
    batch_max_size = max_batch_size,

    -- in seconds, how often the current batch is closed & queued (default 1)
    process_delay = conf.process_delay_pre_v_3_3x or 5,

    -- in seconds, time delay for each batch of queued records.
    flush_timeout = conf.flush_timeout_pre_v_3_3x or 5,

    -- max number of batches that can be queued before the oldest batch is dropped
    max_queued_batches = conf.max_queued_batches_pre_v_3_3x or 500,
  }

  -- Set options for New updated Queue 
  -- https://github.com/Kong/kong/blob/master/kong/tools/queue.lua
  newQueueopts = {
    name = NEW_QUEUE_ID,
    log_tag = 'cequence-ai-unified passive integration plugin v2',
    -- maximum number of entries in one batch (default 1)
    max_batch_size = max_batch_size,
    -- max seconds after first entry before a batch is sent (default 1)
    max_coalescing_delay = conf.max_coalescing_delay_post_v_3_3x or 5,
    -- maximum number of entries on the queue (default 10000)
    max_entries = conf.max_entries_post_v_3_3x or 10000,
    -- maximum number of bytes on the queue (default nil) 
    -- max_bytes = 100,

    -- delay when retrying a failed batch, doubles for each subsequent retry (def: 0.01)
    initial_retry_delay = conf.initial_retry_delay_post_v_3_3x or 1,

    -- max seconds before a failed batch is dropped (default 60)
    max_retry_time = conf.max_retry_time_post_v_3_3x or 120,

    -- max delay between send attempts, caps exponential retry (default 60)
    max_retry_delay = conf.max_retry_delay_post_v_3_3x or 60,
  }
end

-- get epoch time with milliseconds
local function getCurrentEpochTimeMillis()
  local currentTimeSeconds = os.time()
  local currentClockSeconds = os.clock()
  local currentMillis = math.floor(currentClockSeconds * 1000)
  
  return string.format("%.3f", currentTimeSeconds + (currentMillis / 1000))
end

-- Function for generating a UUID
local function get_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- Function for retrieving the access token
local function get_m2m_access_token(conf)
  local httpc = httpr.new()
  httpc:set_timeout(3000)

  local tokenReq = string.format(
    "grant_type=client_credentials&client_id=%s&client_secret=%s",
    conf.client_id,
    conf.client_secret
  )

  local tokenParams = setmetatable({
    method = 'POST',
    body = tokenReq,
    headers = {
      ['Content-Type'] = 'application/x-www-form-urlencoded',
    }
  }, { __index = httpParams })

  -- to track retries
  local retryCount = 0

  -- Maximum number of retries
  local maxRetryCount = 5

  -- Maximum delay between retries (in milliseconds)
  local maxRetryDelay = 15000

  -- Maximum overall time to retry (in milliseconds)
  local maxOverallRetryTime = 60000
  -- Initial retry delay (in milliseconds)
  -- Initial retry delay (in milliseconds)
  local retryDelay = 1000

  -- Start timestamp for tracking overall retry time.
  local startTimestamp = ngx.now() * 1000
  local token_url = string.format("https://%s/auth/realms/%s/protocol/openid-connect/token",
                                  conf.auth_domain, conf.realm)

  kong.log("Cequence: Token URL is - " .. token_url)

  while retryCount < maxRetryCount do
    local res, err = httpc:request_uri(token_url, tokenParams)

    if res and res.status == 200 then
      kong.log("Cequence: Unified token request successful. Token will be cached for reuse.")
      local token = decode(res.body)['access_token']
      if not token then
        return nil
      end

      local telems = str_split(token, '.')
      local json_str = ngx.decode_base64(telems[2])
      local json_obj = decode(json_str)
      local exp_time = json_obj["exp"]
      ttl = (exp_time - os.time())
      kong.log(string.format("Cequence: Value of ttl %d - ", ttl))
      return token
    end

    kong.log(string.format("Cequence: Failed to retrieve token. Retry in %dms.", retryDelay))
    ngx.sleep(retryDelay / 1000)  -- Sleep for retryDelay milliseconds

    retryCount = retryCount + 1
    retryDelay = retryDelay * 2  -- Exponential backoff: double the retryDelay for each attempt

    -- Check if the overall retry time has exceeded the maximum allowed time
    if (ngx.now() * 1000) - startTimestamp > maxOverallRetryTime then
      return nil, "Cequence: Failed to retrieve access token within the maximum overall retry time"
    end

    -- Check if the maximum retry delay has been reached
    if retryDelay > maxRetryDelay then
      retryDelay = maxRetryDelay
    end
  end

  return nil, "Cequence: Token retrieve failed. Maximum retry count reached. Will retry again"
end

-- Function for sending entries
local function send_entries_to_cequence(conf, entries)
  local httpc = httpr.new()
  httpc:set_timeout(3000)

  local payload = ''
  local array
  if not conf.batch_processing_enabled then
    assert(
      #entries == 1,
      "internal error, received more than one entry when max_batch_size is 1"
    )
    payload = encode(entries[1])

  else
    payload = encode({data = entries})

  end

  -- Retrieve the access token from the cache
  local token, tokenErr = kong.cache:get(
    CACHE_KEY,
    {
      ttl = ttl - 60, -- caching for a minute less to avoid expired tokens
      neg_ttl = 1,
    },
    get_m2m_access_token, conf)

  if not token then
    kong.log.err("Cequence: Unified token request failed with error -  ", tokenErr)
    return nil, tokenErr
  end

  if debug_enabled then
    local transactionIds = {}

    -- Define the regex pattern to match transaction IDs
    local pattern = '"transaction%-id"%s*:%s*"([^"]+)"'

    -- Iterate over matches and extract transaction IDs
    for match in payload:gmatch(pattern) do
      table.insert(transactionIds, match)
    end

    local batch_type = (conf.batch_processing_enabled and 'bulk' or 'single')
    kong.log("Cequence: Unified " .. batch_type .. " event request with " ..
             #transactionIds .. " transactions id(s)::: ", encode(transactionIds))
  end

  -- kong.log("Cequence: Unified payload " .. payload)

  -- Prepare the headers and request parameters
  local eventParams = setmetatable({
    method = 'POST',
    body = payload,
    headers = {
      ['Content-Type'] = 'application/json',
      ['Authorization'] = 'Bearer ' .. token,
    },
  }, { __index = httpParams })

  -- Send the event request to the remote server
  local endpoint = (conf.batch_processing_enabled and '/api-transactions' or '/api-transaction')
  local url = 'https://' .. conf.edge_domain .. endpoint
  local res, eventErr = httpc:request_uri(url, eventParams)

  if not res then
    kong.log.err("Cequence: Unified event request failed with err  ", eventErr)
    return nil, eventErr
  end

  kong.log("Cequence: Unified event response is  ", res.body)
  return true
end

-- Function for creating a deprecated queue
local function create_queue_pre_v3_3(conf)
  local process = function(entries)
    return send_entries_to_cequence(conf, entries)
  end

  local deprecated_queue, err

  if queue_check_evaluated == false then
    kong_batch_queue_construct = get_batch_queue_construct_type()
    queue_check_evaluated = true
  end

  if  kong_batch_queue_construct == true then
    deprecated_queue, err = DeprecatedBatchQueue.new('cequence-ai-unified', process,
                                                     deprecatedBatchQueueopts)
  else
    deprecated_queue, err = DeprecatedBatchQueue.new(process, deprecatedBatchQueueopts)
  end

  if not deprecated_queue then
    kong.log.err("Cequence: Could not create deprecated_queue with err  ", err)
    return nil, err
  end

  return deprecated_queue
end

-- Function for retrieving the deprecated queue
local function get_deprecated_queue(conf)
  local deprecated_queue = deprecatedQueues[OLD_QUEUE_ID]
  local deprecated_queue_state = 'existing'
  if not deprecated_queue then
    kong.log.debug("Cequence: Creating a new cequence deprecated_queue .. ")
    deprecated_queue_state = 'new'
    deprecated_queue = create_queue_pre_v3_3(conf)
    deprecatedQueues[OLD_QUEUE_ID] = deprecated_queue
  end

  return deprecated_queue, deprecated_queue_state
end

-- Function for processing an entry
local function process_entry(conf, entry)
  setQueueOptions(conf)
  
  if kong.version_num >= 3003000 then    
    local ok, err = NewQueue.enqueue( newQueueopts, send_entries_to_cequence, conf, entry )
    if not ok then
      kong.log.err("Cequence: (New queue) Failed to enqueue log entry to server with err ", err)
    end
  else
    local deprecated_queue, deprecated_queue_state = get_deprecated_queue(conf)
    if deprecated_queue then
      kong.log.debug("Cequence: Adding entry to ", 
                     deprecated_queue_state, 
                     " cequence deprecated_queue .... ")
      deprecated_queue:add(entry)
    end
  end
end

-- encode headers into a json array of strings like [ "header1 : base64_encoded_value1" ]
local function getbase64EncodedHeadersArray(headers)
  local base64EncodedHeaders = {}

  for name, value in pairs(headers) do
    if type(value) == "table" then
    for _, v in ipairs(value) do
      local encodedValue = ngx.encode_base64(v)
      local headerString = string.format("%s:%s", name, encodedValue)
      table.insert(base64EncodedHeaders, headerString)
    end
    else
    local encodedValue = ngx.encode_base64(value)
    local headerString = string.format("%s:%s", name, encodedValue)
    table.insert(base64EncodedHeaders, headerString)
    end
  end
  
  return base64EncodedHeaders
  end

-- Access phase handler function
function CequenceAIUnifiedHandler:access()
  if kong.version_num < 2007000 then
    kong.service.request.enable_buffering()
  end
  kong.ctx.plugin.cequence_trn_id = ngx.var.request_id and ngx.var.request_id or get_uuid()
  -- Commenting for now as its not required.
  -- kong.service.request.set_header('X-Cequence-Kong-Transaction-Id', kong.ctx.plugin.cequence_trn_id)

  -- Invalidate cache if needed
  local invalidate_header = kong.request.get_header('cequence-token-cache-invalidate') or ''
  if ( invalidate_header == 'true' ) then
    kong.log("Cequence: Invalidating cequence token cache ..... ")
    kong.cache:invalidate(CACHE_KEY)	
  end

  -- Store cequence data for the request
  kong.ctx.plugin.cequence_data = {
    ['timestamp'] = getCurrentEpochTimeMillis(),
    ['version'] = '0.1',
    ['transaction-id'] = kong.ctx.plugin.cequence_trn_id,
    request = {
      -- This is not working as per the expection of cequence framework, commenting for now
      -- ['client-ip'] = kong.client.get_forwarded_ip(),
      ['http-version'] = tostring( kong.request.get_http_version() or '' ),
      ['http-method'] = kong.request.get_method(),
      ['uri-query-fragment'] = kong.request.get_path_with_query(),
      ['host'] = kong.request.get_forwarded_host(),
      connection = {
      ['connection-ip'] = ngx.var.remote_addr,
      ['connection-port'] = tonumber(ngx.var.remote_port),
      ['server-ip'] = ngx.var.server_addr,
      ['server-port'] = tonumber(ngx.var.server_port),
      ['transaction-depth'] = tonumber(ngx.var.connection_requests),
      },
      headers = getbase64EncodedHeadersArray( kong.request.get_headers() ),
      body = {
      ['length'] = string.len( kong.request.get_raw_body() ),
      ['data'] = ngx.encode_base64( kong.request.get_raw_body() )
      },
    },
    response = {
      ['status-code'] = '',
      headers = {},
      body = {
      ['length'] = 0,
      ['data'] = ''
      },
    },
  }
end

-- Header filter phase handler function
function CequenceAIUnifiedHandler:header_filter()
  if (kong.ctx.plugin.cequence_data == nil) then
    return
  end

  -- Update cequence data with response headers
  kong.ctx.plugin.cequence_data.response['status-code'] = tostring(kong.response.get_status())
  kong.ctx.plugin.cequence_data.response.headers =
    getbase64EncodedHeadersArray(kong.response.get_headers())
end

-- Body filter phase handler function
function CequenceAIUnifiedHandler:body_filter()
  -- Update cequence data with response body
  local respBody

  if (kong.ctx.plugin.cequence_data == nil) then
    return
  end

  if kong.version_num < 2007000 then
    respBody = kong.service.response.get_raw_body()
  else
    respBody = kong.response.get_raw_body()
  end

  if respBody then
    kong.ctx.plugin.cequence_data.response.body.length = string.len(respBody)
    kong.ctx.plugin.cequence_data.response.body.data = ngx.encode_base64(respBody)
  end
end

-- Log phase handler function
function CequenceAIUnifiedHandler:log(conf)
  if (kong.ctx.plugin.cequence_data == nil) then
    return
  end

  -- Log the entry for processing
  kong.log("Cequence: Unified entry transaction id pushed for processing is ",
           kong.ctx.plugin.cequence_trn_id)
  -- kong.log("Cequence: Unified entry pushed for processing is ", entry)
  -- Process the entry

  process_entry(conf, kong.ctx.plugin.cequence_data)
end

return CequenceAIUnifiedHandler
