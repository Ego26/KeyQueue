-- Matchmaker: formt aus dem Pool wartender Spieler Teams für einen Key (Prinzip Faceit) - rein, ohne
-- WoW-API, damit busted-testbar. Jeder Client rechnet mit denselben Daten dasselbe Ergebnis aus
-- (feste Reihenfolge, keine Zufälle).
--
-- Gleichbehandlung: Fraktion, Realm und Wertung geben KEINEN Vorrang. Die Reihenfolge bestimmt allein
-- die Wartezeit (wer zuerst in der Queue ist, kommt zuerst dran). Alles andere sind Bedingungen, die
-- jeder Spieler selbst setzt - und die für alle gleich gelten (Stufenbereich, Dungeons, Mindestwertung).
local _, ns = ...

local Matchmaker = {}
if type(ns) == "table" then
	ns.Matchmaker = Matchmaker
end

Matchmaker.ROLES = { "TANK", "HEALER", "DAMAGER" }
Matchmaker.TEAM = { TANK = 1, HEALER = 1, DAMAGER = 3 }
-- so viele Key-Halter probiert der Matchmaker pro wartendem Spieler (hält die Rechenzeit klein)
Matchmaker.KEY_TRIES = 8
-- Wertungsfenster (wie Elo bei Faceit): ein Team besteht aus Spielern mit ähnlicher Wertung - alle
-- liegen höchstens WINDOW um die Wertung des am längsten Wartenden. Das Fenster wächst mit dessen
-- Wartezeit (für alle gleich schnell), damit niemand ewig hängt. Angefangene Minuten zählen nicht.
Matchmaker.WINDOW_BASE = 250
Matchmaker.WINDOW_PER_MINUTE = 50
Matchmaker.WINDOW_MAX = 1000
Matchmaker.VERSION = 1

--[[
Ticket = ein Eintrag in der Queue: ein Spieler oder eine Gruppe (bis 4) mit ihrem Leader als id
{
  id = "Name-Realm",          -- eindeutig (Leader der Gruppe), auch Gleichstand-Entscheider
  queuedAt = 1790000000,      -- Serverzeit beim Anmelden (alle Clients sehen dieselbe Uhr)
  minLevel = 15, maxLevel = 18, -- Stufenbereich (maxLevel 0/nil = egal)
  dungeons = { [groupID] = true } oder nil = alle,
  minScore = 0,               -- Mindestwertung, die ALLE anderen im Team haben müssen (0 = egal)
  key = { level = 17, groupID = 420 } oder nil, -- eigener Key, den der Spieler einbringt
  members = { { roles = { TANK = true, ... }, primary = "TANK", score = 3500 }, ... }
}
Spielstärke eines Mitglieds: member.rating, sonst member.score (RIO). rating ist für später gedacht
(z. B. Wertung kombiniert mit Logs), ohne den Matchmaker umzubauen.
Match = { key = Ticket.key, leader = id des Key-Halters, tickets = { Ticket, ... },
          roles = { [ticketId] = { "TANK", ... } } (Rolle je Mitglied, in der Reihenfolge von members) }
]]

local function Needs()
	return { TANK = Matchmaker.TEAM.TANK, HEALER = Matchmaker.TEAM.HEALER, DAMAGER = Matchmaker.TEAM.DAMAGER }
end

local function Open(needs)
	return needs.TANK + needs.HEALER + needs.DAMAGER
end

-- Passt der Key zu den Wünschen des Tickets (Stufe, Dungeon)?
function Matchmaker.KeyFits(ticket, key)
	if (key.level or 0) < (ticket.minLevel or 0) then
		return false
	end
	if (ticket.maxLevel or 0) > 0 and key.level > ticket.maxLevel then
		return false
	end
	if ticket.dungeons and next(ticket.dungeons) ~= nil and not ticket.dungeons[key.groupID] then
		return false
	end
	return true
end

local function Rating(member)
	return member.rating or member.score or 0
end

-- Mitte des Teams: Spielstärke des am längsten Wartenden (Gruppe: Durchschnitt)
local function Center(ticket)
	local total = 0
	for _, member in ipairs(ticket.members) do
		total = total + Rating(member)
	end
	return total / #ticket.members
end

-- Fenster um die Mitte: wächst je volle Minute Wartezeit (now = Serverzeit; ohne now das Grundfenster)
function Matchmaker.Window(ticket, now)
	local minutes = now and math.max(0, math.floor((now - (ticket.queuedAt or now)) / 60)) or 0
	return math.min(Matchmaker.WINDOW_MAX, Matchmaker.WINDOW_BASE + minutes * Matchmaker.WINDOW_PER_MINUTE)
end

