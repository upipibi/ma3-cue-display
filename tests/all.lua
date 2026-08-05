package.path = "./?.lua;./src/?.lua;./tests/?.lua;" .. package.path

local runner = require("runner")

require("test_json")
require("test_state")
require("test_http")

runner.report()
