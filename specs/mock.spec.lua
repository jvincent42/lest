describe("mocks", function ()
  it("creates a callable table", function ()
    local mock = fn()
    expect(type(mock)).toBe("table")
    expect(type(getmetatable(mock).__call)).toBe("function")
  end)

  it("calls identity if no cb provided", function ()
    local mock = fn()
    expect(mock(42)).toBe(42)
  end)

  it("calls cb if provided", function ()
    local mock = fn(function (a, b) return a + b end)
    expect(mock(1, 2)).toBe(3)
  end)

  it("counts calls", function ()
    local mock = fn()
    for i = 1, 10 do mock(i) end
    expect(#mock.calls).toBe(10)
  end)

  it("bootstrap", function ()
    local mock = fn()
    local mock2 = fn(mock)
    expect(mock2()).toBe(nil)
    expect(#mock.calls).toBe(1)
  end)
end)