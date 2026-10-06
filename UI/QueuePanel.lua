-- KeyQueue-Panel rechts an Blizzards Gruppensuche (wie PGF): hier lebt KeyQueue künftig - Matchmaking-
-- Queue (Rolle, Stufe, Mindestwertung, Key einbringen), letzte Keys (Klick: Mitspieler bewerten),
-- Favoriten und Sperrliste. Das große KeyQueue-Fenster fällt weg, sobald die Queue läuft.
-- Die Queue selbst (Pool, Matchmaker, Match-Popup) folgt nach dem Pool-Test; der Knopf ist bis dahin aus.
local ADDON_NAME, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Theme, Util = ns.Theme, ns.Util

local QueuePanel = {}
ns.QueuePanel = QueuePanel
LibStub("AceEvent-3.0"):Embed(QueuePanel)

local WIDTH, PAD = 300, 16
local INNER = WIDTH - 2 * PAD - 6 -- rechts Platz für den Scrollbalken
local MIN_HEIGHT = 620 -- höher als die Gruppensuche: Queue und letzte Keys ohne Scrollen
local RECENT_RUNS = 5
local ROLE_KEYS = { TANK = "ROLE_TANK", HEALER = "ROLE_HEALER", DAMAGER = "ROLE_DAMAGER" }

local function Options()
	return KeyQueue.db.profile.queue
end

-- Rollen der Queue: gewählte (nur die, die die Klasse spielen kann), sonst die der aktuellen Spec
local function QueueRoles()
	local available = Util.GetAvailableRoles()
	local roles = {}
	for role in pairs(Options().roles) do
		if available[role] then
			roles[role] = true
		end
	end
	if next(roles) == nil then
		roles[Util.GetMyRole() or "DAMAGER"] = true
	end
	return roles
end

local function Ago(timestamp)
	local seconds = math.max(0, time() - (timestamp or time()))
	if seconds < 3600 then
		return L["QP_AGO_MIN"]:format(math.max(1, math.floor(seconds / 60)))
	elseif seconds < 86400 then
		return L["QP_AGO_HOURS"]:format(math.floor(seconds / 3600))
	end
	return L["QP_AGO_DAYS"]:format(math.floor(seconds / 86400))
end

-- Zahlenfeld (leer = egal) für Stufe und Mindestwertung
local function NumberField(parent, width, field, maxLetters)
	local edit = Theme.EditBox(parent, width, L["ANY"])
	edit:SetNumeric(true)
	edit:SetMaxLetters(maxLetters or 2)
	edit:SetJustifyH("CENTER")
	edit:HookScript("OnTextChanged", function(self, userInput)
		if userInput then
			Options()[field] = tonumber(self:GetText()) or 0
		end
	end)
	function edit:Sync()
		if not self:HasFocus() then
			local value = Options()[field] or 0
			self:SetText(value > 0 and tostring(value) or "")
		end
	end
	return edit
end

local function Section(parent, text)
	local label = Theme.Text(parent, 11, "dim")
	label:SetText(text)
	return label
end

-- Aufklappbare Zeile (Letzte Keys, Favoriten, Sperrliste): Name links, deutlicher Pfeil rechts,
-- Überfahren hellt die Fläche auf. toggle:SetOpen(open) dreht den Pfeil (zu: >, offen: v)
local function ToggleRow(parent, onClick)
	local toggle = CreateFrame("Button", nil, parent)
	toggle:SetHeight(32)
	Theme.SetSurface(toggle, Theme.color.none)
	toggle.label = Theme.Text(toggle, 12, "text")
	toggle.label:SetPoint("LEFT", 6, 0)
	toggle.chevron = toggle:CreateTexture(nil, "OVERLAY")
	toggle.chevron:SetSize(14, 14)
	toggle.chevron:SetPoint("RIGHT", -6, 0)
	toggle.chevron:SetTexture(Theme.media.chevron, nil, nil, "TRILINEAR")
	toggle.chevron:SetVertexColor(unpack(Theme.color.muted))
	toggle:SetScript("OnClick", onClick)
	toggle:SetScript("OnEnter", function()
		Theme.SetSurface(toggle, Theme.color.cardHover)
		toggle.chevron:SetVertexColor(unpack(Theme.color.text))
	end)
	toggle:SetScript("OnLeave", function()
		Theme.SetSurface(toggle, Theme.color.none)
		toggle.chevron:SetVertexColor(unpack(Theme.color.muted))
	end)
	function toggle:SetOpen(open)
		self.chevron:SetRotation(open and 0 or math.pi / 2)
	end
	return toggle
end