local function InWindow(ticket, center, window)
	for _, member in ipairs(ticket.members) do
		if math.abs(Rating(member) - center) > window then
			return false
		end
	end
	return true
end

local function LowestScore(ticket)
	local lowest
	for _, member in ipairs(ticket.members) do
		local score = member.score or 0
		if not lowest or score < lowest then
			lowest = score
		end
	end
	return lowest or 0
end

-- Mindestwertung gilt in beide Richtungen: jeder erfüllt die Wünsche des anderen
function Matchmaker.ScoresFit(a, b)
	return LowestScore(a) >= (b.minScore or 0) and LowestScore(b) >= (a.minScore or 0)
end

-- Rollen der Mitglieder eines Tickets auf die offenen Plätze verteilen (Hauptrolle zuerst, sonst die
-- anderen angebotenen). needs wird dabei verringert; Rückgabe Rollen je Mitglied oder nil (passt nicht).
local function AssignRoles(members, needs, index, result)
	index, result = index or 1, result or {}
	if index > #members then
		return result
	end
	local member = members[index]
	local order = {}
	if member.primary and member.roles[member.primary] then
		table.insert(order, member.primary)
	end
	for _, role in ipairs(Matchmaker.ROLES) do
		if member.roles[role] and role ~= member.primary then
			table.insert(order, role)
		end
	end
	for _, role in ipairs(order) do
		if needs[role] > 0 then
			needs[role] = needs[role] - 1
			result[index] = role
			if AssignRoles(members, needs, index + 1, result) then
				return result
			end
			needs[role] = needs[role] + 1
			result[index] = nil
		end
	end
	return nil
end

-- Rollen für das ganze Team verteilen (nicht Ticket für Ticket: wer mehrere Rollen kann, wird umgesetzt,
-- wenn später jemand kommt, der nur eine kann). Rückgabe Rollen je Ticket oder nil (passt nicht).
local function Solve(team)
	local members, owners = {}, {}
	for _, ticket in ipairs(team) do
		for index, member in ipairs(ticket.members) do
			table.insert(members, member)
			table.insert(owners, { ticket.id, index })
		end
	end
	local assigned = AssignRoles(members, Needs())
	if not assigned then
		return nil
	end
	local roles = {}
	for position, owner in ipairs(owners) do
		roles[owner[1]] = roles[owner[1]] or {}
		roles[owner[1]][owner[2]] = assigned[position]
	end
	return roles, #members
end

-- Team um einen wartenden Spieler (anchor) mit dem Key eines Key-Halters bauen: erst die beiden, dann
-- in Wartezeit-Reihenfolge auffüllen. Rückgabe Match oder nil.
local function TryTeam(ordered, anchor, holder, used, now)
	local key = holder.key
	local size = Open(Needs())
	local center, window = Center(anchor), Matchmaker.Window(anchor, now)
	local team, roles, count = {}, nil, 0
	local function Add(ticket)
		if not Matchmaker.KeyFits(ticket, key) or not InWindow(ticket, center, window) then
			return false
		end
		for _, other in ipairs(team) do
			if not Matchmaker.ScoresFit(ticket, other) then
				return false
			end
		end
		table.insert(team, ticket)
		local solved, members = Solve(team)
		if not solved then
			table.remove(team)
			return false
		end
		roles, count = solved, members
		return true
	end
	if not Add(holder) then
		return nil
	end
	if anchor ~= holder and not Add(anchor) then
		return nil
	end
	for _, ticket in ipairs(ordered) do
		if count >= size then
			break
		end
		if ticket ~= anchor and ticket ~= holder and not used[ticket.id] then
			Add(ticket)
		end
	end
	if count < size then
		return nil
	end
	return { key = key, leader = holder.id, tickets = team, roles = roles }
end

-- Wartezeit-Reihenfolge: wer zuerst kam, zuerst; bei Gleichstand die id (für alle Clients gleich)
local function Ordered(pool)
	local list = {}
	for _, ticket in ipairs(pool) do
		if type(ticket.members) == "table" and #ticket.members > 0 then
			table.insert(list, ticket)
		end
	end
	table.sort(list, function(a, b)
		if (a.queuedAt or 0) ~= (b.queuedAt or 0) then
			return (a.queuedAt or 0) < (b.queuedAt or 0)
		end
		return a.id < b.id
	end)
	return list
end

