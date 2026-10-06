-- Matcher: Kriterien-Prüfung - rein, ohne WoW-API, damit busted-testbar
local _, ns = ...

local Buffs = type(ns) == "table" and ns.Buffs or dofile("Modules/Buffs.lua")

local Matcher = {}
if type(ns) == "table" then
	ns.Matcher = Matcher
end

Matcher.ROLES = { "TANK", "HEALER", "DAMAGER" }

-- Erkennungszeichen für KQ-Gruppen im Mindestscore - mit der Keystufe darin, denn der Gruppenname
-- (mit der Stufe) ist für Addons nicht lesbar, der Mindestscore schon (Phase 0):
--   Tausender + Keystufe * 10 + 7, z. B. +18 -> ...187. Endziffer 7 und eine gültige Stufe = KeyQueue.
-- Der Mindestscore ist zugleich Blizzards echte Hürde: er darf nie über dem Wunsch des Leaders liegen
-- (sonst sperrt Blizzard passende Spieler aus) - daher die Tausender abgerundet und einer weniger.
-- Den genauen Wunschwert prüft der Leader-Matcher selbst.
Matcher.MARKER_DIGIT = 7
Matcher.MARKER_MIN_LEVEL = 2
Matcher.MARKER_MAX_LEVEL = 40

function Matcher.EncodeMarkerScore(minScore, level)
	level = math.max(Matcher.MARKER_MIN_LEVEL, math.min(Matcher.MARKER_MAX_LEVEL, math.floor(level or 2)))
	local code = level * 10 + Matcher.MARKER_DIGIT
	local thousands = math.max(0, math.floor((math.floor(minScore or 0) - code) / 1000)) * 1000
	return thousands + code
end

-- Keystufe aus dem Kennzeichen, nil = kein KeyQueue-Kennzeichen
function Matcher.DecodeMarkerLevel(score)
	if type(score) ~= "number" or score <= 0 or score % 10 ~= Matcher.MARKER_DIGIT then
		return nil
	end
	local level = math.floor((score % 1000) / 10)
	if level >= Matcher.MARKER_MIN_LEVEL and level <= Matcher.MARKER_MAX_LEVEL then
		return level
	end
end

function Matcher.IsMarkerScore(score)
	return Matcher.DecodeMarkerLevel(score) ~= nil
end

-- Einheitlicher Namensschlüssel: Realm nur, wenn es nicht der eigene ist
function Matcher.NameKey(name, ownRealm)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local short, realm = name:match("^([^%-]+)%-(.+)$")
	if not short then
		return name
	end
	if realm == ownRealm then
		return short
	end
	return short .. "-" .. realm
end

local function Copy(source)
	local target = {}
	for key, value in pairs(source) do
		target[key] = value
	end
	return target
end

-- Können die offenen Plätze die noch fehlenden Buffs abdecken? (max. 2 Buffs, wenige Plätze)
local function CanCover(missing, slots, index)
	index = index or 1
	local buff = missing[index]
	if not buff then
		return true
	end
	for _, role in ipairs(Matcher.ROLES) do
		local count = slots[role] or 0
		if count > 0 and Buffs.RoleCanProvide(role, buff) then
			slots[role] = count - 1
			local ok = CanCover(missing, slots, index + 1)
			slots[role] = count
			if ok then
				return true
			end
		end
	end
	return false
end

local function MissingBuffs(criteria, classes)
	local missing = {}
	if criteria.needBloodlust and not Buffs.GroupHas(classes, "BLOODLUST") then
		table.insert(missing, "BLOODLUST")
	end
	if criteria.needBattleRez and not Buffs.GroupHas(classes, "BATTLEREZ") then
		table.insert(missing, "BATTLEREZ")
	end
	return missing
end

function Matcher.TotalOpen(open)
	local total = 0
	for _, role in ipairs(Matcher.ROLES) do
		total = total + math.max(0, open[role] or 0)
	end
	return total
end