function QueuePanel:Create()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(WIDTH, 500)
	frame:SetFrameStrata("HIGH")
	frame:EnableMouse(true)
	Theme.DropShadow(frame)
	Theme.SetSurface(frame, Theme.color.bg, Theme.color.border)
	frame:Hide()
	self.frame = frame

	-- Kopf: Bildmarke, Name, Zahnrad (Einstellungen)
	local mark = frame:CreateTexture(nil, "ARTWORK")
	mark:SetSize(24, 24)
	mark:SetPoint("TOPLEFT", PAD, -14)
	mark:SetTexture(Theme.media.mark, nil, nil, "TRILINEAR")
	local title = Theme.Text(frame, 15, "text")
	title:SetPoint("LEFT", mark, "RIGHT", 8, 0)
	title:SetText(L["QP_TITLE"])
	local subtitle = Theme.Text(frame, 11, "muted")
	subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
	subtitle:SetText(L["QP_SUBTITLE"])
	local close = Theme.Button(frame, "\195\151", "ghost", 28, 28) -- ×
	Theme.SetFont(close.label, 16)
	close:SetPoint("TOPRIGHT", -8, -12)
	close:SetScript("OnClick", function()
		self:Close()
	end)
	self.closeButton = close
	local gear = Theme.Button(frame, "", "ghost", 28, 28)
	gear:SetPoint("RIGHT", close, "LEFT", -2, 0)
	gear.icon = gear:CreateTexture(nil, "OVERLAY")
	gear.icon:SetSize(15, 15)
	gear.icon:SetPoint("CENTER")
	gear.icon:SetTexture(Theme.media.gear, nil, nil, "TRILINEAR")
	gear.icon:SetVertexColor(unpack(Theme.color.muted))
	gear:SetScript("OnClick", function()
		ns.MainFrame:Open("settings")
	end)
	gear:HookScript("OnEnter", function()
		GameTooltip:SetOwner(gear, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["QP_SETTINGS"], 1, 1, 1)
		GameTooltip:Show()
	end)
	gear:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	local headRule = frame:CreateTexture(nil, "BORDER")
	headRule:SetPoint("TOPLEFT", 0, -52)
	headRule:SetPoint("TOPRIGHT", 0, -52)
	Theme.PixelHeight(headRule, 1)
	headRule:SetColorTexture(unpack(Theme.color.line))

	local scroll, child = Theme.ScrollArea(frame, 40)
	scroll:SetPoint("TOPLEFT", 0, -53)
	scroll:SetPoint("BOTTOMRIGHT", -6, 10) -- unten Abstand zum Rand: abgeschnittene Zeilen enden sauber
	child:SetWidth(WIDTH - 16)
	self.scroll, self.child = scroll, child
	self:CreateQueue(child)
	self:CreateRecent(child)
	self:CreatePlayers(child)

	self:RegisterMessage("KEYQUEUE_HISTORY_UPDATE", "Refresh")
	-- Queue-Stand: Knopf und Status (Listing, Anmeldungen, Bewerber)
	self:RegisterMessage("KEYQUEUE_QUEUE_UPDATE", "Refresh")
	self:RegisterMessage("KEYQUEUE_SEARCH_UPDATE", "RefreshStatus")
	self:RegisterMessage("KEYQUEUE_LEADER_UPDATE", "RefreshStatus")
	-- Laufzeit jede Sekunde (nur die Statuszeile, nicht das ganze Panel)
	-- und zweimal pro Sekunde die Reihe rechts der Gruppensuche prüfen: verschiebt sich ein Nachbar
	-- (PGF, Raider.IO), ohne auf/zu zu gehen, rückt KeyQueue trotzdem nach
	local elapsed, reanchor = 0, 0
	frame:SetScript("OnUpdate", function(_, delta)
		elapsed, reanchor = elapsed + delta, reanchor + delta
		if reanchor >= 0.5 then
			reanchor = 0
			local right = self:ChainRight(false)
			if right and right ~= rawget(self, "anchoredRight") then
				self:Reanchor()
			end
		end
		if elapsed >= 1 then
			elapsed = 0
			if ns.Queue:IsActive() then
				self:RefreshStatus()
			end
		end
	end)
	self:RegisterMessage("KEYQUEUE_PLAYERS_UPDATE", "Refresh")
	self:RegisterMessage("KEYQUEUE_PROFILE_CHANGED", "Refresh")
	self:RegisterEvent("BAG_UPDATE_DELAYED", "Refresh") -- neuer Schlüssel
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "Refresh")
end

---------------------------------------------------------------------------
-- Matchmaking: Rolle, Stufe, Mindestwertung, Key einbringen, Queue-Knopf
---------------------------------------------------------------------------

