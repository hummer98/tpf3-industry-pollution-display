-- Plugs the emissions card into the base industry window. The base
-- registers its own cards at the same extension point with orders 0
-- (notifications), 10 (production rules), 20 (boosters), 30 (stocks),
-- 40 (balance chart); 15 puts the card between the rules and the boosters.
function data()
	return {
		type = "react-plugin ::IndustryEowExtensionPoint",
		data = {
			filePath = "hummer_industry_pollution_display::/gui/ipd.script@IndustryEmissionsPlugin",
			order = 15,
		},
	}
end
