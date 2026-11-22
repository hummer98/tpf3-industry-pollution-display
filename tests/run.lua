-- Offline tests for the industry emissions card. Run from anywhere:
--   luajit tests/run.lua
-- No game needed: the globals the scripts expect (api, ug_require, _,
-- debugPrint) are stubbed below with just enough behaviour.

local root = (arg and arg[0] or "tests/run.lua"):match("^(.*)/tests/[^/]*$") or "."

local loaders = package.loaders or package.searchers
table.insert(loaders, 2, function(name)
	local rel = name:match("^hummer_industry_pollution_display::/(.*)$")
	if rel then return assert(loadfile(root .. "/content/" .. rel)) end
end)

local failures, passes = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passes = passes + 1
		print("PASS " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. "\n     " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then error((msg or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

------------------------------------------------------------------------
-- ipd_core (pure)
------------------------------------------------------------------------
local core = require "hummer_industry_pollution_display::/gui/ipd_core.lua"

test("round: floor(x + 0.5), like the engine's mathutil.round", function()
	eq(core.round(0), 0)
	eq(core.round(2.4), 2)
	eq(core.round(2.5), 3)
	eq(core.round(-2.5), -2)
	eq(core.round(-0.4), 0)
	eq(core.round(-0.6), -1)
end)

test("collectEmitters: skips entities without an emitter, keeps order", function()
	local comps = { [10] = { noisePower = 1 }, [30] = { noisePower = 3 } }
	local list = core.collectEmitters({ 10, 20, 30 }, function(e) return comps[e] end)
	eq(#list, 2)
	eq(list[1].noisePower, 1)
	eq(list[2].noisePower, 3)
end)

test("collectEmitters: nil / empty input gives an empty list", function()
	eq(#core.collectEmitters(nil, function() error("not called") end), 0)
	eq(#core.collectEmitters({}, function() error("not called") end), 0)
end)

test("sumEmissions: totals are rounded, count is the emitter count", function()
	local r = core.sumEmissions({
		{ noisePower = 10.2, pollutionPower = 0.4 },
		{ noisePower = 5.4, pollutionPower = 7.1 },
	})
	eq(r.noise, 16)      -- 15.6
	eq(r.pollution, 8)   -- 7.5
	eq(r.count, 2)
end)

test("sumEmissions: no emitters -> zeros and count 0", function()
	local r = core.sumEmissions({})
	eq(r.noise, 0); eq(r.pollution, 0); eq(r.count, 0)
	r = core.sumEmissions(nil)
	eq(r.count, 0)
end)

test("sumEmissions: greenified industry at 0 still counts as emitting", function()
	local r = core.sumEmissions({ { noisePower = 0, pollutionPower = 0 } })
	eq(r.count, 1)
	eq(r.pollution, 0)
end)

test("sumEmissions: a missing field is treated as 0", function()
	local r = core.sumEmissions({ { noisePower = 3 } })
	eq(r.noise, 3); eq(r.pollution, 0)
end)

test("unwrapParams: params first, or after a react ref", function()
	local p = { entityId = 1 }
	eq(core.unwrapParams(p, nil), p)
	eq(core.unwrapParams({ is_react_ref_info = true }, p), p)
end)

test("makeChangeLogger: emits a line once per key until it changes", function()
	local out = {}
	local lg = core.makeChangeLogger(function(l) out[#out + 1] = l end)
	lg(1, "a"); lg(1, "a"); lg(2, "a"); lg(1, "b"); lg(1, "b")
	eq(#out, 3)
	eq(out[3], "b")
	lg(1, "a")
	eq(#out, 4, "returning to an earlier line logs again")
end)

------------------------------------------------------------------------
-- ipd.script (plugin recipe wired to stubbed engine + react)
------------------------------------------------------------------------
local CT = { CONSTRUCTION = "CONSTRUCTION", EMISSION_EMITTER = "EMISSION_EMITTER" }
local world  -- { entities = {id=true}, con = {conEntity -> construction}, sub2con = {sub -> con}, emitters = {id -> comp} }

api = {
	type = { ComponentType = CT },
	engine = {
		entityExists = function(e) return world.entities[e] == true end,
		getComponent = function(e, ct)
			-- The engine throws for an entity that does not exist (incl. -1).
			if not (world.entities[e] or world.con[e]) then error("Invalid entity: " .. tostring(e)) end
			if ct == CT.CONSTRUCTION then return world.con[e] end
			if ct == CT.EMISSION_EMITTER then
				if world.throwOnEmitter then error(world.throwOnEmitter) end
				return world.emitters[e]
			end
			return nil
		end,
		-- only here to trip a depot read that wrongly uses industry APIs
		util = { industry = { getIndustryProductivityInfo = function() return {} end } },
		system = {
			streetConnectorSystem = {
				getConstructionEntityForSubconstruction = function(e) return world.sub2con[e] end,
			},
		},
	},
}
local logs = {}
debugPrint = function(msg) logs[#logs + 1] = msg end

local registered = {}
local stepStateFn
local stepStateCalls = 0
local cards = {}
local stubs = {
	["::/gui/main/react.lua"] = {
		RegisterPluginRecipe = function(extensionPoint, name, fn)
			registered[#registered + 1] = { ep = extensionPoint, name = name }
			return fn
		end,
	},
	["::/gui/main/builtin.lua"] = {
		type = { Orientation = { Vertical = "V" } },
		BoxLayout = function(p) return { kind = "BoxLayout", p = p } end,
	},
	["::/gui/main/engine_react_util.tl"] = {
		useStepState = function(fn)
			stepStateCalls = stepStateCalls + 1
			stepStateFn = fn
			local v = fn()
			return { old = function() return v end }
		end,
	},
	["::/gui/main/content_card.tl"] = {
		ContentCard = function(p) cards[#cards + 1] = p; return { kind = "ContentCard", p = p } end,
		makeRecipeAndParam = function(recipe, param) return { recipe = recipe, param = param } end,
	},
	["::/gui/entity_window/entity_window_util.tl"] = { NoiseAndPollution = "NoiseAndPollutionRecipe" },
	["::/gui/entity_window/industry/industry_eow.script.tl"] = { IndustryEowExtensionPoint = { id = "::IndustryEowExtensionPoint" } },
	["::/gui/entity_window/maintenance_station/maintenance_station_eow.script.tl"] = { MaintenanceStationEowExtensionPoint = { id = "::MaintenanceStationEowExtensionPoint" } },
}
ug_require = function(path)
	return assert(stubs[path], "unexpected ug_require: " .. tostring(path))
end

local exports = {}
test("script: registers the industry and maintenance station plugins, exports via data()", function()
	local chunk = assert(loadfile(root .. "/content/gui/ipd.script.lua"))
	local chunkReturn = chunk()
	eq(chunkReturn, nil, "a .script.lua must not return a value")
	eq(type(data), "function", "global data() must be defined")
	exports = data()
	eq(#registered, 2)
	eq(registered[1].ep.id, "::IndustryEowExtensionPoint")
	eq(registered[1].name, "IndustryEmissionsPlugin")
	eq(registered[2].ep.id, "::MaintenanceStationEowExtensionPoint")
	eq(registered[2].name, "MaintenanceStationEmissionsPlugin")
	eq(type(exports.IndustryEmissionsPlugin), "function")
	eq(type(exports.MaintenanceStationEmissionsPlugin), "function")
end)

-- The res files are what the engine actually reads: each must name an
-- extension point and an export that the script really provides.
local function loadRes(file)
	data = nil
	assert(loadfile(root .. "/content/gui/" .. file))()
	local r = data()
	data = nil
	return r
end

test("res: each plugin resource points at its extension point and an existing export", function()
	for _, c in ipairs({
		{ file = "ipd.res.lua", ep = "::IndustryEowExtensionPoint", export = "IndustryEmissionsPlugin" },
		{ file = "ipd_maintenance.res.lua", ep = "::MaintenanceStationEowExtensionPoint", export = "MaintenanceStationEmissionsPlugin" },
	}) do
		local r = loadRes(c.file)
		eq(r.type, "react-plugin " .. c.ep, c.file)
		eq(r.data.filePath, "hummer_industry_pollution_display::/gui/ipd.script@" .. c.export, c.file)
		eq(type(exports[c.export]), "function", c.file)
		eq(type(r.data.order), "number", c.file)
	end
	-- Between the base maintenance pool (20) and balance (30) cards.
	eq(loadRes("ipd_maintenance.res.lua").data.order, 25)
end)

local function render(entityId, params)
	cards = {}
	params = params or {}
	params.entityId = entityId
	params.gameCtx = params.gameCtx or { ctx = true }
	params.showCalloutOnRightSide = true
	return exports.IndustryEmissionsPlugin(params)
end

test("recipe: sums the emitters of the industry's construction into a NoiseAndPollution card", function()
	world = {
		entities = { [100] = true, [101] = true, [102] = true },
		sub2con = { [100] = 50 },
		con = { [50] = { subconstructions = { 100, 101, 102 } } },
		emitters = {
			[100] = { noisePower = 40.3, pollutionPower = 12.6 },
			[102] = { noisePower = 10, pollutionPower = 3 },
		},
	}
	local node = render(100)
	eq(node.kind, "BoxLayout")
	eq(node.p.meta.class, "box-plugin-vertical-space")
	eq(#cards, 1)
	eq(cards[1].recipeAndParamPermanent.recipe, "NoiseAndPollutionRecipe")
	eq(cards[1].recipeAndParamPermanent.param.noise, 50)
	eq(cards[1].recipeAndParamPermanent.param.pollution, 16)
	eq(cards[1].gameCtx.ctx, true)
	eq(cards[1].showOnRightSide, true)
	eq(node.p.children[1].kind, "ContentCard")
end)

test("recipe: construction without any emitter renders no card", function()
	world = {
		entities = { [100] = true, [101] = true },
		sub2con = { [100] = 50 },
		con = { [50] = { subconstructions = { 100, 101 } } },
		emitters = {},
	}
	local node = render(100)
	eq(#cards, 0)
	eq(node.p.children[1], nil)
end)

test("recipe: vanished entity renders no card and does not touch the engine", function()
	world = { entities = {}, sub2con = {}, con = {}, emitters = {} }
	api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction = function()
		error("must not be called for a vanished entity")
	end
	local node = render(999)
	eq(#cards, 0)
	eq(node.p.children[1], nil)
	api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction = function(e) return world.sub2con[e] end
end)

test("recipe: engine's -1 'no construction' answer -> no card, no getComponent(-1)", function()
	world = { entities = { [7] = true }, sub2con = { [7] = -1 }, con = {}, emitters = {} }
	render(7)
	eq(#cards, 0)
end)

test("recipe: nil construction entity -> no card", function()
	world = { entities = { [7] = true }, sub2con = {}, con = {}, emitters = {} }
	render(7)
	eq(#cards, 0)
end)

test("recipe: exactly one useStepState hook per render, with and without a card", function()
	world = {
		entities = { [100] = true },
		sub2con = { [100] = 50 },
		con = { [50] = { subconstructions = { 100 } } },
		emitters = { [100] = { noisePower = 1, pollutionPower = 1 } },
	}
	stepStateCalls = 0
	render(100); eq(#cards, 1); eq(stepStateCalls, 1)
	world.emitters = {}
	stepStateCalls = 0
	render(100); eq(#cards, 0); eq(stepStateCalls, 1)
end)

test("recipe: params may arrive after a react ref (first/last plugin)", function()
	world = {
		entities = { [100] = true },
		sub2con = { [100] = 50 },
		con = { [50] = { subconstructions = { 100 } } },
		emitters = { [100] = { noisePower = 1, pollutionPower = 2 } },
	}
	cards = {}
	exports.IndustryEmissionsPlugin({ is_react_ref_info = true }, { entityId = 100, gameCtx = {}, showCalloutOnRightSide = false })
	eq(#cards, 1)
	eq(cards[1].recipeAndParamPermanent.param.pollution, 2)
end)

test("recipe: the engine read is deferred to the step state", function()
	world = {
		entities = { [100] = true },
		sub2con = { [100] = 50 },
		con = { [50] = { subconstructions = { 100 } } },
		emitters = { [100] = { noisePower = 0, pollutionPower = 5 } },
	}
	render(100)
	world.emitters[100].pollutionPower = 9
	eq(stepStateFn().pollution, 9)
end)

------------------------------------------------------------------------
-- maintenance station / depot window
------------------------------------------------------------------------
local function renderDepot(entityId)
	cards = {}
	return exports.MaintenanceStationEmissionsPlugin({ entityId = entityId, gameCtx = { depot = true }, showCalloutOnRightSide = false })
end

test("depot: the depot subconstruction's emitter becomes a NoiseAndPollution card", function()
	-- keyEntity of the window is the VEHICLE_DEPOT subconstruction itself.
	world = {
		entities = { [200] = true, [201] = true },
		sub2con = { [200] = 60 },
		con = { [60] = { subconstructions = { 200, 201 } } },
		emitters = { [200] = { noisePower = 35.5, pollutionPower = 75.2 } },
	}
	local node = renderDepot(200)
	eq(#cards, 1)
	eq(cards[1].recipeAndParamPermanent.recipe, "NoiseAndPollutionRecipe")
	eq(cards[1].recipeAndParamPermanent.param.noise, 36)
	eq(cards[1].recipeAndParamPermanent.param.pollution, 75)
	eq(cards[1].gameCtx.depot, true)
	eq(cards[1].showOnRightSide, false)
	eq(node.p.children[1].kind, "ContentCard")
end)

test("depot: follows pool usage changes through the step state", function()
	world = {
		entities = { [200] = true },
		sub2con = { [200] = 60 },
		con = { [60] = { subconstructions = { 200 } } },
		emitters = { [200] = { noisePower = 20, pollutionPower = 50 } },
	}
	renderDepot(200)
	world.emitters[200] = { noisePower = 40, pollutionPower = 100 }
	local r = stepStateFn()
	eq(r.noise, 40)
	eq(r.pollution, 100)
end)

test("depot: no industry API is used and nothing is logged", function()
	world = {
		entities = { [200] = true },
		sub2con = { [200] = 60 },
		con = { [60] = { subconstructions = { 200 } } },
		emitters = { [200] = { noisePower = 20, pollutionPower = 50 } },
	}
	local real = api.engine.util.industry.getIndustryProductivityInfo
	api.engine.util.industry.getIndustryProductivityInfo = function() error("industry API used for a depot") end
	logs = {}
	renderDepot(200)
	stepStateFn()
	api.engine.util.industry.getIndustryProductivityInfo = real
	eq(#logs, 0, "unexpected log: " .. tostring(logs[1]))
	eq(#cards, 1)
end)

test("depot: only the depot entity's emitter, not other emitting parts of its construction", function()
	-- e.g. a modded station with a built-in depot: the station's emission is
	-- not the depot's, and the emissions script only drives the depot entity.
	world = {
		entities = { [200] = true, [210] = true },
		sub2con = { [200] = 60, [210] = 60 },
		con = { [60] = { subconstructions = { 210, 200 } } },
		emitters = { [200] = { noisePower = 20, pollutionPower = 50 }, [210] = { noisePower = 99, pollutionPower = 99 } },
	}
	renderDepot(200)
	eq(#cards, 1)
	eq(cards[1].recipeAndParamPermanent.param.noise, 20)
	eq(cards[1].recipeAndParamPermanent.param.pollution, 50)
end)

test("depot: shown even when the engine reports no construction", function()
	world = { entities = { [200] = true }, sub2con = { [200] = -1 }, con = {}, emitters = { [200] = { noisePower = 1, pollutionPower = 2 } } }
	renderDepot(200)
	eq(#cards, 1)
	eq(cards[1].recipeAndParamPermanent.param.pollution, 2)
end)

test("depot: no emitter / vanished entity -> no card", function()
	world = { entities = { [200] = true }, sub2con = { [200] = 60 }, con = { [60] = { subconstructions = { 200 } } }, emitters = {} }
	renderDepot(200); eq(#cards, 0)
	world = { entities = {}, sub2con = {}, con = {}, emitters = {} }
	local node = renderDepot(200); eq(#cards, 0); eq(node.p.children[1], nil)
end)

test("depot: params may arrive after a react ref (first/last plugin)", function()
	world = {
		entities = { [200] = true },
		sub2con = { [200] = 60 },
		con = { [60] = { subconstructions = { 200 } } },
		emitters = { [200] = { noisePower = 1, pollutionPower = 3 } },
	}
	cards = {}
	exports.MaintenanceStationEmissionsPlugin({ is_react_ref_info = true }, { entityId = 200, gameCtx = {}, showCalloutOnRightSide = true })
	eq(#cards, 1)
	eq(cards[1].recipeAndParamPermanent.param.pollution, 3)
end)

------------------------------------------------------------------------
-- logging: failures only
------------------------------------------------------------------------
-- A fresh load from the first render on: a working industry and depot,
-- read every step, must log nothing at all.
test("a working industry and depot log nothing, step after step", function()
	world = {
		entities = { [100] = true, [200] = true },
		sub2con = { [100] = 50, [200] = 60 },
		con = { [50] = { subconstructions = { 100 } }, [60] = { subconstructions = { 200 } } },
		emitters = { [100] = { noisePower = 6, pollutionPower = 11 }, [200] = { noisePower = 2, pollutionPower = 3 } },
	}
	logs = {}
	registered = {}
	assert(loadfile(root .. "/content/gui/ipd.script.lua"))()
	local fresh = data()
	cards = {}
	fresh.IndustryEmissionsPlugin({ entityId = 100, gameCtx = {}, showCalloutOnRightSide = true })
	stepStateFn(); stepStateFn()
	world.emitters[100].pollutionPower = 12
	stepStateFn()
	fresh.MaintenanceStationEmissionsPlugin({ entityId = 200, gameCtx = {}, showCalloutOnRightSide = true })
	stepStateFn()
	eq(#cards, 2)
	eq(#logs, 0, "unexpected log: " .. tostring(logs[1]))
end)

test("a throwing read renders no card and logs each distinct error once", function()
	world = {
		entities = { [100] = true },
		sub2con = { [100] = 50 },
		con = { [50] = { subconstructions = { 100 } } },
		emitters = { [100] = { noisePower = 1, pollutionPower = 4 } },
		throwOnEmitter = "emitter read failed",
	}
	logs = {}
	local node = render(100)
	stepStateFn(); stepStateFn()
	eq(#cards, 0)
	eq(node.p.children[1], nil)
	eq(#logs, 1)
	assert(logs[1]:find("^%[IPD%] emission read failed: .*emitter read failed"), logs[1])
	world.throwOnEmitter = "another failure"
	stepStateFn()
	eq(#logs, 2, "a different error is logged too")
	-- the read recovers: the card comes back, nothing more is logged
	world.throwOnEmitter = nil
	render(100)
	eq(#cards, 1)
	eq(#logs, 2)
end)

test("depot: a throwing read renders no card and logs", function()
	world = {
		entities = { [200] = true },
		sub2con = { [200] = 60 },
		con = { [60] = { subconstructions = { 200 } } },
		emitters = { [200] = { noisePower = 1, pollutionPower = 2 } },
		throwOnEmitter = "depot read failed",
	}
	logs = {}
	renderDepot(200)
	eq(#cards, 0)
	eq(#logs, 1)
	assert(logs[1]:find("depot read failed", 1, true), logs[1])
end)

-- two windows failing at once with different messages must not alternate
-- through one shared key and log every step
test("two failing windows log once each, not every step", function()
	world = {
		entities = { [100] = true, [200] = true },
		sub2con = { [100] = 50, [200] = 60 },
		con = { [50] = { subconstructions = { 100 } }, [60] = { subconstructions = { 200 } } },
		emitters = {},
	}
	local real = api.engine.getComponent
	api.engine.getComponent = function(e, ct)
		if ct == CT.EMISSION_EMITTER then error("bad emitter " .. tostring(e)) end
		return real(e, ct)
	end
	logs = {}
	render(100)
	local industryStep = stepStateFn
	renderDepot(200)
	local depotStep = stepStateFn
	for _ = 1, 3 do industryStep(); depotStep() end
	api.engine.getComponent = real
	eq(#logs, 2, "one line per window")
	assert(logs[1]:find("bad emitter 100", 1, true), logs[1])
	assert(logs[2]:find("bad emitter 200", 1, true), logs[2])
end)

-- the change-time diagnostics of development builds stay out of the
-- release, and os.clock (process CPU time) is never a timer here
test("script: no development diagnostics or os.clock", function()
	for _, name in ipairs({ "ipd.script.lua", "ipd_core.lua" }) do
		local h = assert(io.open(root .. "/content/gui/" .. name))
		local src = h:read("*a")
		h:close()
		for _, needle in ipairs({ "os.clock", "missionEmissionsScriptFactor", "diagnose", "ecoLevel" }) do
			assert(not src:find(needle, 1, true), needle .. " in " .. name)
		end
	end
end)

------------------------------------------------------------------------
-- release files
------------------------------------------------------------------------
local GITHUB = "https://github.com/hummer98/tpf3-industry-pollution-display"

-- a small JSON decoder (objects, arrays, strings with escapes, numbers,
-- true/false/null): enough for strings.json and _metadata/modinfo.json,
-- whose keys contain spaces and escaped quotes
local function decodeJson(src)
	local pos = 1
	local function ws() pos = src:find("[^ \t\r\n]", pos) or #src + 1 end
	local value
	local function str()
		local out, i = {}, pos + 1
		while true do
			local c = src:sub(i, i)
			assert(c ~= "", "unterminated string")
			if c == '"' then pos = i + 1; return table.concat(out) end
			assert(c:byte() >= 0x20, "control character in string")
			if c == "\\" then
				local e = src:sub(i + 1, i + 1)
				local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				if e == "u" then
					local cp = tonumber(src:sub(i + 2, i + 5), 16)
					assert(cp and cp < 0x80, "only ASCII \\u escapes are expected")
					out[#out + 1] = string.char(cp); i = i + 6
				else
					out[#out + 1] = assert(map[e], "bad escape"); i = i + 2
				end
			else
				out[#out + 1] = c; i = i + 1
			end
		end
	end
	function value()
		ws()
		local c = src:sub(pos, pos)
		if c == "{" then
			local t = {}
			pos = pos + 1; ws()
			if src:sub(pos, pos) == "}" then pos = pos + 1; return t end
			while true do
				ws(); assert(src:sub(pos, pos) == '"', "key expected at " .. pos)
				local k = str(); ws()
				assert(src:sub(pos, pos) == ":", ": expected at " .. pos); pos = pos + 1
				assert(t[k] == nil, "duplicate key " .. k)
				t[k] = value(); ws()
				local d = src:sub(pos, pos); pos = pos + 1
				if d == "}" then return t end
				assert(d == ",", ", or } expected at " .. pos)
			end
		elseif c == "[" then
			local t = {}
			pos = pos + 1; ws()
			if src:sub(pos, pos) == "]" then pos = pos + 1; return t end
			while true do
				t[#t + 1] = value(); ws()
				local d = src:sub(pos, pos); pos = pos + 1
				if d == "]" then return t end
				assert(d == ",", ", or ] expected at " .. pos)
			end
		elseif c == '"' then
			return str()
		end
		for lit, v in pairs({ ["true"] = true, ["false"] = false, ["null"] = false }) do
			if src:sub(pos, pos + #lit - 1) == lit then pos = pos + #lit; return v end
		end
		local num = src:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		local n = num and tonumber(num)
		assert(n, "bad value at " .. pos)
		pos = pos + #num
		return n
	end
	local v = value(); ws()
	assert(pos > #src, "trailing data at " .. pos)
	return v
end

local function readJson(rel)
	local f = assert(io.open(root .. "/" .. rel))
	local src = f:read("*a")
	f:close()
	return decodeJson(src)
end

local GAME_LANGS = { "en", "ja", "de", "es", "fr", "it", "ko", "nl", "pl", "pt_BR", "ru", "zh_CN", "zh_TW" }

test("decodeJson: escapes, nesting, rejects broken input", function()
	local v = decodeJson('{"a \\"b\\"": ["x", 1, true], "c": {"d": "\\u0041\\n"}}')
	eq(v['a "b"'][1], "x"); eq(v['a "b"'][2], 1); eq(v['a "b"'][3], true)
	eq(v.c.d, "A\n")
	eq((pcall(decodeJson, '{"a": "b"')), false)
	eq((pcall(decodeJson, '{"a": "b",}')), false)
	eq((pcall(decodeJson, '{"a": 1, "a": 2}')), false)
	eq((pcall(decodeJson, '[1-]')), false)
	eq((pcall(decodeJson, '["a\\nb"]')), true) -- an escaped newline is fine
	eq((pcall(decodeJson, '["a' .. "\n" .. 'b"]')), false) -- a raw one is not
end)

test("_metadata/modinfo.json: readable name, summary, author, tag", function()
	local info = readJson("_metadata/modinfo.json")
	local keys = {}
	for k in pairs(info) do keys[#keys + 1] = k end
	table.sort(keys)
	eq(table.concat(keys, ","), "authors,description,name,summary,tags,url")
	-- English only (user, 2026-11-22: no Japanese in mod titles); the
	-- translations stay in strings.json and the description
	eq(info.name, "Industry Pollution Display")
	assert(not info.name:find("[\128-\255]"), "name must be ASCII / English only")
	eq(info.name, readJson("strings.json").en.mod_name, "name = the English mod_name")
	-- mod.io limits, counted in characters (UTF-8 lead bytes)
	local function chars(str) return select(2, str:gsub("[^\128-\191]", "")) end
	assert(chars(info.name) <= 50, "name too long for mod.io")
	assert(chars(info.summary) <= 250, "summary too long for mod.io")
	assert(chars(info.description) <= 50000, "description too long for mod.io")
	eq(info.authors[1].name, "hummer")
	eq(info.authors[1].role, "CREATOR")
	eq(info.tags[1], "Script Mod")
	eq(info.url, GITHUB)
end)

local function sections(text)
	local paras, from = {}, 1
	while true do
		local at = text:find("\n\n", from, true)
		paras[#paras + 1] = text:sub(from, (at or 0) - 1)
		if not at then break end
		from = at + 2
	end
	local found = {}
	for _, para in ipairs(paras) do
		local head = para:match("^%[([^%]\n]+)%] ")
		assert(head, "paragraph without a language heading: " .. para:sub(1, 30))
		found[#found + 1] = { head = head, text = para }
	end
	return found
end

-- the game's own words (base.mo "Noise", "Pollution", "Depot"), or players
-- won't recognise what the card is about; every section names the depot too,
-- since that window is the less obvious half of the mod
local OFFICIAL = {
	en = { "English", "noise", "pollution", "depot" },
	ja = { "日本語", "騒音", "公害", "車庫" },
	de = { "Deutsch", "Lärm", "Verschmutzung", "Depot" },
	es = { "Español", "ruido", "polución", "depósito" },
	fr = { "Français", "bruit", "pollution", "dépôt" },
	it = { "Italiano", "rumore", "inquinamento", "deposit" },
	ko = { "한국어", "소음", "공해", "차고지" },
	nl = { "Nederlands", "geluidsoverlast", "vervuiling", "depot" },
	pl = { "Polski", "hałas", "zanieczyszcz", "baz" },
	pt_BR = { "Português (Brasil)", "barulho", "poluição", "pátio" },
	ru = { "Русский", "шум", "загрязнени", "депо" },
	zh_CN = { "简体中文", "噪音", "污染", "车库" },
	zh_TW = { "繁體中文", "噪音", "汙染", "倉庫" },
}

test("modinfo description: every language, in the game's terms", function()
	local info = readJson("_metadata/modinfo.json")
	local found = sections(info.description)
	eq(#found, #GAME_LANGS, "one section per game language")
	for i, lang in ipairs(GAME_LANGS) do
		local want = OFFICIAL[lang]
		eq(found[i].head, want[1], "section " .. i)
		for j = 2, #want do
			assert(found[i].text:find(want[j], 1, true), lang .. " doesn't name " .. want[j])
		end
	end
	assert(found[1].text:find("License: MIT", 1, true)
		and found[1].text:find(GITHUB, 1, true), "licence and source link")
end)

-- the mod.io web page text is kept in docs/ (the uploader has no field for
-- it); it must say the same as the in-game description
test("docs/modio_description.md matches modinfo.json", function()
	local info = readJson("_metadata/modinfo.json")
	local f = assert(io.open(root .. "/docs/modio_description.md"))
	local md = f:read("*a")
	f:close()
	assert(md:find(info.summary, 1, true), "summary differs")
	for _, s in ipairs(sections(info.description)) do
		local head, title, body = s.text:match("^%[([^%]]+)%] ([^\n]+)\n(.*)$")
		assert(md:find("## " .. head .. ": " .. title .. "\n\n" .. body .. "\n", 1, true), head .. " section differs")
	end
end)

-- strings.json carries the same name and first sentence per language, so
-- the two never tell different stories
test("strings.json: name and description in every game language, matching modinfo", function()
	local langs = readJson("strings.json")
	local info = readJson("_metadata/modinfo.json")
	local found = sections(info.description)
	local known = {}
	for i, lang in ipairs(GAME_LANGS) do
		known[lang] = true
		local t = assert(langs[lang], "missing language " .. lang)
		local keys = {}
		for k in pairs(t) do keys[#keys + 1] = k end
		table.sort(keys)
		eq(table.concat(keys, ","), "mod_desc,mod_name", lang .. " keys")
		local title, body = found[i].text:match("^%[[^%]]+%] ([^\n]+)\n(.*)$")
		eq(t.mod_name, title, lang .. " name")
		eq(body:sub(1, #t.mod_desc), t.mod_desc, lang .. " description")
	end
	for lang in pairs(langs) do assert(known[lang], "unknown language " .. lang) end
	eq(langs.en.mod_name, "Industry Pollution Display")
	eq(langs.ja.mod_name, "産業パネルに公害表示")
end)

local function readFile(rel)
	local f = assert(io.open(root .. "/" .. rel), "missing " .. rel)
	local src = f:read("*a")
	f:close()
	return src
end

test("LICENSE: MIT, copyright hummer 2026", function()
	local lic = readFile("LICENSE")
	eq(lic:match("^[^\n]+"), "MIT License")
	assert(lic:find("Copyright (c) 2026 hummer", 1, true), "copyright line")
	assert(lic:find("THE SOFTWARE IS PROVIDED \"AS IS\"", 1, true), "full licence text")
end)

test("README: both languages, install folder, clone URL, licence", function()
	local md = readFile("README.md")
	assert(md:find("^# Industry Pollution Display"), "English title first")
	assert(md:find("\n## 日本語\n", 1, true), "Japanese part")
	assert(md:find("# 産業パネルに公害表示", 1, true), "Japanese title")
	assert(md:find("git clone " .. GITHUB .. ".git hummer_industry_pollution_display_1", 1, true), "clone command")
	local n = select(2, md:gsub("%[MIT%]%(LICENSE%) © 2026 hummer", ""))
	eq(n, 2, "licence line in each language")
end)

-- each language section shows its own screenshot; GitHub renders a broken
-- image silently, so check the files are there and are 1920x1080 PNGs
test("README: images exist and are 1920x1080 PNGs, cover = English one", function()
	local md = readFile("README.md")
	local seen = {}
	for rel in md:gmatch("!%[[^%]]*%]%(([^)]+)%)") do seen[#seen + 1] = rel end
	eq(#seen, 2, "one image per language")
	eq(seen[1], "docs/images/cover_en.png")
	eq(seen[2], "docs/images/cover_ja.png")
	local function size(rel)
		local png = readFile(rel)
		eq(png:sub(1, 8), "\137PNG\r\n\26\n", rel .. " is a PNG")
		local function u32(i) local a, b, c, d = png:byte(i, i + 3) return ((a * 256 + b) * 256 + c) * 256 + d end
		return u32(17), u32(21)
	end
	for _, rel in ipairs({ seen[1], seen[2], "_metadata/0.png" }) do
		local w, h = size(rel)
		eq(w, 1920, rel .. " width")
		eq(h, 1080, rel .. " height")
	end
	eq(readFile("_metadata/0.png"), readFile("docs/images/cover_en.png"), "cover is the English screenshot")
	assert(readFile("docs/images/cover_ja.png") ~= readFile("docs/images/cover_en.png"), "Japanese screenshot is a different image")
end)

test("README links the mod.io page in both languages", function()
	local md = readFile("README.md")
	local url = "https://mod.io/g/transportfever3/m/industry-pollution-display"
	-- each language section needs its own link; extra links (badges) are fine
	local split = assert(md:find("\n## 日本語", 1, true), "Japanese section")
	assert(md:sub(1, split):find(url, 1, true), "English section link")
	assert(md:sub(split):find(url, 1, true), "Japanese section link")
	assert(not md:find("link follows after", 1, true), "English placeholder left")
	assert(not md:find("リンクを載せます", 1, true), "Japanese placeholder left")
end)

test(".gitignore: build output and Python caches", function()
	local gi = readFile(".gitignore")
	assert(gi:find("\ndist/\n", 1, true) or gi:find("^dist/\n"), "dist/")
	assert(gi:find("__pycache__/", 1, true), "__pycache__/")
end)

-- published text and code name only the mod, its author and the game;
-- the needles are split so this file does not match itself
test("no internal names in the published files", function()
	local needles = { "yama" .. "moto", "A" .. "oM", "aom" .. "-", "Age of " .. "Mobility", "the " .. "user" }
	local p = assert(io.popen('cd "' .. root .. '" && find . -path ./.git -prune -o -path ./dist -prune -o -name __pycache__ -prune -o -type f -print'))
	local checked = 0
	for rel in p:lines() do
		local src = readFile(rel:sub(3))
		for _, needle in ipairs(needles) do
			assert(not src:find(needle, 1, true), needle .. " in " .. rel)
		end
		checked = checked + 1
	end
	p:close()
	assert(checked >= 10, "file list looks wrong: " .. checked)
end)

-- the game resolves "<modId>::/..." by mod.json's modId and loads the mod
-- from "<modId>_<major>", so a rename must change all of them
test("modId, folder name and every require / filePath prefix agree", function()
	local f = assert(io.open(root .. "/mod.json"))
	local modId = f:read("*a"):match('"modId"%s*:%s*"([^"]+)"')
	f:close()
	eq(modId, "hummer_industry_pollution_display")
	local folder = (root == "." and io.popen("pwd"):read("*l") or root):match("([^/]+)/?$")
	if folder:match("_%d+$") then eq((folder:gsub("_%d+$", "")), modId, "folder name") end
	local seen = 0
	for _, name in ipairs({ "ipd.res.lua", "ipd_maintenance.res.lua", "ipd.script.lua", "ipd_core.lua" }) do
		local h = assert(io.open(root .. "/content/gui/" .. name))
		local src = h:read("*a")
		h:close()
		for prefix in src:gmatch('"([%w_]+)::/') do
			eq(prefix, modId, name)
			seen = seen + 1
		end
	end
	-- two res files and the script's require of the core
	eq(seen, 3, "prefixed paths found")
end)

print(string.format("\n%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