-- Tooltip beim Überfahren (Titel + Erklärung): die Zeilen selbst bleiben kurz
local function Explain(region, title, ...)
	local lines = { ... }
	region:HookScript("OnEnter", function()
		GameTooltip:SetOwner(region, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title, 1, 1, 1)
		for _, line in ipairs(lines) do
			GameTooltip:AddLine(line, 0.64, 0.64, 0.68, true)
		end
		GameTooltip:Show()
	end)
	region:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- Rolle als große Kachel: Glyphe oben, Name darunter; gewählt = Akzentfläche
local ROLE_GLYPHS = { TANK = "roleTank", HEALER = "roleHealer", DAMAGER = "roleDps" }
local function UpdateRoleTile(tile)
	local on, hover = tile.checked, tile:IsMouseOver()
	if on then
		Theme.SetSurface(tile, hover and Theme.color.violetHover or Theme.color.violetSoft, Theme.color.activeBorder)
	else
		Theme.SetSurface(tile, hover and Theme.color.surfaceHover or Theme.color.surface, Theme.color.border)
	end
	-- Glyphe immer in der Rollenfarbe; nicht gewählt gedämpft
	local r, g, b = unpack(Theme.roleColor[tile.role])
	tile.glyph:SetVertexColor(r, g, b, (on or hover) and 1 or 0.45)
	tile.label:SetTextColor(unpack((on or hover) and Theme.color.text or Theme.color.muted))
end

local function RoleTile(parent, role, onToggle)
	local tile = CreateFrame("Button", nil, parent)
	tile:SetHeight(58)
	tile.role = role
	tile.glyph = tile:CreateTexture(nil, "ARTWORK")
	tile.glyph:SetSize(22, 22)
	tile.glyph:SetPoint("TOP", 0, -10)
	tile.glyph:SetTexture(Theme.media[ROLE_GLYPHS[role]], nil, nil, "TRILINEAR")
	tile.label = Theme.Text(tile, 12, "muted")
	tile.label:SetPoint("BOTTOM", 0, 9)
	tile.label:SetJustifyH("CENTER")
	tile.label:SetText(L[ROLE_KEYS[role]])
	function tile:SetChecked(value)
		self.checked = value and true or false
		UpdateRoleTile(self)
	end
	tile:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		onToggle(self.checked)
	end)
	tile:SetScript("OnEnter", UpdateRoleTile)
	tile:SetScript("OnLeave", UpdateRoleTile)
	tile:SetChecked(false)
	return tile
end

-- Einstellungszeile: Name links, Wert bzw. Schalter rechts, feine Linie darunter
local ROW_HEIGHT = 42
local function SettingRow(parent, text)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:EnableMouse(true) -- für die Erklärung beim Überfahren
	row.label = Theme.Text(row, 12, "text")
	row.label:SetPoint("LEFT", 0, 0)
	row.label:SetText(text)
	Theme.Rule(row)
	return row
end

