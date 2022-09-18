#!/usr/bin/env bash

diff snapshots/main.snapshot <(lua lest.lua specs/main.spec.lua)
diff snapshots/mock.snapshot <(lua lest.lua specs/mock.spec.lua)