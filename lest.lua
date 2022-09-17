local level = 0
local plan = nil
local current_path = {}

--- Get the n first elements of an array
--
-- [pure]
local elements = function (list, len)
  local new = {}
  for i = 1, len do
    new[i] = list[i]
  end
  return new
end

--- Calls cb one before all test of the describe block
function beforeAll(cb)
  if #current_path == 0 then
    plan.beforeAll = cb
  else
    local path = table.concat(elements(current_path, level), ":")
    plan.describes[path].beforeAll = cb
  end
end

--- Calls cb once after all test of the describe block
function afterAll(cb)
  if #current_path == 0 then
    plan.afterAll = cb
  else
    local path = table.concat(elements(current_path, level), ":")
    plan.describes[path].afterAll = cb
  end
end

--- Calls cb before each test of the describe block
function beforeEach(cb)
  if #current_path == 0 then
    plan.beforeEach = cb
  else
    local path = table.concat(elements(current_path, level), ":")
    plan.describes[path].beforeEach = cb
  end
end

--- Calls cb after each test of the describe block
function afterEach(cb)
  if #current_path == 0 then
    plan.afterEach = cb
  else
    local path = table.concat(elements(current_path, level), ":")
    plan.describes[path].afterEach = cb
  end
end


--- Describe unit tests
function describe(label, cb)
  level = level + 1
  current_path[level] = (current_path[level] or 0) + 1
  local path = table.concat(elements(current_path, level), ":")
  if not plan.describes[path] then
    plan.describes[path] = {}
  end
  plan.describes[path] = { label = label, its = {} }
  cb()
  level = level - 1
end

--- Run a unit test
function it(label, cb)
  local path = table.concat(elements(current_path, level), ":")
  table.insert(plan.describes[path].its, { label = label, cb = cb, result = nil })
end

local g_received = nil
local g_expected = nil
--- Creates an expectable object
function expect(received)
  g_received = received
  return {
    --- Comparison using equality operator (==)
    toBe = function (expected)
      g_expected = expected
      assert(received == expected)
    end,
    --- Comparison using inequality operator (~=)
    toNotBe = function (expected)
      g_expected = expected
      assert(received ~= expected)
    end
  }
end

--- Build test plan
local buildPlan = function (filename)
  plan = {
    filename = filename,
    describes = {},
    beforeAll = nil,
    afterAll =  nil,
    beforeEach = nil,
    afterEach = nil,
    success = true,
    passed = 0,
    failed = {},
    time = 0
  }
  local f, err = loadfile(filename)
  if not f then
    print(err)
    os.exit(1)
  else
    f()
  end
end