function QueuePanel:CreateQueue(child)
	self.queueTitle = Section(child, L["QP_SECTION_QUEUE"])
	self.roleChips = {}
	for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
		table.insert(self.roleChips, RoleTile(child, role, function(checked)
			local roles = Options().roles
			-- Ausgangspunkt ist, was gerade gilt (Spec-Rolle bzw. spielbare Auswahl)
			local current = QueueRoles()
			wipe(roles)
			for key in pairs(current) do
				roles[key] = true
			end
			roles[role] = checked or nil
			if next(roles) == nil then
				roles[role] = true -- mindestens eine Rolle bleibt
			end
			self:Refresh()
		end))
	end

	-- Keystufe wie bei Blizzard über den Suchtext (Feld links in der Gruppensuche) - hier nur angezeigt
	self.levelRow = SettingRow(child, L["QP_LEVEL"])
	self.levelText = Theme.Text(self.levelRow, 12, "text")
	self.levelText:SetPoint("RIGHT", 0, 0)
	self.levelText:SetJustifyH("RIGHT")
	Explain(self.levelRow, L["QP_LEVEL"], L["QP_LEVEL_TIP"], L["QP_LEVEL_TIP_FIXED"])

	-- auch normale Gruppen (ohne KeyQueue): deren Leader entscheiden selbst
	self.normalRow = SettingRow(child, L["QP_INCLUDE_NORMAL"])
	self.includeNormal = Theme.Switch(self.normalRow, "", true, function(checked)
		Options().includeNormal = checked
		if ns.Search.matchmaking then
			ns.Search:Refilter()
		end
		self:Refresh()
	end)
	self.includeNormal:SetWidth(30)
	self.includeNormal:SetPoint("RIGHT", 0, 0)
	Explain(self.normalRow, L["QP_INCLUDE_NORMAL"], L["QP_INCLUDE_NORMAL_TIP"])

	self.scoreRow = SettingRow(child, L["QP_MIN_SCORE"])
	self.minScore = NumberField(self.scoreRow, 76, "minScore", 4)
	Theme.SetMonoFont(self.minScore, 12)
	self.minScore:SetPoint("RIGHT", 0, 0)
	Explain(self.scoreRow, L["QP_MIN_SCORE"], L["QP_MIN_SCORE_TIP"])

	-- eigener Schlüssel als Karte: Dungeon-Bild, Stufe, Name, Schalter
	local keyCard = CreateFrame("Frame", nil, child)
	keyCard:SetHeight(64)
	keyCard:EnableMouse(true)
	Theme.SetSurface(keyCard, Theme.color.surface, Theme.color.border)
	keyCard.icon = keyCard:CreateTexture(nil, "ARTWORK")
	keyCard.icon:SetSize(40, 40)
	keyCard.icon:SetPoint("LEFT", 12, 0)
	keyCard.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	keyCard.title = Theme.Text(keyCard, 12, "text")
	keyCard.title:SetPoint("TOPLEFT", keyCard.icon, "TOPRIGHT", 12, -3)
	keyCard.title:SetText(L["QP_BRING_KEY"])
	keyCard.level = Theme.Text(keyCard, 13, "violetText")
	Theme.SetMonoFont(keyCard.level, 13)
	keyCard.level:SetPoint("BOTTOMLEFT", keyCard.icon, "BOTTOMRIGHT", 12, 2)
	keyCard.name = Theme.Text(keyCard, 12, "muted")
	keyCard.name:SetWordWrap(false)
	self.keyCard = keyCard
	self.bringKey = Theme.Switch(keyCard, "", true, function(checked)
		Options().bringKey = checked
		self:Refresh()
	end)
	self.bringKey:SetWidth(30)
	self.bringKey:SetPoint("RIGHT", -12, 0)
	keyCard.name:SetPoint("RIGHT", self.bringKey, "LEFT", -8, 0)
	Explain(keyCard, L["QP_BRING_KEY"], L["QP_BRING_KEY_TIP"])

	-- Queue starten / Gruppe listen / Queue beenden (geschützte Aufrufe: nur aus diesem Klick)
	self.queueButton = Theme.Button(child, L["QP_QUEUE"], "primary", INNER, 44)
	self.queueButton:SetScript("OnClick", function()
		ns.Queue:Toggle()
	end)
	self.queueStatus = Theme.Text(child, 11, "muted")
	self.queueStatus:SetWidth(INNER)
	self.queueStatus:SetSpacing(2)
end

---------------------------------------------------------------------------
-- Letzte Keys: Klick öffnet "Wie war's?" für diesen Run
---------------------------------------------------------------------------

function QueuePanel:CreateRecent(child)
	self.recentTitle = Section(child, L["QP_HISTORY"])
	-- aufklappbar wie Favoriten/Sperrliste (anfangs zu: die Queue steht im Vordergrund)
	self.recentToggle = ToggleRow(child, function()
		self.recentOpen = not self.recentOpen
		self:Refresh()
		if self.recentOpen then
			self:Reveal(self.recentToggle)
		end
	end)
	self.recentOpen = false
	self.recentAll = Theme.Button(child, L["QP_ALL_KEYS"], "ghost", 90, 22)
	Theme.SetFont(self.recentAll.label, 11)
	self.recentAll:SetWidth(self.recentAll.label:GetStringWidth() + 16)
	self.recentAll:SetScript("OnClick", function()
		ns.MainFrame:Open("history")
	end)
	self.recentEmpty = Theme.Text(child, 12, "muted")
	self.recentEmpty:SetText(L["QP_RECENT_EMPTY"])
	self.recentRows = {}
	for index = 1, RECENT_RUNS do
		local row = CreateFrame("Button", nil, child)
		row:SetHeight(40)
		Theme.SetSurface(row, Theme.color.none)
		row.title = Theme.Text(row, 12, "text")
		row.title:SetPoint("TOPLEFT", 4, -6)
		row.title:SetPoint("RIGHT", -70, 0)
		row.title:SetWordWrap(false)
		row.sub = Theme.Text(row, 11, "muted")
		row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
		row.when = Theme.Text(row, 11, "dim")
		row.when:SetPoint("TOPRIGHT", -4, -6)
		row.when:SetJustifyH("RIGHT")
		row:SetScript("OnClick", function()
			ns.FeedbackPopup:Show(row.run)
		end)
		row:SetScript("OnEnter", function()
			Theme.SetSurface(row, Theme.color.cardHover)
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:AddLine(row.title:GetText() or "", 1, 1, 1)
			for _, member in ipairs(row.run and row.run.members or {}) do
				if member.key ~= ns.History:MyKey() then
					local name = Util.RoleIcon(member.role or "DAMAGER", 13) .. " "
						.. Util.ClassName(Ambiguate(member.name or member.key or "?", "none"), member.class)
					if ns.History:IsFavorite(member.key) then
						name = name .. "  " .. Util.FavoriteIcon(12)
					elseif ns.History:IsBlocked(member.key) then
						name = name .. "  " .. Theme.Colorize(L["FB_BLOCK"], "blocked")
					end
					GameTooltip:AddLine(name)
				end
			end
			GameTooltip:AddLine(L["QP_RATE_HINT"], 0.56, 0.69, 1)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function()
			Theme.SetSurface(row, Theme.color.none)
			GameTooltip:Hide()
		end)
		self.recentRows[index] = row
	end