--[[
Prüft einen Bewerber gegen die Kriterien des Leaders.

criteria  = { minScore, maxScore, minItemLevel, minTimedHere, needBloodlust, needBattleRez } (0/nil = egal)
            minTimedHere: gelisteten Dungeon mindestens auf dieser Stufe getimt (player.here)
state     = { open = { TANK = n, HEALER = n, DAMAGER = n }, classes = { "MAGE", ... } }
            classes: Klassen in der Gruppe inkl. bereits eingeladener Spieler
applicant = { class, score, itemLevel, assignedRole, roles = { TANK = bool, ... }, numMembers,
              here = { level, timed } (bester Run im gelisteten Dungeon, nil = unbekannt),
              members = { { class, score, itemLevel, assignedRole, roles, here }, ... } (nur Gruppen-Bewerbung) }

Rückgabe: true, role  oder  false, reason
          Gruppen-Bewerbung: true, { role1, role2, ... } (Rolle je Mitglied)
reason: PARTY (Mitglieder noch unbekannt), SCORE_LOW, SCORE_HIGH, ILVL_LOW, HERE_LOW, NO_ROLE, ROLE_FULL, BUFF_NEEDED
]]
local function CheckStats(criteria, player)
	local score = player.score or 0
	if (criteria.minScore or 0) > 0 and score < criteria.minScore then
		return false, "SCORE_LOW"
	end
	if (criteria.maxScore or 0) > 0 and score > criteria.maxScore then
		return false, "SCORE_HIGH"
	end
	if (criteria.minItemLevel or 0) > 0 and (player.itemLevel or 0) < criteria.minItemLevel then
		return false, "ILVL_LOW"
	end
	-- Matchmaking: Wertung im Fenster um den Leader (ähnliche Spielstärke im Team)
	if criteria.ratingWindow and criteria.ratingCenter and math.abs(score - criteria.ratingCenter) > criteria.ratingWindow then
		return false, "RATING"
	end
	-- Erfahrung im gelisteten Dungeon: getimt auf mindestens dieser Stufe (unbekannt zählt als nein)
	local minHere = criteria.minTimedHere or 0
	if minHere > 0 then
		local here = player.here
		if not (here and here.timed and (here.level or 0) >= minHere) then
			return false, "HERE_LOW"
		end
	end
	return true
end

-- Rollen, die der Spieler angeboten hat; seine Spec-Rolle zuerst
local function RoleCandidates(player)
	local roles = player.roles or {}
	local candidates = {}
	if player.assignedRole and roles[player.assignedRole] then
		table.insert(candidates, player.assignedRole)
	end
	for _, role in ipairs(Matcher.ROLES) do
		if roles[role] and role ~= player.assignedRole then
			table.insert(candidates, role)
		end
	end
	return candidates
end

-- Gruppen-Bewerbung: jedes Mitglied muss Score/iLvl erfüllen, zusammen brauchen alle einen freien Platz
function Matcher.EvaluateParty(criteria, state, members)
	local candidates = {}
	local classes = Copy(state.classes or {})
	for index, member in ipairs(members) do
		local ok, reason = CheckStats(criteria, member)
		if not ok then
			return false, reason
		end
		candidates[index] = RoleCandidates(member)
		if #candidates[index] == 0 then
			return false, "NO_ROLE"
		end
		table.insert(classes, member.class)
	end
	local missing = MissingBuffs(criteria, classes)

	-- Rollen verteilen (max. 4 Mitglieder, einfaches Backtracking)
	local assignment, roleFit = {}, false
	local function Assign(index, slots)
		if index > #members then
			roleFit = true
			return CanCover(missing, slots)
		end
		for _, role in ipairs(candidates[index]) do
			local open = slots[role] or 0
			if open > 0 then
				slots[role] = open - 1
				assignment[index] = role
				if Assign(index + 1, slots) then
					return true
				end
				slots[role] = open
			end
		end
		return false
	end
	if Assign(1, Copy(state.open)) then
		return true, Copy(assignment)
	end
	return false, roleFit and "BUFF_NEEDED" or "ROLE_FULL"
end

function Matcher.Evaluate(criteria, state, applicant)
	if (applicant.numMembers or 1) > 1 then
		if not applicant.members or #applicant.members < applicant.numMembers then
			return false, "PARTY"
		end
		return Matcher.EvaluateParty(criteria, state, applicant.members)
	end

	local ok, reason = CheckStats(criteria, applicant)
	if not ok then
		return false, reason
	end
	local candidates = RoleCandidates(applicant)
	if #candidates == 0 then
		return false, "NO_ROLE"
	end

	local classes = Copy(state.classes or {})
	table.insert(classes, applicant.class)
	local missing = MissingBuffs(criteria, classes)

	local anyOpen = false
	for _, role in ipairs(candidates) do
		local open = state.open[role] or 0
		if open > 0 then
			anyOpen = true
			local slots = Copy(state.open)
			slots[role] = open - 1
			-- Bedarf aktualisiert sich live: fehlt noch ein Buff, muss ein Restplatz ihn bringen können
			if CanCover(missing, slots) then
				return true, role
			end
		end
	end
	return false, anyOpen and "BUFF_NEEDED" or "ROLE_FULL"
