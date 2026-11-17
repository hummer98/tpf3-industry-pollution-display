-- Industry and maintenance-building window plugins: a "Current Noise /
-- Current Pollution" card.
--
-- The industry window collects its content through the base
-- IndustryEowExtensionPoint (gui/entity_window/industry/industry.tl) and
-- depots / maintenance stations through MaintenanceStationEowExtensionPoint
-- (gui/entity_window/maintenance_station/maintenance_station.tl), so these
-- are regular react-plugins (ipd.res.lua, ipd_maintenance.res.lua) and
-- nothing in the base is overridden.
--
-- The numbers are the EMISSION_EMITTER powers the emissions game script
-- (game_mechanics/emission/emissions.script.tl) writes. For an industry it
-- rewrites every emitting subconstruction of the construction from the
-- production state and the greenification (eco level) factor; summing them
-- per construction is what the base headquarters window (perk.tl) does for
-- its own card. For a depot it rewrites only the VEHICLE_DEPOT entity's own
-- emitter from the maintenance pool usage, so that emitter alone is shown:
-- a modded construction may bundle a depot with other emitting parts (e.g.
-- a station) whose emission is not the depot's.
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local content_card = ug_require "::/gui/main/content_card.tl"
local entity_window_util = ug_require "::/gui/entity_window/entity_window_util.tl"
local industry_eow = ug_require "::/gui/entity_window/industry/industry_eow.script.tl"
local maintenance_station_eow = ug_require "::/gui/entity_window/maintenance_station/maintenance_station_eow.script.tl"
local core = require "hummer_industry_pollution_display::/gui/ipd_core.lua"

local function log(msg)
	debugPrint("[IPD] " .. msg)
end

-- Failures only: readEmissions runs every step, so a broken read (an engine
-- API change, a modded construction the engine rejects) would otherwise
-- repeat the same line each frame; one line per window and distinct error is
-- enough to report it, and a working game logs nothing. The key is per
-- window: with one shared key, two windows failing with different messages
-- (e.g. each naming its entity) would alternate and log every step.
local logOnChange = core.makeChangeLogger(log)

-- A failed read shows no card: the error is not passed on into the base
-- window's step state, whose other cards (production, stocks) do not
-- depend on this one.
local function guardedRead(kind, readEmissions, entityId)
	local ok, result = pcall(readEmissions, entityId)
	if ok then
		return result
	end
	logOnChange(kind .. " " .. tostring(entityId), "emission read failed: " .. tostring(result))
	return core.sumEmissions({})
end

-- Emission totals of the construction the industry belongs to. Called from
-- a step state, so it runs where engine reads are allowed.
local function readIndustryEmissions(entityId)
	if not api.engine.entityExists(entityId) then
		return core.sumEmissions({})
	end
	-- -1 (not nil) when there is no construction; the base (industry.tl)
	-- guards it the same way, and getComponent on a bad entity throws.
	local conEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(entityId)
	local con = conEntity and conEntity >= 0 and api.engine.getComponent(conEntity, api.type.ComponentType.CONSTRUCTION) or nil
	local emitters = core.collectEmitters(con and con.subconstructions or {}, function(entity)
		return api.engine.getComponent(entity, api.type.ComponentType.EMISSION_EMITTER)
	end)
	return core.sumEmissions(emitters)
end

-- The depot window's entity is the VEHICLE_DEPOT entity, the one emitter the
-- emissions script drives for depots (see the header).
local function readDepotEmissions(entityId)
	if not api.engine.entityExists(entityId) then
		return core.sumEmissions({})
	end
	return core.sumEmissions(core.collectEmitters({ entityId }, function(entity)
		return api.engine.getComponent(entity, api.type.ComponentType.EMISSION_EMITTER)
	end))
end

-- Both windows hand their plugins the same fields (entityId, gameCtx,
-- showCalloutOnRightSide), so one recipe body serves both extension points.
local function makeEmissionsRecipe(kind, readEmissions)
	return function(a, b)
		local params = core.unwrapParams(a, b)

		-- Hooks are unconditional so their order is identical on every render.
		local emissionsState = engine_react_util.useStepState(function()
			return guardedRead(kind, readEmissions, params.entityId)
		end)
		local emissions = emissionsState:old()

		-- No emitter at all (a modded asset without emission metadata): no
		-- card rather than a misleading "0 / 0".
		local card = nil
		if emissions.count > 0 then
			card = content_card.ContentCard{
				initialCalloutTextPermanent = "",
				recipeAndParamPermanent = content_card.makeRecipeAndParam(
					entity_window_util.NoiseAndPollution,
					{
						noise = emissions.noise,
						pollution = emissions.pollution,
					}
				),
				gameCtx = params.gameCtx,
				showOnRightSide = params.showCalloutOnRightSide,
			}
		end

		return builtin.BoxLayout{
			meta = { class = "box-plugin-vertical-space" },
			orientation = builtin.type.Orientation.Vertical,
			children = { card },
		}
	end
end

local IndustryEmissionsPlugin = react.RegisterPluginRecipe(industry_eow.IndustryEowExtensionPoint, "IndustryEmissionsPlugin", makeEmissionsRecipe("industry", readIndustryEmissions))
if not IndustryEmissionsPlugin then
	log("plugin recipe not registered")
end

local MaintenanceStationEmissionsPlugin = react.RegisterPluginRecipe(maintenance_station_eow.MaintenanceStationEowExtensionPoint, "MaintenanceStationEmissionsPlugin", makeEmissionsRecipe("depot", readDepotEmissions))
if not MaintenanceStationEmissionsPlugin then
	log("maintenance station plugin recipe not registered")
end

-- Entry point of a .script.lua resource: the engine (loaderHelper:useFn)
-- ignores the chunk return value and calls the global data() instead. A
-- trailing `return {...}` aborts the GUI bootstrap with
-- "function data() not defined".
function data()
	return {
		IndustryEmissionsPlugin = IndustryEmissionsPlugin,
		MaintenanceStationEmissionsPlugin = MaintenanceStationEmissionsPlugin,
	}
end