end

---------------------------------------------------------------------------
-- Spieler: Favoriten und Sperrliste (aufklappbar, × entfernt)
---------------------------------------------------------------------------

function QueuePanel:CreatePlayers(child)
	self.playersTitle = Section(child, L["QP_PLAYERS"])
	self.lists = {}
	for _, kind in ipairs({ "favorites", "blacklist" }) do
		local list = { kind = kind, rows = {}, open = false }
		list.toggle = ToggleRow(child, function()
			list.open = not list.open
			self:Refresh()
			if list.open then
				self:Reveal(list.toggle)
			end
		end)
		list.empty = Theme.Text(child, 11, "dim")
		list.empty:SetText(L["QP_LIST_EMPTY"])
		self.lists[kind] = list
		table.insert(self.lists, list)
	end
end

function QueuePanel:ListRow(list, index)
	local row = list.rows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, self.child)
	row:SetHeight(26)
	Theme.Primer(row) -- entsteht beim Anzeigen (nach Größenabfragen): siehe Theme.Primer
	row.name = Theme.Text(row, 12, "text")
	Theme.SetGameFont(row.name, 12)
	row.name:SetPoint("LEFT", 16, 0)
	row.remove = Theme.Button(row, "\195\151", "ghost", 24, 24) -- ×
	row.remove:SetPoint("RIGHT", 0, 0)
	row.remove:SetScript("OnClick", function()
		if list.kind == "favorites" then
			ns.History:SetFavorite(row.key, false)
		else
			ns.History:SetBlocked(row.key, false)
		end
	end)
	list.rows[index] = row
	return row
end

---------------------------------------------------------------------------
-- Anordnen und Stand zeigen
---------------------------------------------------------------------------