end

---------------------------------------------------------------------------
-- Spieler-Seite: passt eine gefundene Gruppe zu mir (und meiner Party)?
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Zusammensetzung und Ausdrücke (Prinzip Premade Groups Filter, eigene Umsetzung)
---------------------------------------------------------------------------

-- Nahkampf-DPS-Specs; alle anderen DPS gelten als Fernkampf (auch künftige neue Specs)
Matcher.MELEE_SPECS = {
	[251] = true, [252] = true, -- Todesritter Frost, Unheilig
	[577] = true,               -- Dämonenjäger Verwüstung
	[103] = true,               -- Druide Wildheit
	[255] = true,               -- Jäger Überleben
	[269] = true,               -- Mönch Windläufer
	[70] = true,                -- Paladin Vergeltung
	[259] = true, [260] = true, [261] = true, -- Schurke
	[263] = true,               -- Schamane Verstärkung
	[71] = true, [72] = true,   -- Krieger Waffen, Furor
}

-- Klassen-Zähler für Ausdrücke, z. B. "shamans == 0"
Matcher.CLASS_VARIABLES = {
	DEATHKNIGHT = "deathknights", DEMONHUNTER = "demonhunters", DRUID = "druids", EVOKER = "evokers",
	HUNTER = "hunters", MAGE = "mages", MONK = "monks", PALADIN = "paladins", PRIEST = "priests",
	ROGUE = "rogues", SHAMAN = "shamans", WARLOCK = "warlocks", WARRIOR = "warriors",
}

-- Alle Variablen, die ein Ausdruck verwenden darf (Reihenfolge = Hilfe-Anzeige)
Matcher.EXPRESSION_VARIABLES = {
	"members", "tanks", "heals", "dps", "melees", "ranged",
	"partyfit", "hasbl", "hasbr", "blfit", "brfit",
	"mprating", "bestrun", "timed", "minscore", "ilvl", "myscore", "myilvl",
	"age", "kq", "autoinv", "leaver", "declined", "voice", "myrealm",
}

local ALLOWED_WORDS = { ["and"] = true, ["or"] = true, ["not"] = true, ["true"] = true, ["false"] = true }
for _, name in ipairs(Matcher.EXPRESSION_VARIABLES) do
	ALLOWED_WORDS[name] = true
end
for _, name in pairs(Matcher.CLASS_VARIABLES) do
	ALLOWED_WORDS[name] = true
end

local function CountRoles(group)
	local counts = { TANK = 0, HEALER = 0, DAMAGER = 0, melee = 0, ranged = 0 }
	for _, member in ipairs(group.members or {}) do
		local role = member.role or "DAMAGER"
		counts[role] = (counts[role] or 0) + 1
		if role == "DAMAGER" then
			if member.specID and Matcher.MELEE_SPECS[member.specID] then
				counts.melee = counts.melee + 1
			else
				counts.ranged = counts.ranged + 1
			end
		end
	end
	return counts
end

local function HasSpaceFor(group, me)
	local need = {}
	for _, role in ipairs(me.roles or {}) do
		need[role] = (need[role] or 0) + 1
	end
	for role, count in pairs(need) do
		if ((group.remaining or {})[role] or 0) < count then
			return false
		end
	end
	return true
end

