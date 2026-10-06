-- Empfehlungen nach dem Key: Lob für Mitspieler ("Guter Mitspieler", "Starker Tank", "Sauber gekickt").
-- Nur Lob wird später mit der Matchmaking-Community geteilt; Kritik ("Nie wieder") landet allein auf der
-- eigenen Sperrliste und verlässt den Rechner nie. Bis dahin lokal gespeichert, je Run und Mitspieler.
local _, ns = ...

local Endorsements = {}
ns.Endorsements = Endorsements

-- Reihenfolge der Schilder im Bewertungsfenster
Endorsements.TAGS = { "TEAM", "ROLE", "KICKS" }

-- global.endorsements[runId][memberKey] = { tags = { TEAM = true, ... }, at = Zeit, shared = false }
local function Store()
	return ns.addon.db.global.endorsements
end

function Endorsements:Get(run, key)
	local byRun = run and key and Store()[run.id]
	local entry = byRun and byRun[key]
	return entry and entry.tags or {}
end

function Endorsements:Has(run, key, tag)
	return self:Get(run, key)[tag] == true
end

-- Schild an/aus; leere Einträge fallen weg (nichts Unnötiges speichern oder später verschicken)
function Endorsements:Toggle(run, key, tag)
	if not (run and key) then
		return
	end
	local store = Store()
	local byRun = store[run.id] or {}
	local entry = byRun[key] or { tags = {}, at = time() }
	entry.tags[tag] = (not entry.tags[tag]) or nil
	entry.shared = false -- geändert: beim nächsten Teilen erneut senden
	byRun[key] = next(entry.tags) and entry or nil
	store[run.id] = next(byRun) and byRun or nil
end

-- Wie oft habe ich diesen Spieler schon empfohlen (über alle Runs)?
function Endorsements:GivenCount(key)
	local count = 0
	for _, byRun in pairs(Store()) do
		if byRun[key] then
			count = count + 1
		end
	end
	return count
end
