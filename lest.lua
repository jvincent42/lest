local plan = {}
local level = 0
local currentPlan = nil
local singlefile = true
local currentPath = {}

--- Get the n first elements of an array
---
--- [pure]
local elements = function(list, len)
  local new = {}
  for i = 1, len do
    new[i] = list[i]
  end
  return new
end

--- Mock a function
---
--- return a callable table
---@param cb function
---@return table|function
function fn(cb)
  local Fn = {
    calls = {}
  }
  local o = {}
  function o.__call(self, ...)
    table.insert(self.calls, {...})
    if cb then
      return cb(...)
    else
      return ...
    end
  end
  setmetatable(Fn, o)
  return Fn
end

--- Calls cb one before all test of the describe block
function beforeAll(cb)
  if #currentPath == 0 then
    table.insert(currentPlan.beforeAll, cb)
  else
    local path = table.concat(elements(currentPath, level), ":")
    table.insert(currentPlan.describes[path].beforeAll, cb)
  end
end

--- Calls cb once after all test of the describe block
function afterAll(cb)
  if #currentPath == 0 then
    table.insert(currentPlan.afterAll, cb)
  else
    local path = table.concat(elements(currentPath, level), ":")
    table.insert(currentPlan.describes[path].afterAll, cb)
  end
end

--- Calls cb before each test of the describe block
function beforeEach(cb)
  if #currentPath == 0 then
    table.insert(currentPlan.beforeEach, cb)
  else
    local path = table.concat(elements(currentPath, level), ":")
    table.insert(currentPlan.describes[path].beforeEach, cb)
  end
end

--- Calls cb after each test of the describe block
function afterEach(cb)
  if #currentPath == 0 then
    table.insert(currentPlan.afterEach, cb)
  else
    local path = table.concat(elements(currentPath, level), ":")
    table.insert(currentPlan.describes[path].afterEach, cb)
  end
end

--- Run a unit test
function it(label, cb)
  if #currentPath == 0 then
    table.insert(currentPlan.its, {
      label = label,
      cb = cb,
      result = nil
    })
  else
    local path = table.concat(elements(currentPath, level), ":")
    table.insert(currentPlan.describes[path].its, {
      label = label,
      cb = cb,
      result = nil
    })
  end
end

--- Describe unit tests
function describe(label, cb)
  level = level + 1
  currentPath[level] = (currentPath[level] or 0) + 1
  local path = table.concat(elements(currentPath, level), ":")
  if not currentPlan.describes[path] then
    currentPlan.describes[path] = {}
  end
  currentPlan.describes[path] = {
    label = label,
    its = {},
    beforeAll = {},
    afterAll = {},
    beforeEach = {},
    afterEach = {}
  }
  cb()
  level = level - 1
end

--- Creates an expectable object
local g_received = nil
local g_expected = nil
function expect(received)
  g_received = received
  return {
    --- Comparison using equality operator (==)
    toBe = function(expected)
      g_expected = expected
      assert(received == expected)
    end,
    --- Comparison using inequality operator (~=)
    toNotBe = function(expected)
      g_expected = expected
      assert(received ~= expected)
    end
  }
end

--- Build test currentPlan
local buildCurrentPlan = function(filename)
  currentPlan = {
    filename = filename,
    describes = {},
    its = {},
    beforeAll = {},
    afterAll = {},
    beforeEach = {},
    afterEach = {},
    success = true,
    passed = 0,
    failed = {},
    time = 0
  }
  level = 0
  currentPath = {}
  local f, err = loadfile(filename)
  if not f then
    print(err)
    os.exit(1)
  else
    f()
  end
end

