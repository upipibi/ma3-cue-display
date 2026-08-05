-- Pure HTTP: a request line in, a response string out. No sockets here, which
-- is what makes all of it testable off-console.
local M = {}

local REASONS = {
  [200] = "OK",
  [400] = "Bad Request",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [500] = "Internal Server Error",
  [503] = "Service Unavailable",
}

function M.parse_request(line)
  if type(line) ~= "string" then return nil end
  local method, target = line:match("^(%u+)%s+(%S+)%s+HTTP/1%.[01]")
  if not method then return nil end
  local path, query = target:match("^([^?]*)%??(.*)$")
  return { method = method, path = path, query = query or "" }
end

function M.query_param(query, key)
  for pair in (query or ""):gmatch("[^&]+") do
    local k, v = pair:match("^([^=]*)=?(.*)$")
    if k == key then return v end
  end
  return nil
end

function M.response(status, content_type, body)
  body = body or ""
  return table.concat({
    "HTTP/1.1 " .. status .. " " .. (REASONS[status] or "OK"),
    "Content-Type: " .. content_type,
    "Content-Length: " .. #body,
    "Cache-Control: no-store",
    -- Cheap, and it stops /api/state from failing confusingly if someone
    -- embeds it in a page served from somewhere else.
    "Access-Control-Allow-Origin: *",
    "Connection: close",
    "",
    body,
  }, "\r\n")
end

-- The page picks its own mode from location.pathname and location.search, so
-- "/" and "/debug" serve one identical document and there is no server-side
-- styling logic to keep in sync.
function M.route(req, ctx)
  if req.method ~= "GET" then
    return M.response(405, "text/plain; charset=utf-8", "method not allowed")
  end
  local p = req.path
  if p == "/" or p == "/debug" then
    return M.response(200, "text/html; charset=utf-8", ctx.html)
  elseif p == "/api/state" then
    return M.response(200, "application/json; charset=utf-8", ctx.state_json)
  elseif p == "/health" then
    return M.response(200, "text/plain; charset=utf-8", "ok " .. ctx.version)
  end
  return M.response(404, "text/plain; charset=utf-8", "not found")
end

return M
