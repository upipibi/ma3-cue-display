package.path = "./?.lua;./src/?.lua;./tests/?.lua;" .. package.path

local runner = require("runner")

require("test_json")

runner.report()
