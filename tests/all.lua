package.path = "./?.lua;./src/?.lua;./tests/?.lua;" .. package.path

local runner = require("runner")

require("test_json")
require("test_state")
require("test_http")
require("test_server")
require("test_ma3")

runner.report()
