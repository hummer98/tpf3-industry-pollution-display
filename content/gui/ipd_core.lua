-- Pure helpers for the industry emissions card. No engine access here so
-- the file can be exercised offline (tests/run.lua).
local core = {}

-- Same rule as the engine's mathutil.round (floor(x + 0.5)), so the card
-- shows what the base windows would show for the same emitter values.
function core.round(x)
	return math.floor(x + 0.5)
end

-- Emitter components of the given subconstruction entities. getEmitter maps
-- an entity to its EMISSION_EMITTER component or nil; entities without one
-- (e.g. the industry's street connectors) are skipped.
function core.collectEmitters(subconstructions, getEmitter)
	local emitters = {}
	for _, entity in ipairs(subconstructions or {}) do
		local emitter = getEmitter(entity)
		if emitter then
			emitters[#emitters + 1] = emitter
		end
	end
	return emitters
end

-- Totals over a list of emitters, rounded the way the base entity windows
-- (perk.tl, vehicle_eow) present them. count tells the caller whether the
-- entity emits at all: one without any emitter shows no card, while one
-- whose emitters are currently at 0 (fully greenified, idle depot) still does.
function core.sumEmissions(emitters)
	local noise, pollution, count = 0, 0, 0
	for _, emitter in ipairs(emitters or {}) do
		noise = noise + (emitter.noisePower or 0)
		pollution = pollution + (emitter.pollutionPower or 0)
		count = count + 1
	end
	return {
		noise = core.round(noise),
		pollution = core.round(pollution),
		count = count,
	}
end

-- usePlugins (gui_react_util.tl) passes a react ref as the first argument
-- to the first/last plugin of a window, and the params after it. Any other
-- plugin gets the params first. This picks the params in both cases.
function core.unwrapParams(a, b)
	if type(a) == "table" and a.is_react_ref_info then
		return b
	end
	return a
end

-- Emits a line only when it differs from the previous line for the same key
-- (A, A, B, A logs A, B, A): readEmissions runs every step, so logging a
-- failure unconditionally would flood stdout.txt.
function core.makeChangeLogger(emit)
	local last = {}
	return function(key, line)
		if last[key] ~= line then
			last[key] = line
			emit(line)
		end
	end
end

return core
