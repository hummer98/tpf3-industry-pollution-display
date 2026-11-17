-- Plugs the emissions card into the base depot / maintenance station window
-- (both open MaintenanceStationWindow). The base registers its own cards at
-- the same extension point with orders 20 (maintenance pool), 30 (balance),
-- 40 (statistics), 50 (vehicles); 25 puts the card right under the pool,
-- whose usage drives the emission.
function data()
	return {
		type = "react-plugin ::MaintenanceStationEowExtensionPoint",
		data = {
			filePath = "hummer_industry_pollution_display::/gui/ipd.script@MaintenanceStationEmissionsPlugin",
			order = 25,
		},
	}
end