--- Traverse describes tree
local traverse = function (cb)
  local path = { 1 }
  while true do
    local key = table.concat(path, ":")
    if not plan.describes[key] then
      table.remove(path)
      path[#path] = path[#path] + 1
    else

      cb(plan.describes[key], {table.unpack(path)})

      if plan.describes[key..":1"] then
        table.insert(path, 1)
      else
        path[#path] = path[#path] + 1
        key = table.concat(path, ":")
        if not plan.describes[key] then
          table.remove(path)
          if #path == 0 then
            return
          end
          path[#path] = path[#path] + 1
        end
      end
    end
  end
end

--- Run test plan
local runPlan = function ()
  local clock = os.clock()

  if plan.beforeAll then
    plan.beforeAll()
  end

  local afterAlls = {}
  traverse(function (context, path)
    if context.beforeAll then
      context.beforeAll()
    end

    table.insert(afterAlls, context.afterAll)

    for i = 1, #context.its do
      if plan.beforeEach then
        plan.beforeEach()
      end
      for depth = 1, #path do
        local key = table.concat(elements(path, depth), ":")
        local ctx = plan.describes[key]
        if ctx.beforeEach then
           ctx.beforeEach()
        end
      end

      local cb = context.its[i].cb
      local ret, err = xpcall(cb, debug.traceback)
      if not ret then
        context.its[i].result = {
          passed = false
        }
        plan.success = false
        local stack = {}
        for line in string.gmatch(err, "[^\n]+") do
          table.insert(stack, line)
        end
        table.insert(plan.failed, {
          label = context.its[i].label,
          path = path,
          error = string.gsub(stack[5], "^%s+", ""),
          expected = g_expected,
          received = g_received,
        })
      else
        context.its[i].result = { passed = true }
        plan.passed = plan.passed + 1
      end

      if plan.afterEach then
        plan.afterEach()
      end
      for depth = 1, #path do
        local key = table.concat(elements(path, depth), ":")
        local ctx = plan.describes[key]
        if ctx.afterEach then
          ctx.afterEach()
        end
      end
    end

    local afterAllCb = table.remove(afterAlls)
    if afterAllCb then
      afterAllCb()
    end
  end)

  if plan.afterAll then
    plan.afterAll()
  end

  plan.time = os.clock() - clock
end

--- Generate breadcrumb from path
---@param path table
function breadcrumb(path)
  if #path == 0 then
    return ""
  end
  local key = table.concat(path, ":")
  if #path == 1 then
    return plan.describes[key].label
  end
  return breadcrumb(elements(path, #path - 1)) .. " > " .. plan.describes[key].label
end

--- leftPad print
local paddedPrint = function (str, depth)
  print(string.rep("  ", depth) .. str)
end

--- Pretty print all this mess
local reportPlan = function ()
  if plan.success then
    print("\27[42m PASS \27[0m ./" .. plan.filename)
  else
    print("\27[41m FAIL \27[0m ./" .. plan.filename)
  end

  traverse(function (context, path)
    paddedPrint(context.label, #path)
    for i = 1, #context.its do
      if context.its[i].result.passed then
        paddedPrint("\27[32m✓\27[0m \27[2m" .. context.its[i].label .. "\27[0m", #path + 1)
      else
        paddedPrint("\27[31m✕\27[0m \27[2m" .. context.its[i].label .. "\27[0m", #path + 1)
      end
    end
  end)

  print("")

  for i = 1, #plan.failed do
    print("\27[31m  ● " .. breadcrumb(plan.failed[i].path) .. " > " .. plan.failed[i].label .. "\27[0m")
    print("")
    print("\27[2m    expect(\27[0m\27[31mreceived\27[0m\27[2m).\27[0mtoBe\27[2m(\27[0m\27[32mexpected\27[0m\27[2m)\27[0m")
    print("")
    print("    Expected: \27[32m".. plan.failed[i].expected .."\27[0m")
    print("    Received: \27[31m".. plan.failed[i].received .."\27[0m")
    print("")
    print("      at " .. plan.failed[i].error)
    print("")
  end

  local test_suites = {}
  if plan.success then
    table.insert(test_suites, "\27[32m1 passed\27[0m")
  else
    table.insert(test_suites, "\27[31m1 failed\27[0m")
  end
  table.insert(test_suites, "1 total")
  print("\27[1mTest Suites: \27[0m" .. table.concat(test_suites, ", "))

  local tests = {}
  if #plan.failed > 0 then
    table.insert(tests, "\27[31m" .. #plan.failed .. " failed\27[0m")
  end
  if plan.passed > 0 then
    table.insert(tests, "\27[32m" .. plan.passed .. " passed\27[0m")
  end
  table.insert(tests, (plan.passed + #plan.failed) .. " total")
  print("\27[1mTests:       \27[0m" .. table.concat(tests, ", "))
  print("\27[1mTime:        \27[0m" .. plan.time * 100 .. "s")
end

--- Run a test file
local runFile = function (filename)
  buildPlan(filename)
  runPlan()
  reportPlan()
end

if #arg == 0 then
  print("lest [filename..]")
else
  runFile(arg[1])
end
