local level = 0
local plan = {}
local current_path = {}

local elements = function (list, len)
  local new = {}
  for i = 1, len do
    new[i] = list[i]
  end
  return new
end

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

function it(label, cb)
  local path = table.concat(elements(current_path, level), ":")
  table.insert(plan.describes[path].its, { label = label, cb = cb, result = nil })
end

local g_received = nil
local g_expected = nil
function expect(received)
  g_received = received
  return {
    toBe = function (expected)
      g_expected = expected
      -- local path = table.concat(elements(current_path, level), ":")
      -- plan.describes[path].its[#plan.describes[path].its].received = received
      -- plan.describes[path].its[#plan.describes[path].its].expected = expected
      assert(received == expected)
    end,
    toNotBe = function (expected)
      g_expected = expected
      assert(received ~= expected)
    end
  }
end

local buildPlan = function (filename)
  plan = {
    filename = filename,
    describes = {},
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

local runPlan = function ()
  local clock = os.clock()
  traverse(function (context, path)
    for i = 1, #context.its do
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
    end
  end)
  plan.time = os.clock() - clock
end

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

local paddedPrint = function (str, depth)
  print(string.rep("  ", depth) .. str)
end

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