function QueuePanel:Refresh()
	local frame = self.frame
	if not frame or not frame:IsShown() then
		return
	end
	local child = self.child
	local inner = INNER
	local y = 14
	local function Place(region, x, height)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", child, "TOPLEFT", PAD + (x or 0), -y)
		region:Show()
		if height then
			y = y + height
		end
	end

	-- Matchmaking: Rollen als Kacheln (nur, was die Klasse spielen kann - wie Blizzards Gruppensuche)
	Place(self.queueTitle, 0, 22)
	local roles = QueueRoles()
	local available = Util.GetAvailableRoles()
	local shown = {}
	for _, chip in ipairs(self.roleChips) do
		chip:SetChecked(roles[chip.role] == true)
		if available[chip.role] then
			table.insert(shown, chip)
		else
			chip:Hide()
		end
	end
	local gap = 8
	local tileWidth = math.floor((inner - gap * (#shown - 1)) / math.max(1, #shown))
	for slot, chip in ipairs(shown) do
		chip:SetWidth(tileWidth)
		Place(chip, (slot - 1) * (tileWidth + gap))
	end
	y = y + 58 + 6

	-- Stufe, normale Gruppen, Mindestwertung: flache Zeilen
	local low, high = Util.ParseLevelRange(Util.GetBlizzardSearchText())
	if low then
		Theme.SetMonoFont(self.levelText, 12)
		self.levelText:SetTextColor(unpack(Theme.color.text))
		self.levelText:SetText(low == high and ("+" .. low) or ("+" .. low .. " - +" .. high))
	else
		Theme.SetFont(self.levelText, 12)
		self.levelText:SetTextColor(unpack(Theme.color.muted))
		self.levelText:SetText(L["QP_LEVEL_UPGRADES"])
	end
	for _, row in ipairs({ self.levelRow, self.normalRow, self.scoreRow }) do
		row:SetWidth(inner)
		Place(row, 0, ROW_HEIGHT)
	end
	self.includeNormal:SetChecked(Options().includeNormal ~= false)
	self.minScore:Sync()
	y = y + 14

	-- Key einbringen
	local key = Util.GetKeystone()
	local card = self.keyCard
	card:SetWidth(inner)
	Place(card, 0, 64 + 12)
	local icon = key and key.texture
	if not icon and C_Item and C_Item.GetItemIconByID then
		icon = C_Item.GetItemIconByID(180653) -- Schlüsselstein
	end
	card.icon:SetTexture(icon or 134400)
	card.icon:SetDesaturated(key == nil)
	card.icon:SetAlpha(key and 1 or 0.5)
	card.name:ClearAllPoints()
	if key then
		card.level:SetText("+" .. (key.level or "?"))
		card.level:Show()
		card.name:SetPoint("LEFT", card.level, "RIGHT", 6, 0)
		card.name:SetText(key.name or "")
	else
		card.level:Hide()
		card.name:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 12, 2)
		card.name:SetText(L["QP_NO_KEY"])
	end
	card.name:SetPoint("RIGHT", self.bringKey, "LEFT", -8, 0)
	self.bringKey:SetChecked(key ~= nil and Options().bringKey)
	self.bringKey:SetEnabled(key ~= nil)
	self.bringKey:SetAlpha(key and 1 or 0.4)

	Place(self.queueButton, 0, 52)
	self.queueButton:SetWidth(inner)
	self:RefreshStatus(true)
	Place(self.queueStatus, 0, math.max(16, math.ceil(self.queueStatus:GetStringHeight() or 14)) + 24)

	-- Verlauf: letzte Keys (dieser Charakter), aufklappbar wie Favoriten/Sperrliste
	Place(self.recentTitle)
	self.recentAll:ClearAllPoints()
	self.recentAll:SetPoint("RIGHT", child, "TOPLEFT", PAD + inner, -(y + 6))
	self.recentAll:Show()
	y = y + 20
	local open = self.recentOpen
	local runs = ns.History:GetRuns(true)
	local toggle = self.recentToggle
	toggle.label:SetText(L["QP_RECENT"]:format(math.min(#runs, RECENT_RUNS)))
	toggle:SetOpen(open)
	toggle:SetWidth(inner)
	toggle.y = y
	Place(toggle, 0, 32)
	self.recentEmpty:SetShown(open and #runs == 0)
	if open and #runs == 0 then
		Place(self.recentEmpty, 6, 24)
	end
	for index, row in ipairs(self.recentRows) do
		local run = open and runs[index]
		row.run = run
		if run then
			local level = (run.level or 0) > 0 and ("+" .. run.level .. " ") or ""
			row.title:SetText(level .. (run.name or "?"))
			local status = run.status == "timed" and Theme.Colorize(L["QP_TIMED"], "ok")
				or (run.status == "depleted" and L["QP_DEPLETED"] or L["QP_RUNNING"])
			local rated = 0
			for _, member in ipairs(run.members or {}) do
				if next(ns.Endorsements:Get(run, member.key)) then
					rated = rated + 1
				end
			end
			row.sub:SetText(status .. (rated > 0 and ("  \194\183  " .. L["QP_RATED"]:format(rated)) or ""))
			row.when:SetText(Ago(run.endedAt or run.startedAt))
			row:SetWidth(inner - 10)
			Place(row, 10, 42)
		else
			row:Hide()
		end
	end
	y = y + 12

	-- Spieler
	Place(self.playersTitle, 0, 20)
	for _, list in ipairs(self.lists) do
		local names = {}
		for name in pairs(KeyQueue.db.global[list.kind]) do
			table.insert(names, name)
		end
		table.sort(names)
		local textKey = list.kind == "favorites" and "QP_FAVORITES" or "QP_BLOCKED"
		list.toggle.label:SetText(L[textKey]:format(#names))
		list.toggle:SetOpen(list.open)
		list.toggle:SetWidth(inner)
		list.toggle.y = y
		Place(list.toggle, 0, 32)
		list.empty:Hide()
		for index, name in ipairs(names) do
			local row = self:ListRow(list, index)
			row.key = name
			row.name:SetText(Ambiguate(name, "none"))
			row:SetWidth(inner)
			if list.open then
				Place(row, 0, 26)
			else
				row:Hide()
			end
		end
		for index = #names + 1, #list.rows do
			list.rows[index]:Hide()
		end
		if list.open and #names == 0 then
			Place(list.empty, 16, 22)
		end
	end
	child:SetHeight(y + PAD)
	self.scroll:UpdateThumb()
end

-- Aufgeklappte Liste ins Bild holen: so weit scrollen, dass die Zeile oben steht (nicht übers Ende hinaus).
-- Im nächsten Bild: dann kennt der Scrollbereich die neue Höhe
function QueuePanel:Reveal(toggle)
	local top = rawget(toggle, "y")
	C_Timer.After(0, function()
		local scroll = self.scroll
		if not (top and scroll and scroll:IsVisible()) then
			return
		end
		local range = scroll:GetVerticalScrollRange() or 0
		local target = math.min(range, math.max(scroll:GetVerticalScroll() or 0, top - 12))
		scroll:SetVerticalScroll(target)
		scroll:UpdateThumb()
	end)
end

-- Queue-Knopf und Statuszeile: was gerade passiert und was als Nächstes kommt.
-- noLayout: nur Text setzen (Refresh ordnet danach selbst an)
function QueuePanel:RefreshStatus(noLayout)
	if not (self.frame and self.frame:IsShown()) then
		return
	end
	local queue, search = ns.Queue, ns.Search
	local button, text = self.queueButton, nil
	local key = Util.GetKeystone()
	if queue:IsListPending() then
		button:SetLabel(L["QP_LIST_NOW"])
		button:SetStyle("primary")
		text = L["QP_STATUS_PENDING"]
	elseif queue:IsLeading() then
		button:SetLabel(L["QP_STOP"])
		button:SetStyle("secondary")
		local applicants = C_LFGList.HasActiveEntryInfo() and #(C_LFGList.GetApplicants() or {}) or 0
		text = L["QP_STATUS_LEAD"]:format(Util.FormatTime(queue:GetElapsed()), math.max(1, GetNumGroupMembers()), applicants)
	elseif queue:IsJoining() then
		button:SetLabel(L["QP_STOP"])
		button:SetStyle("secondary")
		text = L["QP_STATUS_JOIN"]:format(Util.FormatTime(queue:GetElapsed()), search:CountMatches(), search:CountApplications())
	else
		button:SetLabel(L["QP_QUEUE"])
		button:SetStyle("primary")
		local lead = Options().bringKey and queue:CanLead()
		text = lead and L["QP_HINT_LEAD"] or L["QP_HINT_JOIN"]
		if Options().bringKey and key and IsInGroup() and not UnitIsGroupLeader("player") then
			text = L["QP_HINT_NOT_LEADER"]
		end
	end
	button:SetEnabled(not InCombatLockdown())
	local changed = self.queueStatus:GetText() ~= text
	self.queueStatus:SetText(text)
	-- andere Zeilenzahl: Panel neu anordnen
	if changed and not noLayout and self.lastStatusLines ~= math.ceil(self.queueStatus:GetStringHeight() or 0) then
		self.lastStatusLines = math.ceil(self.queueStatus:GetStringHeight() or 0)
		self:Refresh()
	end
end

-- Nur in "Organisierte Gruppen -> Dungeons" selbst: die Dungeon-Suche, das Erstellen oder die eigene
-- gelistete Gruppe (nicht schon in der Kategorie-Auswahl, nicht im Dungeonbrowser, PvP usw.)
local DUNGEONS = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2
function QueuePanel:DungeonsOpen()
	local pve, lfg = _G.PVEFrame, _G.LFGListFrame
	if not (pve and pve:IsShown() and lfg and lfg:IsVisible()) then
		return false
	end
	local active = rawget(lfg, "activePanel")
	if active and active == lfg.SearchPanel then
		-- im alten KeyQueue-Fenster eingebettet zählt nicht
		return lfg.SearchPanel:GetParent() == lfg and lfg.SearchPanel.categoryID == DUNGEONS
	elseif active and active == lfg.EntryCreation then
		return lfg.EntryCreation.selectedCategory == DUNGEONS
	elseif active and active == lfg.ApplicationViewer then
		local info = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
		local activityID = info and Util.Readable(info.activityIDs and info.activityIDs[1] or info.activityID)
		local activity = activityID and C_LFGList.GetActivityInfoTable(activityID)
		return activity ~= nil and activity.categoryID == DUNGEONS
	end
	return false
end

-- Reihe rechts der Gruppensuche: andere Addons docken dort auch an (PGF, dahinter Raider.IOs Profil -
-- so ordnen die beiden sich selbst). KeyQueue reiht sich dahinter ein; geht eins auf/zu oder ändert
-- die Breite, rückt KeyQueue nach. Ein woanders hin verschobenes Fenster zählt nicht mit.
local NEIGHBORS = { "PremadeGroupsFilterDialog", "RaiderIO_ProfileTooltip" }
local GAP, DOCKED = 8, 48

local function ScreenLeft(frame)
	local left = frame:GetLeft()
	return left and left * frame:GetEffectiveScale()
end

local function ScreenRight(frame)
	local right = frame:GetRight()
	return right and right * frame:GetEffectiveScale()
end

-- rechte Kante der Reihe (Bildschirm-Pixel); withSelf: das KeyQueue-Panel mitzählen (für Fenster dahinter)
function QueuePanel:ChainRight(withSelf)
	local pve = _G.PVEFrame
	local right = pve and ScreenRight(pve)
	if not right then
		return nil
	end
	-- Nachbar = sichtbar und beginnt irgendwo zwischen dem linken Rand der Gruppensuche und dem bisherigen
	-- Ende der Reihe (auch überlappend: PGF sitzt je nach Ansicht ein Stück über der Gruppensuche).
	-- Läuft zweimal pro Sekunde: ohne Hilfstabellen (kein Speicher-Abfall)
	local pveLeft = ScreenLeft(pve) or 0
	local function Consider(frame)
		if type(frame) == "table" and frame.IsVisible and frame:IsVisible() then
			local left = ScreenLeft(frame)
			if left and left >= pveLeft and left <= right + DOCKED * frame:GetEffectiveScale() then
				right = math.max(right, ScreenRight(frame) or right)
			end
		end
	end
	for index = 1, #NEIGHBORS do
		Consider(_G[NEIGHBORS[index]])
	end
	if withSelf then
		Consider(rawget(self, "frame"))
	end
	return right
end

-- Fenster oben bündig mit der Gruppensuche hinter die Reihe setzen
function QueuePanel.PlaceInChain(frame, right)
	local pve = _G.PVEFrame
	local pveRight = ScreenRight(pve)
	frame:ClearAllPoints()
	local dx = (right and pveRight) and (right - pveRight) / frame:GetEffectiveScale() or 0
	frame:SetPoint("TOPLEFT", pve, "TOPRIGHT", dx + GAP, 0)
end

-- Nachbarn beobachten (Raider.IOs Profil entsteht erst später): auf/zu/Breite = neu einreihen
local watched = {}
function QueuePanel:WatchNeighbors()
	for _, name in ipairs(NEIGHBORS) do
		local frame = _G[name]
		if type(frame) == "table" and frame.HookScript and not watched[frame] then
			watched[frame] = true
			for _, script in ipairs({ "OnShow", "OnHide", "OnSizeChanged" }) do
				pcall(frame.HookScript, frame, script, function()
					self:Reanchor()
				end)
			end
		end
	end
end

-- neu einreihen (gesammelt im nächsten Bild: Nachbarn melden oft mehrmals hintereinander)
function QueuePanel:Reanchor()
	if rawget(self, "reanchorQueued") then
		return
	end
	self.reanchorQueued = true
	C_Timer.After(0, function()
		self.reanchorQueued = nil
		if self.frame and self.frame:IsShown() then
			self.anchoredRight = self:ChainRight(false)
			QueuePanel.PlaceInChain(self.frame, self.anchoredRight)
		end
		if ns.MatchTest then
			ns.MatchTest:Reanchor()
		end
	end)
end

-- Schließen: bleibt zu, bis "Dungeons" das nächste Mal geöffnet wird
function QueuePanel:Close()
	self.closed = true
	if self.frame then
		self.frame:Hide()
	end
	if ns.MatchTest then
		ns.MatchTest:Reanchor()
	end
end

function QueuePanel:Place()
	local pve = _G.PVEFrame
	if not self:DungeonsOpen() then
		self.closed = nil -- beim nächsten Öffnen wieder da
		if self.frame then
			self.frame:Hide()
		end
		if ns.MatchTest then
			ns.MatchTest:Place()
		end
		return
	end
	self:WatchNeighbors()
	if self.closed then
		if self.frame then
			self.frame:Hide()
		end
	else
		if not self.frame then
			self:Create()
		end
		self.frame:SetHeight(math.max(MIN_HEIGHT, pve:GetHeight() or 0))
		self.frame:Show()
		self.anchoredRight = self:ChainRight(false)
		QueuePanel.PlaceInChain(self.frame, self.anchoredRight)
		self:Refresh()
	end
	if ns.MatchTest then
		ns.MatchTest:Place()
	end
end

-- an Blizzards Gruppensuche hängen (lädt bei Bedarf nach): Fenster auf/zu, Ansicht und Kategorie gewechselt
local function Update()
	QueuePanel:Place()
end
local function Hook()
	local pve = _G.PVEFrame
	if not pve or QueuePanel.hooked then
		return pve ~= nil
	end
	QueuePanel.hooked = true
	pve:HookScript("OnShow", Update)
	pve:HookScript("OnHide", Update)
	local lfg = _G.LFGListFrame
	if lfg then
		lfg:HookScript("OnShow", Update)
		lfg:HookScript("OnHide", Update)
		-- Keystufe kommt aus Blizzards Suchtext: beim Tippen die Stufenzeile nachziehen
		local box = lfg.SearchPanel and lfg.SearchPanel.SearchBox
		if box and box.HookScript then
			box:HookScript("OnTextChanged", function()
				if QueuePanel.frame and QueuePanel.frame:IsShown() then
					QueuePanel:Refresh()
				end
			end)
		end
	end
	for _, name in ipairs({ "LFGListFrame_SetActivePanel", "LFGListSearchPanel_SetCategory",
		"LFGListCategorySelection_SelectCategory", "LFGListEntryCreation_Select" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, Update)
		end
	end
	return true
end

if not Hook() then
	QueuePanel:RegisterEvent("ADDON_LOADED", function()
		if Hook() then
			QueuePanel:UnregisterEvent("ADDON_LOADED")
		end
	end)
end