--- Traverse describes tree
local traverse = function(cb)
  local path = {1}
  cb(currentPlan, {})
  while true do
    local key = table.concat(path, ":")
    if not currentPlan.describes[key] then
      table.remove(path)
      if #path == 0 then
        return
      end
      path[#path] = path[#path] + 1
    else

      cb(currentPlan.describes[key], {table.unpack(path)})

      if currentPlan.describes[key .. ":1"] then
        table.insert(path, 1)
      else
        path[#path] = path[#path] + 1
        key = table.concat(path, ":")
        if not currentPlan.describes[key] then
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

--- Run test currentPlan
local runCurrentPlan = function()
  local clock = os.clock()

  if #currentPlan.beforeAll > 0 then
    for i = 1, #currentPlan.beforeAll do
      currentPlan.beforeAll[i]()
    end
  end

  local afterAlls = {}
  traverse(function(context, path)
    if #context.beforeAll > 0 then
      for j = 1, #context.beforeAll do
        context.beforeAll[j]()
      end
    end

    table.insert(afterAlls, context.afterAll)

    for i = 1, #context.its do
      if #currentPlan.beforeEach > 0 then
        for j = 1, #currentPlan.beforeEach do
          currentPlan.beforeEach[j]()
        end
      end
      for depth = 1, #path do
        local key = table.concat(elements(path, depth), ":")
        local ctx = currentPlan.describes[key]
        if #ctx.beforeEach > 0 then
          for j = 1, #ctx.beforeEach do
            ctx.beforeEach[j]()
          end
        end
      end

      local cb = context.its[i].cb
      local ret, err = xpcall(cb, debug.traceback)
      if not ret then
        context.its[i].result = {
          passed = false
        }
        currentPlan.success = false
        local stack = {}
        for line in string.gmatch(err, "[^\n]+") do
          table.insert(stack, line)
        end
        table.insert(currentPlan.failed, {
          label = context.its[i].label,
          path = path,
          error = string.gsub(stack[5], "^%s+", ""),
          expected = g_expected,
          received = g_received
        })
      else
        context.its[i].result = {
          passed = true
        }
        currentPlan.passed = currentPlan.passed + 1
      end

      if #currentPlan.afterEach > 0 then
        for j = 1, #currentPlan.afterEach do
          currentPlan.afterEach[j]()
        end
      end
      for depth = 1, #path do
        local key = table.concat(elements(path, depth), ":")
        local ctx = currentPlan.describes[key]
        if #ctx.afterEach > 0 then
          for j = 1, #ctx.afterEach do
            ctx.afterEach[j]()
          end
        end
      end
    end

    local afterAllCbs = table.remove(afterAlls)
    if afterAllCbs then
      for i = 1, #afterAllCbs do
        afterAllCbs[i]()
      end
    end
  end)

  if #currentPlan.afterAll > 0 then
    for j = 1, #currentPlan.afterAll do
      currentPlan.afterAll[j]()
    end
  end

  currentPlan.time = os.clock() - clock
end

--- Generate breadcrumb from path
---@param path table
function breadcrumb(path)
  if #path == 0 then
    return ""
  end
  local key = table.concat(path, ":")
  if #path == 1 then
    return currentPlan.describes[key].label
  end
  return breadcrumb(elements(path, #path - 1)) .. " > " .. currentPlan.describes[key].label
end

--- leftPad print
local paddedPrint = function(str, depth)
  print(string.rep("  ", depth) .. str)
end

--- Pretty print all this mess
local reportCurrentPlan = function()
  if currentPlan.success then
    plan.suitesPassed = plan.suitesPassed + 1
    print("\27[42m\27[30m PASS \27[0m\27[0m ./\27[1m\27[4m" .. currentPlan.filename .. "\27[0m\27[0m")
  else
    plan.suitesFailed = plan.suitesFailed + 1
    print("\27[41m\27[30m FAIL \27[0m\27[0m ./" .. currentPlan.filename)
  end

  if singlefile then
    traverse(function(context, path)
      if context.label then
        paddedPrint(context.label, #path)
      end
      for i = 1, #context.its do
        if context.its[i].result.passed then
          paddedPrint("\27[32m✓\27[0m \27[2m" .. context.its[i].label .. "\27[0m", #path + 1)
        else
          paddedPrint("\27[31m✕\27[0m \27[2m" .. context.its[i].label .. "\27[0m", #path + 1)
        end
      end
    end)
  end

  for i = 1, #currentPlan.failed do
    print("")
    if #currentPlan.failed[i].path == 0 then
      print("\27[31m  ● " .. currentPlan.failed[i].label .. "\27[0m")
    else
      print("\27[31m  ● " .. breadcrumb(currentPlan.failed[i].path) .. " > " .. currentPlan.failed[i].label ..
              "\27[0m")
    end
    print("")
    print(
      "\27[2m    expect(\27[0m\27[31mreceived\27[0m\27[2m).\27[0mtoBe\27[2m(\27[0m\27[32mexpected\27[0m\27[2m)\27[0m")
    print("")
    print("    Expected: \27[32m" .. tostring(currentPlan.failed[i].expected) .. "\27[0m")
    print("    Received: \27[31m" .. tostring(currentPlan.failed[i].received) .. "\27[0m")
    print("")
    print("      at " .. currentPlan.failed[i].error)
  end

  if not singlefile and #currentPlan.failed > 0 then
    print("")
  end

  plan.failed = plan.failed + #currentPlan.failed
  plan.passed = plan.passed + currentPlan.passed
  plan.time = plan.time + currentPlan.time
end

--- Pretty print plan execution on stdout
local reportPlan = function()
  print("")
  local testSuites = {}
  if plan.suitesFailed > 0 then
    table.insert(testSuites, "\27[31m" .. plan.suitesFailed .. " failed\27[0m")
  end
  if plan.suitesPassed > 0 then
    table.insert(testSuites, "\27[32m" .. plan.suitesPassed .. " passed\27[0m")
  end
  table.insert(testSuites, (plan.suitesPassed + plan.suitesFailed) .. " total")
  print("\27[1mTest Suites: \27[0m" .. table.concat(testSuites, ", "))

  local tests = {}
  if plan.failed > 0 then
    table.insert(tests, "\27[31m" .. plan.failed .. " failed\27[0m")
  end
  if plan.passed > 0 then
    table.insert(tests, "\27[32m" .. plan.passed .. " passed\27[0m")
  end
  table.insert(tests, (plan.passed + plan.failed) .. " total")
  print("\27[1mTests:       \27[0m" .. table.concat(tests, ", "))

  print("\27[1mTime:        \27[0m" .. string.format("%.3f", plan.time * 100) .. "s")
end

--- Run a test file
local runFile = function(filename)
  buildCurrentPlan(filename)
  runCurrentPlan()
  reportCurrentPlan()
end

if #arg == 0 then
  print("lest [files...]")
else
  if #arg > 1 then
    singlefile = false
  end
  plan = {
    suitesPassed = 0,
    suitesFailed = 0,
    passed = 0,
    failed = 0,
    time = 0
  }
  for i = 1, #arg do
    runFile(arg[i])
  end
  reportPlan()
end

if plan.failed == nil or plan.failed > 0 then
  os.exit(1)
end