-- Alle Teams, die sich aus dem Pool bilden lassen. Wer am längsten wartet, wird zuerst versorgt:
-- mit dem eigenen Key, sonst dem Key des am längsten wartenden passenden Key-Halters.
-- now = Serverzeit (für das mitwachsende Wertungsfenster); ohne now gilt das Grundfenster.
function Matchmaker.FindMatches(pool, now)
	local ordered = Ordered(pool)
	local used, matches = {}, {}
	for _, anchor in ipairs(ordered) do
		if not used[anchor.id] then
			local holders = {}
			if anchor.key then
				table.insert(holders, anchor)
			end
			for _, ticket in ipairs(ordered) do
				if #holders >= Matchmaker.KEY_TRIES then
					break
				end
				if ticket ~= anchor and ticket.key and not used[ticket.id] then
					table.insert(holders, ticket)
				end
			end
			for _, holder in ipairs(holders) do
				local match = TryTeam(ordered, anchor, holder, used, now)
				if match then
					for _, ticket in ipairs(match.tickets) do
						used[ticket.id] = true
					end
					table.insert(matches, match)
					break
				end
			end
		end
	end
	return matches
end

-- Pool-Anzeige ("23 in Queue: 4 Tanks, 5 Heiler, 14 DPS, 6 Keys") nach Hauptrolle
function Matchmaker.PoolStats(pool)
	local stats = { players = 0, TANK = 0, HEALER = 0, DAMAGER = 0, keys = 0 }
	for _, ticket in ipairs(pool) do
		for _, member in ipairs(ticket.members or {}) do
			stats.players = stats.players + 1
			local role = member.primary or "DAMAGER"
			stats[role] = (stats[role] or 0) + 1
		end
		if ticket.key then
			stats.keys = stats.keys + 1
		end
	end
	return stats
end

---------------------------------------------------------------------------
-- Ticket als kurzer Text für Addon-Nachrichten (max. 255 Zeichen)
-- "T1|queuedAt|minLevel|maxLevel|minScore|keyLevel|keyGroup|d1,d2|THD:3500|D:3400"
-- Rollen je Mitglied als Buchstaben (T/H/D), Hauptrolle zuerst. Die id ist der Absender.
---------------------------------------------------------------------------

local LETTER = { TANK = "T", HEALER = "H", DAMAGER = "D" }
local ROLE_OF = { T = "TANK", H = "HEALER", D = "DAMAGER" }

function Matchmaker.Encode(ticket)
	local dungeons = {}
	for groupID in pairs(ticket.dungeons or {}) do
		table.insert(dungeons, tostring(groupID))
	end
	table.sort(dungeons)
	local parts = {
		"T" .. Matchmaker.VERSION, math.floor(ticket.queuedAt or 0), ticket.minLevel or 0, ticket.maxLevel or 0,
		ticket.minScore or 0, ticket.key and ticket.key.level or 0, ticket.key and ticket.key.groupID or 0,
		table.concat(dungeons, ","),
	}
	for _, member in ipairs(ticket.members) do
		local letters = member.primary and LETTER[member.primary] or ""
		for _, role in ipairs(Matchmaker.ROLES) do
			if member.roles[role] and role ~= member.primary then
				letters = letters .. LETTER[role]
			end
		end
		table.insert(parts, letters .. ":" .. math.floor(member.score or 0))
	end
	return table.concat(parts, "|")
end

-- Rückgabe Ticket oder nil (fremde Version, kaputte Nachricht)
function Matchmaker.Decode(text, id)
	if type(text) ~= "string" or type(id) ~= "string" then
		return nil
	end
	local parts = {}
	for part in (text .. "|"):gmatch("([^|]*)|") do
		table.insert(parts, part)
	end
	if parts[1] ~= "T" .. Matchmaker.VERSION or #parts < 9 then
		return nil
	end
	local numbers = {}
	for index = 2, 7 do
		numbers[index] = tonumber(parts[index])
		if not numbers[index] then
			return nil
		end
	end
	local ticket = {
		id = id, queuedAt = numbers[2], minLevel = numbers[3], maxLevel = numbers[4], minScore = numbers[5],
		members = {},
	}
	if numbers[6] > 0 and numbers[7] > 0 then
		ticket.key = { level = numbers[6], groupID = numbers[7] }
	end
	if parts[8] ~= "" then
		ticket.dungeons = {}
		for groupID in parts[8]:gmatch("[^,]+") do
			local value = tonumber(groupID)
			if not value then
				return nil
			end
			ticket.dungeons[value] = true
		end
	end
	for index = 9, math.min(#parts, 12) do
		local letters, score = parts[index]:match("^([THD]+):(%d+)$")
		if not letters then
			return nil
		end
		local member = { roles = {}, primary = ROLE_OF[letters:sub(1, 1)], score = tonumber(score) }
		for letter in letters:gmatch(".") do
			member.roles[ROLE_OF[letter]] = true
		end
		table.insert(ticket.members, member)
	end
	return ticket
end

return Matchmaker