--[[
Ausdruck übersetzen: nur bekannte Variablen, Zahlen, Vergleiche, and/or/not und Klammern.
Keine Funktionen, Strings oder Schlüsselwörter - so kann ein Ausdruck nie hängen oder auf WoW zugreifen.
Rückgabe: compiled  oder  nil, reason, detail  (reason: CHARS, UNKNOWN, SYNTAX)
]]
function Matcher.CompileExpression(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return nil
	end
	local badChar = text:match("[^%w%s_%(%)<>=~%+%-%*/%%%.]")
	if badChar then
		return nil, "CHARS", badChar
	end
	for word in text:gmatch("[%a_][%w_]*") do
		if not ALLOWED_WORDS[word] then
			return nil, "UNKNOWN", word
		end
	end

	local code = "return (" .. text .. ")"
	local env = {}
	local fn
	if setfenv and loadstring then -- WoW (Lua 5.1)
		fn = loadstring(code, "KeyQueue")
		if fn then
			setfenv(fn, env)
		end
	else -- Lua 5.2+ (Tests außerhalb von WoW)
		fn = load(code, "KeyQueue", "t", env)
	end
	if not fn then
		return nil, "SYNTAX"
	end
	return { fn = fn, env = env, text = text }
end

-- Zerlegt einen Ausdruck in Bausteine (für die Übersetzung "Bedeutet: ..." und "Zurück")
function Matcher.TokenizeExpression(text)
	local tokens = {}
	local position, length = 1, #(text or "")
	while position <= length do
		local rest = text:sub(position)
		local space = rest:match("^%s+")
		if space then
			position = position + #space
		else
			local token = rest:match("^[%a_][%w_]*") or rest:match("^%d+%.?%d*")
				or rest:match("^[<>~=]=") or rest:match("^.")
			table.insert(tokens, token)
			position = position + #token
		end
	end
	return tokens
end

-- Ja/Nein-Variablen sind allein schon eine Bedingung; alle anderen sind Zahlen und brauchen einen Vergleich
Matcher.BOOLEAN_VARIABLES = {
	partyfit = true, hasbl = true, hasbr = true, blfit = true, brfit = true, timed = true,
	kq = true, autoinv = true, leaver = true, declined = true, voice = true, myrealm = true,
}

local COMPARISONS = { ["=="] = true, ["~="] = true, ["<"] = true, [">"] = true, ["<="] = true, [">="] = true }

local function TokenKind(token)
	if not token then
		return "start"
	elseif COMPARISONS[token] then
		return "compare"
	elseif token == "and" or token == "or" then
		return "connector"
	elseif token == "not" then
		return "not"
	elseif token == "(" then
		return "open"
	elseif token == ")" then
		return "close"
	elseif token:match("^%d") then
		return "number"
	elseif Matcher.BOOLEAN_VARIABLES[token] then
		return "flag"
	end
	return "value" -- Zahl-Variable wie tanks oder mprating
end

--[[
Baustein mitdenkend anhängen, damit auch Einsteiger nur gültige Ausdrücke klicken:
- Bedingung auf Bedingung: automatisch "and" dazwischen
- Zahl-Variable + Zahl: automatisch "=="
- Zahl-Variable + neue Bedingung: Zahl-Variable wird zu "mindestens 1"
- zweiter Vergleich / zweite Zahl ersetzt den vorigen; "and"/"or" am Anfang wird ignoriert
]]
function Matcher.AppendExpressionToken(text, token)
	local tokens = Matcher.TokenizeExpression(text)
	local lastKind, newKind = TokenKind(tokens[#tokens]), TokenKind(token)
	local termEnded = lastKind == "flag" or lastKind == "number" or lastKind == "close"
	local startsTerm = newKind == "flag" or newKind == "value" or newKind == "not" or newKind == "open"

	if lastKind == "value" then
		if newKind == "number" then
			table.insert(tokens, "==")
		elseif startsTerm or newKind == "connector" or newKind == "close" then
			table.insert(tokens, ">=")
			table.insert(tokens, "1")
			if startsTerm then
				table.insert(tokens, "and")
			end
		end
	elseif termEnded and startsTerm then
		table.insert(tokens, "and")
	elseif (lastKind == "compare" and newKind == "compare") or (lastKind == "number" and newKind == "number") then
		table.remove(tokens)
	elseif newKind == "connector" and not termEnded then
		return table.concat(tokens, " ")
	end
	table.insert(tokens, token)
	return table.concat(tokens, " ")
end

-- Was fehlt als Nächstes? "compare" (nach Zahl-Variable), "number" (nach Vergleich), "term" (nach und/oder/nicht)
function Matcher.ExpressionNextStep(text)
	local tokens = Matcher.TokenizeExpression(text)
	local kind = TokenKind(tokens[#tokens])
	if kind == "value" then
		return "compare"
	elseif kind == "compare" then
		return "number"
	elseif kind == "connector" or kind == "not" or kind == "open" then
		return "term"
	end
end

function Matcher.GroupVariables(group, me)
	local counts = CountRoles(group)
	local classes = group.classes or {}
	local myClasses = me.classes or {}
	local hasbl, hasbr = Buffs.GroupHas(classes, "BLOODLUST"), Buffs.GroupHas(classes, "BATTLEREZ")
	local vars = {
		members = group.numMembers or #(group.members or {}),
		tanks = counts.TANK, heals = counts.HEALER, dps = counts.DAMAGER,
		melees = counts.melee, ranged = counts.ranged,
		partyfit = HasSpaceFor(group, me),
		hasbl = hasbl, hasbr = hasbr,
		blfit = hasbl or Buffs.GroupHas(myClasses, "BLOODLUST"),
		brfit = hasbr or Buffs.GroupHas(myClasses, "BATTLEREZ"),
		mprating = group.leaderScore or 0, bestrun = group.leaderBestLevel or 0, timed = group.leaderTimed and true or false,
		minscore = group.requiredScore or 0, ilvl = group.requiredItemLevel or 0,
		myscore = me.score or 0, myilvl = me.itemLevel or 0,
		age = group.ageMinutes or 0,
		kq = group.isKeyQueue and true or false, autoinv = group.autoAccept and true or false,
		leaver = group.hasLeaver and true or false, declined = group.declined and true or false,
		voice = group.hasVoice and true or false, myrealm = group.sameRealm and true or false,
	}
	for _, name in pairs(Matcher.CLASS_VARIABLES) do
		vars[name] = 0
	end
	for _, class in ipairs(classes) do
		local name = Matcher.CLASS_VARIABLES[class]
		if name then
			vars[name] = vars[name] + 1
		end
	end
	return vars
end

-- true/false; bei Laufzeitfehlern (z. B. "tanks + true") passt die Gruppe nicht
function Matcher.EvaluateExpression(compiled, vars)
	local env = compiled.env
	for key in pairs(env) do
		env[key] = nil
	end
	for key, value in pairs(vars) do
		env[key] = value
	end
	local ok, result = pcall(compiled.fn)
	if not ok then
		return false, "RUNTIME"
	end
	return result and true or false
end

local function InRange(value, minValue, maxValue)
	return (not minValue or value >= minValue) and (not maxValue or value <= maxValue)
end

-- Buff-Filter: "any" (egal), "has" (Gruppe hat ihn schon), "missing" (fehlt noch - z. B. weil ich ihn mitbringe)
local function CheckBuff(mode, classes, buff)
	if mode == "has" and not Buffs.GroupHas(classes, buff) then
		return false
	end
	if mode == "missing" and Buffs.GroupHas(classes, buff) then
		return false
	end
	return true
end

--[[
criteria = { activityGroups = { [groupID] = true } (leer = alle), minLeaderScore, maxLeaderScore, onlyKeyQueue,
             bloodlust, battleRez ("any"/"has"/"missing"), hasTank, hasHealer, notMyClass, noLeaver,
             hideDeclined, leaderTimed, playstyles = { [1..4] = true } (leer = alle) }
group    = { activityGroupID, leaderScore, requiredScore, requiredItemLevel, isKeyQueue, delisted,
             remaining = { TANK = n, HEALER = n, DAMAGER = n }, classes = { "MAGE", ... },
             members = { { class, role } }, hasLeaver, declined, leaderTimed, playstyle }
me       = { roles = { "DAMAGER", ... } (eine Rolle pro Party-Mitglied), classes = { ... }, score, itemLevel }

Rückgabe: true  oder  false, reason
reason: DELISTED, DECLINED, DUNGEON, KQ_ONLY, PLAYSTYLE, LEADER_SCORE_LOW, LEADER_SCORE_HIGH, LEADER_NOT_TIMED,
        REQ_SCORE, REQ_ILVL, NO_SPACE, NO_TANK, NO_HEALER, SAME_CLASS, LEAVER, NO_BLOODLUST, HAS_BLOODLUST,
        NO_BATTLEREZ, HAS_BATTLEREZ
]]
function Matcher.MatchGroup(criteria, group, me)
	if group.delisted then
		return false, "DELISTED"
	end
	if criteria.hideDeclined and group.declined then
		return false, "DECLINED"
	end
	if criteria.activityGroups and next(criteria.activityGroups) and not criteria.activityGroups[group.activityGroupID] then
		return false, "DUNGEON"
	end
	if criteria.onlyKeyQueue and not group.isKeyQueue then
		return false, "KQ_ONLY"
	end
	-- Matchmaking-Queue: Keystufe wie in Blizzards Suche über den Suchtext (levelLow/levelHigh, schon vom
	-- Server gefiltert; KeyQueue-Gruppen tragen die Stufe zusätzlich im Kennzeichen). Ohne Stufenwunsch nur
	-- Keys, die etwas bringen: im Dungeon noch nicht so hoch getimt (criteria.bestRuns[challengeMapID]).
	-- Normale Gruppen (includeNormal) nur mit Stufenwunsch - ihre Stufe steht nur im gesperrten Namen.
	if criteria.matchmaking then
		local low, high = criteria.levelLow, criteria.levelHigh
		local level = group.kqLevel
		if not group.isKeyQueue then
			if not criteria.includeNormal then
				return false, "KQ_ONLY"
			end
			if not (low or high) then
				return false, "LEVEL_UNKNOWN"
			end
		elseif (low and level < low) or (high and level > high) then
			return false, "LEVEL"
		end
		if not (low or high) then
			local best = criteria.bestRuns and criteria.bestRuns[group.challengeMapID]
			if best and level and (level < best.level or (level == best.level and best.timed)) then
				return false, "NO_UPGRADE"
			end
		end
	end
	if criteria.ratingWindow and criteria.ratingCenter
		and math.abs((group.leaderScore or 0) - criteria.ratingCenter) > criteria.ratingWindow then
		return false, "RATING"
	end
	if criteria.playstyles and next(criteria.playstyles) and not criteria.playstyles[group.playstyle] then
		return false, "PLAYSTYLE"
	end

	local leaderScore = group.leaderScore or 0
	if (criteria.minLeaderScore or 0) > 0 and leaderScore < criteria.minLeaderScore then
		return false, "LEADER_SCORE_LOW"
	end
	if (criteria.maxLeaderScore or 0) > 0 and leaderScore > criteria.maxLeaderScore then
		return false, "LEADER_SCORE_HIGH"
	end
	if criteria.leaderTimed and not group.leaderTimed then
		return false, "LEADER_NOT_TIMED"
	end

	-- Anforderungen der Gruppe, die ich erfüllen muss (sonst lehnt Blizzard die Bewerbung ab)
	if (group.requiredScore or 0) > (me.score or 0) then
		return false, "REQ_SCORE"
	end
	if (group.requiredItemLevel or 0) > (me.itemLevel or 0) then
		return false, "REQ_ILVL"
	end

	-- Platz für alle Rollen meiner Party (Prinzip partyfit)
	if not HasSpaceFor(group, me) then
		return false, "NO_SPACE"
	end

	-- Zusammensetzung: Mitglieder, Tanks, Heiler, DPS jeweils von-bis (nil = egal)
	local counts = CountRoles(group)
	if not InRange(group.numMembers or #(group.members or {}), criteria.membersMin, criteria.membersMax) then
		return false, "MEMBERS"
	end
	if not InRange(counts.TANK, criteria.tanksMin, criteria.tanksMax) then
		return false, "TANKS"
	end
	if not InRange(counts.HEALER, criteria.healersMin, criteria.healersMax) then
		return false, "HEALERS"
	end
	if not InRange(counts.DAMAGER, criteria.dpsMin, criteria.dpsMax) then
		return false, "DPS"
	end
	if criteria.maxAge and (group.ageMinutes or 0) > criteria.maxAge then
		return false, "AGE"
	end

	local roles = {}
	for _, member in ipairs(group.members or {}) do
		if member.role then
			roles[member.role] = true
		end
	end
	if criteria.hasTank and not roles.TANK then
		return false, "NO_TANK"
	end
	if criteria.hasHealer and not roles.HEALER then
		return false, "NO_HEALER"
	end

	local classes = group.classes or {}
	if criteria.notMyClass then
		for _, mine in ipairs(me.classes or {}) do
			for _, theirs in ipairs(classes) do
				if mine == theirs then
					return false, "SAME_CLASS"
				end
			end
		end
	end
	if criteria.noLeaver and group.hasLeaver then
		return false, "LEAVER"
	end

	if not CheckBuff(criteria.bloodlust, classes, "BLOODLUST") then
		return false, criteria.bloodlust == "has" and "NO_BLOODLUST" or "HAS_BLOODLUST"
	end
	if not CheckBuff(criteria.battleRez, classes, "BATTLEREZ") then
		return false, criteria.battleRez == "has" and "NO_BATTLEREZ" or "HAS_BATTLEREZ"
	end

	-- Experten-Ausdruck zuletzt (bereits übersetzt, siehe CompileExpression)
	if criteria.expression and not Matcher.EvaluateExpression(criteria.expression, Matcher.GroupVariables(group, me)) then
		return false, "EXPRESSION"
	end
	return true
end

-- Reihenfolge der Treffer: KQ-Gruppen zuerst (laden automatisch ein), dann höherer Leader-Score
function Matcher.CompareGroups(a, b)
	if (a.isKeyQueue and true or false) ~= (b.isKeyQueue and true or false) then
		return a.isKeyQueue and true or false
	end
	return (a.leaderScore or 0) > (b.leaderScore or 0)
end

return Matcher
