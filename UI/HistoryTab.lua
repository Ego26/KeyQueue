-- HistoryTab: Tab "History" - alle Keys mit Ergebnis, Gruppe und Leavern
local _, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Theme, Util = ns.Theme, ns.Util

local HistoryTab = {}
ns.HistoryTab = HistoryTab
LibStub("AceEvent-3.0"):Embed(HistoryTab)

local ROW_HEIGHT, ROW_GAP = 112, 0
-- kompakt: Spieler nur als runde Symbole eng nebeneinander unter dem Text, Zeile entsprechend niedriger
local COMPACT_ROW_HEIGHT = 92
local COMPACT_CHIP, COMPACT_CHIP_GAP, COMPACT_CHIP_TOP = 28, 4, 54
local CARD_HEIGHT, CARD_GAP = 38, 6
local MAX_ROWS = 100
local NO_ICON = 134400

function HistoryTab:Create(page)
	self.page = page

	-- Zusammenfassung
	local summary = Theme.Card(page)
	summary:SetPoint("TOPLEFT")
	summary:SetPoint("TOPRIGHT")
	summary:SetHeight(56)
	self.summaryCard = summary

	self.summaryText = Theme.Text(summary, 15)
	self.summaryText:SetPoint("LEFT", 2, 0)
	-- Tooltip erklärt die Kennzahlen
	local summaryHit = CreateFrame("Frame", nil, summary)
	summaryHit:SetAllPoints(self.summaryText)
	summaryHit:EnableMouse(true)
	summaryHit:SetScript("OnEnter", function()
		GameTooltip:SetOwner(summaryHit, "ANCHOR_BOTTOMLEFT", 0, 0)
		GameTooltip:AddLine(L["HISTORY_SUMMARY_TIP"], 1, 1, 1, true)
		GameTooltip:AddLine(" ")
		for _, key in ipairs({ "HISTORY_SUMMARY_TIP_TIMED", "HISTORY_SUMMARY_TIP_LEVEL", "HISTORY_SUMMARY_TIP_LEAVER" }) do
			GameTooltip:AddLine(L[key], 0.8, 0.8, 0.85, true)
		end
		GameTooltip:Show()
	end)
	summaryHit:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	self.showAll = Theme.Chip(summary, L["HISTORY_ALL_CHARACTERS"], false, function(checked)
		KeyQueue.db.global.historyShowAll = checked
		self:Refresh()
	end)
	self.showAll:SetPoint("RIGHT", 0, 0)

	-- Liste
	local card = Theme.Card(page)
	card:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, 0)
	card:SetPoint("BOTTOMRIGHT")
	card.rule:Hide()

	self.empty = Theme.Text(card, 12, "muted")
	self.empty:SetPoint("LEFT", 24, 0)
	self.empty:SetPoint("RIGHT", -24, 0)
	self.empty:SetJustifyH("CENTER")
	self.empty:SetWordWrap(true)
	self.empty:SetText(L["HISTORY_EMPTY"])

	local scroll, child = Theme.ScrollArea(card, ROW_HEIGHT + ROW_GAP)
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", 0, 0)
	self.child = child
	self.rows = {}
	self.expanded = {} -- [run.id] = true

	page:SetScript("OnShow", function()
		self:Refresh()
	end)
	self:RegisterMessage("KEYQUEUE_HISTORY_UPDATE", "OnUpdateMessage")
end

function HistoryTab:OnUpdateMessage()
	if self.page:IsVisible() then
		self:Refresh()
	end
end

function HistoryTab:GetRow(index)
	local row = self.rows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, self.child)
	-- flach mit feiner Linie; Überfahren hinterlegt leicht
	Theme.SetSurface(row, Theme.color.none)
	Theme.Rule(row)

	-- Klick auf den Run klappt die Details auf
	row:EnableMouse(true)
	row:SetScript("OnEnter", function()
		Theme.SetSurface(row, Theme.color.cardHover)
	end)
	row:SetScript("OnLeave", function()
		Theme.SetSurface(row, Theme.color.none)
	end)
	row:SetScript("OnMouseUp", function(_, button)
		-- kompakt: Details als eigenes Fenster rechts daneben (untereinander statt Tabelle)
		if button == "LeftButton" and row.run and self.compact then
			ns.RunCard:Open(row.run)
			return
		end
		if button == "LeftButton" and row.run then
			self.expanded[row.run.id] = not self.expanded[row.run.id] or nil
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			self:Refresh()
		end
	end)

	row.more = Theme.Text(row, 11, "violetText")
	row.more:SetPoint("TOPRIGHT", -14, -16) -- oben rechts: unten haben alle Spieler-Chips Platz

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(Theme.PixelSize(row, 44), Theme.PixelSize(row, 44))
	row.icon:SetPoint("TOPLEFT", Theme.PixelSize(row, 12), -Theme.PixelSize(row, 12))
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- abgerundete Ecken wie die Spec-Symbole in der Suche
	local mask = row:CreateMaskTexture()
	mask:SetTexture(Theme.media.rounded, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "TRILINEAR")
	mask:SetAllPoints(row.icon)
	row.icon:AddMaskTexture(mask)

	row.title = Theme.Text(row, 14)
	row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 12, 2)

	row.result = Theme.Text(row, 13)
	row.result:SetPoint("LEFT", row.title, "RIGHT", 10, 0)

	row.badge = Theme.Badge(row, "KQ", "gold")
	row.badge:SetPoint("LEFT", row.result, "RIGHT", 8, 0)

	row.details = Theme.Text(row, 12, "muted")
	row.details:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -5)

	-- Mitspieler als eigene Cards; der Text erscheint nur, wenn keine Gruppe bekannt ist
	row.cards = {}
	row.members = Theme.Text(row, 11, "muted")
	row.members:SetText(L["HISTORY_NO_MEMBERS"])

	row.block = Theme.Button(row, L["HISTORY_BLOCK_LEAVERS"], "secondary", 130, 24)
	row.block:SetPoint("RIGHT", row.more, "LEFT", -12, 0)
	Theme.SetFont(row.block.label, 11, true)

	self.rows[index] = row
	return row
end

local function ResultText(run)
	if run.status == "timed" then
		return Theme.Colorize(L["HISTORY_TIMED"]:format(math.max(1, run.upgrade or 1)), "ok")
	elseif run.status == "depleted" then
		return Theme.Colorize(L["HISTORY_DEPLETED"], "blocked")
	elseif run.status == "abandoned" then
		return Theme.Colorize(L["HISTORY_ABANDONED"], "muted")
	end
	return Theme.Colorize(L["HISTORY_RUNNING"], "violetText")
end
HistoryTab.ResultText = ResultText -- auch für die Profil-Card

local function DetailsText(run)
	local parts = { date("%d.%m. %H:%M", run.startedAt or 0) }
	if run.duration then
		local limit = run.timeLimit and (" / " .. Util.FormatTime(run.timeLimit)) or ""
		table.insert(parts, Util.FormatTime(run.duration) .. limit)
	end
	if run.status ~= "running" or (run.deaths or 0) > 0 then
		table.insert(parts, L["HISTORY_DEATHS"]:format(run.deaths or 0))
	end
	if run.scoreAfter and run.scoreBefore then
		local delta = run.scoreAfter - run.scoreBefore
		local deltaText = delta > 0 and Theme.Colorize(("+%d"):format(delta), "ok") or ""
		table.insert(parts, L["HISTORY_SCORE"]:format(math.floor(run.scoreBefore), math.floor(run.scoreAfter)) .. " " .. deltaText)
	end
	return table.concat(parts, "  \194\183  ")
end

-- "Name-Realm" (Schlüssel) in Name und Realm zerlegen; ohne Realm = eigener Realm
local function SplitKey(key, fallback)
	local name, realm = (key or ""):match("^([^%-]+)%-(.+)$")
	return name or Ambiguate(fallback or "?", "short"), realm or GetRealmName() or ""
end

-- Spieler-Chip: Avatar (Klassenfarbe mit Rollen-Symbol), Name in
-- Klassenfarbe, darunter der Realm. Größen und Abstände auf ganze Bildschirmpixel.
local ROLE_GLYPH = { TANK = Theme.media.roleTank, HEALER = Theme.media.roleHealer, DAMAGER = Theme.media.roleDps }
local AVATAR = 22 -- wie die Symbole in der Suche (vorher 28: wirkte zu groß)

function HistoryTab:GetMemberCard(row, index)
	local card = row.cards[index]
	if card then
		return card
	end
	card = CreateFrame("Frame", nil, row)
	card:SetHeight(Theme.PixelSize(row, CARD_HEIGHT))
	-- Klick öffnet das Spieler-Profil; Überfahren hellt die Fläche auf
	card:EnableMouse(true)
	card:SetScript("OnEnter", function()
		Theme.SetSurface(card, Theme.color.surfaceHover, rawget(card, "outline"))
		-- kompakt (nur Kachel): Name und Realm im Tooltip
		if self.compact and rawget(card, "tipName") then
			GameTooltip:SetOwner(card, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(card.tipName, 1, 1, 1)
			GameTooltip:AddLine(card.tipRealm or "", 0.6, 0.6, 0.65)
			GameTooltip:Show()
		end
	end)
	card:SetScript("OnLeave", function()
		Theme.SetSurface(card, rawget(card, "fill") or Theme.color.surface, rawget(card, "outline"))
		GameTooltip:Hide()
	end)
	card:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" and card.key then
			ns.ProfileCard:Open(card.key, card.key)
		end
	end)

	local inset = Theme.PixelSize(row, (CARD_HEIGHT - AVATAR) / 2)
	local avatarSize = Theme.PixelSize(row, AVATAR)
	card.avatar = CreateFrame("Frame", nil, card)
	card.avatar:SetSize(avatarSize, avatarSize)
	card.avatar:SetPoint("TOPLEFT", inset, -inset)
	card.avatarSize = avatarSize
	-- rund wie in der Gruppenliste: Ring (eigener Charakter/Leaver), Kreis in Klassenfarbe
	card.ring = card.avatar:CreateTexture(nil, "BACKGROUND")
	card.ring:SetPoint("CENTER")
	card.ring:SetSize(avatarSize + Theme.Pixels(row, 4), avatarSize + Theme.Pixels(row, 4))
	card.ring:SetTexture(Theme.media.circle, nil, nil, "TRILINEAR")
	card.ring:Hide()
	-- dunkler Rand wie in der Suche (PGF-Look)
	local rim = Theme.Pixels(row, 1.5)
	card.rim = card.avatar:CreateTexture(nil, "BORDER")
	card.rim:SetPoint("TOPLEFT", -rim, rim)
	card.rim:SetPoint("BOTTOMRIGHT", rim, -rim)
	card.rim:SetTexture(Theme.media.circle, nil, nil, "TRILINEAR")
	card.rim:SetVertexColor(0, 0, 0, 0.85)
	card.avatarBg = card.avatar:CreateTexture(nil, "ARTWORK")
	card.avatarBg:SetAllPoints()
	card.avatarBg:SetTexture(Theme.media.circle, nil, nil, "TRILINEAR")
	card.spec = card.avatar:CreateTexture(nil, "ARTWORK", nil, 1)
	card.spec:SetAllPoints()
	Theme.MakeRound(card.spec)
	card.glyph = card.avatar:CreateTexture(nil, "OVERLAY")
	card.glyph:SetSize(avatarSize * 0.72, avatarSize * 0.72)
	card.glyph:SetPoint("CENTER")

	card.name = Theme.Text(card, 13)
	Theme.SetGameFont(card.name, 13) -- Spielernamen: WoW-Schrift kann alle Schriftsysteme
	card.name:SetWordWrap(false)
	card.name:SetPoint("TOPLEFT", card.avatar, "TOPRIGHT", 8, 0)
	card.realm = Theme.Text(card, 11, "dim")
	Theme.SetGameFont(card.realm, 11)
	card.realm:SetWordWrap(false)
	card.realm:SetPoint("BOTTOMLEFT", card.avatar, "BOTTOMRIGHT", 8, 0)
	row.cards[index] = card
	return card
end

-- mine = eigener Charakter (immer vorne): leicht in der Akzentfarbe hinterlegt; left = Leaver (roter Rand)
function HistoryTab:SetMemberCard(card, key, fallbackName, class, role, left, mine, specID)
	local name, realm = SplitKey(key, fallbackName)
	card.key = key
	-- Avatar: groß links in der Kachel, kompakt mittig im kleinen Feld
	card.avatar:ClearAllPoints()
	if self.compact then
		card.avatar:SetPoint("CENTER")
	else
		local inset = Theme.PixelSize(card, (CARD_HEIGHT - AVATAR) / 2)
		card.avatar:SetPoint("TOPLEFT", inset, -inset)
	end

	-- Avatar einheitlich für alle: Kachel in Klassenfarbe mit weißem Rollen-Symbol (Specs sind nicht
	-- bei jedem Mitspieler bekannt - gemischt mit Spec-Symbolen wirkte das unruhig)
	local color = class and C_ClassColor and C_ClassColor.GetClassColor(class)
	if color and not color.r then
		color = nil
	end
	card.spec:Hide()
	Util.SetRoleGlyph(card.glyph, role, ROLE_GLYPH[role] or ROLE_GLYPH.DAMAGER)
	card.glyph:Show()
	if color then
		card.avatarBg:SetVertexColor(color.r, color.g, color.b, 1)
	else
		card.avatarBg:SetVertexColor(unpack(Theme.color.surfaceHover))
	end

	local nameText = Util.ClassName(name, class)
	if ns.History:IsFavorite(key) then
		nameText = Util.FavoriteIcon(12) .. " " .. nameText
	end
	card.name:SetText(nameText)
	card.tipName, card.tipRealm = nameText, realm
	card.name:SetShown(not self.compact)
	card.realm:SetShown(not self.compact)
	-- Leaver: rot statt Realm (die Breite ist fest, angehängt würde es abgeschnitten)
	card.realm:SetText(left and Theme.Colorize(L["HISTORY_LEAVER"], "blocked") or realm)
	-- feste Breite (setzt RefreshMembers für das Raster); Text wird bei Bedarf mit "..." gekürzt
	local textLeft = card.avatarSize + Theme.PixelSize(card, (CARD_HEIGHT - AVATAR) / 2) + 8
	card.name:SetWidth(math.max(10, card:GetWidth() - textLeft - 8))
	card.realm:SetWidth(math.max(10, card:GetWidth() - textLeft - 8))

	local fill = mine and Theme.color.violetSoft or Theme.color.surface
	local outline = left and Theme.status.blocked or (mine and Theme.color.activeBorder) or nil
	-- kompakt: nur der runde Avatar ohne Kasten; Ring markiert dich (Akzent) bzw. Leaver (rot)
	if self.compact then
		fill, outline = Theme.color.none, nil
		local ringColor = left and Theme.status.blocked or (mine and Theme.color.violet) or nil
		card.ring:SetShown(ringColor ~= nil)
		if ringColor then
			card.ring:SetVertexColor(unpack(ringColor))
		end
	else
		card.ring:Hide()
	end
	card.fill, card.outline = fill, outline
	Theme.SetSurface(card, fill, outline)
	card:Show()
end

function HistoryTab:RefreshMembers(row, run, showMine)
	local index, previous = 0, nil
	-- festes Raster: 5 gleich breite Spalten mit gleichem Abstand, bündig unter dem Dungeon-Titel,
	-- alles auf ganzen Bildschirmpixeln - so stehen die Chips in jeder Zeile genau untereinander
	local left = Theme.PixelSize(row, 68)
	local gap = Theme.PixelSize(row, CARD_GAP)
	local width = ns.MainFrame:PageWidth() - 12 -- Zeilen sind 12 px schmaler (Scrollleiste)
	local chipWidth = Theme.PixelSize(row, (width - 68 - 14 - 4 * CARD_GAP) / 5)
	local chipHeight, top = Theme.PixelSize(row, CARD_HEIGHT), Theme.PixelSize(row, 60)
	if self.compact then
		-- nur das runde Symbol (Name im Tooltip), eng nebeneinander
		chipWidth = Theme.PixelSize(row, COMPACT_CHIP)
		chipHeight = chipWidth
		gap = Theme.PixelSize(row, COMPACT_CHIP_GAP)
		top = Theme.PixelSize(row, COMPACT_CHIP_TOP)
	end
	local function Place(card, column)
		card:ClearAllPoints()
		card:SetSize(chipWidth, chipHeight)
		card:SetPoint("TOPLEFT", row, "TOPLEFT", left + column * (chipWidth + gap), -top)
		previous = card
	end

	-- Reihenfolge immer Tank, Heiler, DPS (der eigene Charakter wird mit einsortiert, bleibt markiert)
	local people = {}
	if showMine then
		table.insert(people, { key = run.character, name = run.character, class = ns.History:CharacterClass(run),
			role = run.characterRole, mine = true, specID = run.characterSpec })
	end
	for _, member in ipairs(run.members) do
		table.insert(people, member)
	end
	Util.SortByRole(people)
	for _, person in ipairs(people) do
		index = index + 1
		local card = self:GetMemberCard(row, index)
		Place(card, index - 1)
		self:SetMemberCard(card, person.key, person.name, person.class, person.role, person.left, person.mine and true or false,
			person.specID)
	end
	for extra = index + 1, #row.cards do
		row.cards[extra]:Hide()
	end
	row.members:SetShown(#run.members == 0)
	if #run.members == 0 then
		row.members:ClearAllPoints()
		if previous then
			row.members:SetPoint("LEFT", previous, "RIGHT", 14, 0)
		else
			row.members:SetPoint("TOPLEFT", row.details, "BOTTOMLEFT", 0, -16)
		end
	end
end

---------------------------------------------------------------------------
-- Details eines Runs: Affixe, Zeitpuffer, Rekorde, Werte pro Spieler (Blizzard-Damage-Meter)
---------------------------------------------------------------------------

local DETAIL_LINE = 20
-- Spalten der Spieler-Tabelle: x-Position, Überschrift
local COLUMNS = {
	{ x = 10, key = "HISTORY_COL_PLAYER" },
	{ x = 210, key = "HISTORY_COL_OUTPUT" },
	{ x = 320, key = "HISTORY_COL_INTERRUPTS" },
	{ x = 400, key = "HISTORY_COL_DISPELS" },
	{ x = 480, key = "HISTORY_COL_AVOIDABLE" },
	{ x = 620, key = "HISTORY_COL_DEATHS" },
}
-- kompaktes Fenster: dieselben Spalten enger gesetzt
local COMPACT_COLUMNS = {
	{ x = 10, width = 96 }, { x = 112 }, { x = 186 }, { x = 226 }, { x = 272 }, { x = 342 },
}

local ShortNumber = Util.ShortNumber

local function AffixNames(run)
	local names = {}
	for _, affixID in ipairs(run.affixes or {}) do
		local name = C_ChallengeMode.GetAffixInfo(affixID)
		if name and not Util.IsSecret(name) then
			table.insert(names, name)
		end
	end
	return table.concat(names, ", ")
end

local function DetailInfoParts(run)
	local parts = {}
	if run.affixes and #run.affixes > 0 then
		table.insert(parts, L["HISTORY_AFFIXES"]:format(AffixNames(run)))
	end
	if run.duration and run.timeLimit then
		local diff = run.timeLimit - run.duration
		if diff >= 0 then
			table.insert(parts, Theme.Colorize(L["HISTORY_BUFFER"]:format(Util.FormatTime(diff)), "ok"))
		else
			table.insert(parts, Theme.Colorize(L["HISTORY_OVERTIME"]:format(Util.FormatTime(-diff)), "blocked"))
		end
	end
	if (run.timeLost or 0) > 0 then
		table.insert(parts, L["HISTORY_TIME_LOST"]:format(Util.FormatTime(run.timeLost)))
	end
	if run.mapRecord then
		table.insert(parts, Theme.Colorize(L["HISTORY_RECORD_MAP"], "gold"))
	elseif run.affixRecord then
		table.insert(parts, Theme.Colorize(L["HISTORY_RECORD_AFFIX"], "gold"))
	end
	return parts
end
HistoryTab.DetailInfoParts = DetailInfoParts -- auch für das Run-Fenster (kompakt)

local function DetailInfoText(run)
	return table.concat(DetailInfoParts(run), "  \194\183  ")
end

function HistoryTab:GetDetail(row)
	local existing = rawget(row, "statsPanel")
	if existing then
		return existing
	end
	local detail = CreateFrame("Frame", nil, row)
	detail:SetPoint("TOPLEFT", 10, -(ROW_HEIGHT - 2))
	detail:SetPoint("RIGHT", -10, 0)
	Theme.SetSurface(detail, Theme.color.surface)

	detail.info = Theme.Text(detail, 11, "muted")
	detail.info:SetPoint("TOPLEFT", 10, -10)
	detail.info:SetPoint("RIGHT", -10, 0)
	detail.info:SetJustifyH("LEFT")
	detail.info:SetWordWrap(false)

	detail.empty = Theme.Text(detail, 11, "muted")
	detail.empty:SetPoint("TOPLEFT", detail.info, "BOTTOMLEFT", 0, -10)
	detail.empty:SetText(L["HISTORY_NO_STATS"])

	detail.header = {}
	for index, column in ipairs(COLUMNS) do
		local text = Theme.Text(detail, 11, "dim")
		text:SetPoint("TOPLEFT", column.x, -34)
		text:SetText(L[column.key])
		detail.header[index] = text
	end
	detail.lines = {}
	row.statsPanel = detail
	return detail
end

function HistoryTab:GetDetailLine(detail, index)
	local line = detail.lines[index]
	if line then
		return line
	end
	line = {}
	for column in ipairs(COLUMNS) do
		local text = Theme.Text(detail, column == 1 and 12 or 11)
		if column == 1 then
			Theme.SetGameFont(text, 12)
			text:SetWordWrap(false)
		end
		line[column] = text
	end
	detail.lines[index] = line
	return line
end

-- Spieler der Tabelle: ich zuerst, dann die Mitspieler (nur wer Werte hat)
local function StatPlayers(run)
	local players = {}
	local mine = run.stats.players[run.character]
	if mine then
		table.insert(players, { key = run.character, class = ns.History:CharacterClass(run) or mine.class,
			role = run.characterRole, values = mine })
	end
	for _, member in ipairs(run.members) do
		local values = member.key and run.stats.players[member.key]
		if values then
			table.insert(players, { key = member.key, name = member.name, class = member.class or values.class,
				role = member.role, values = values, left = member.left })
		end
	end
	return players
end

-- Höhe der Detail-Ansicht
HistoryTab.StatPlayers = StatPlayers

function HistoryTab:RefreshDetail(row, run)
	local detail = self:GetDetail(row)
	local info = DetailInfoText(run)
	detail.info:SetText(info)
	-- kompakt darf die Infozeile umbrechen; Tabelle beginnt darunter
	detail.info:SetWordWrap(self.compact and true or false)
	local infoHeight = info ~= "" and math.max(14, math.ceil(detail.info:GetStringHeight() or 14)) or 0
	local top = info ~= "" and (10 + infoHeight + 10) or 10
	local columns = self.compact and COMPACT_COLUMNS or COLUMNS
	for index, text in ipairs(detail.header) do
		text:ClearAllPoints()
		text:SetPoint("TOPLEFT", columns[index].x, -top)
	end
	-- ohne Infozeile (z. B. abgebrochen) rückt der Hinweis nach oben
	detail.empty:ClearAllPoints()
	if info == "" then
		detail.empty:SetPoint("TOPLEFT", 10, -10)
	else
		detail.empty:SetPoint("TOPLEFT", detail.info, "BOTTOMLEFT", 0, -10)
	end
	local hasStats = run.stats and next(run.stats.players) ~= nil
	detail.empty:SetShown(not hasStats)
	for _, text in ipairs(detail.header) do
		text:SetShown(hasStats)
	end

	local players = hasStats and StatPlayers(run) or {}
	local seconds = run.stats and run.stats.combatTime
	if not seconds or seconds <= 0 then
		seconds = run.duration or 1
	end
	-- Beste Werte hervorheben: meiste DPS/HPS, Kicks, Dispels; meister vermeidbarer Schaden in Rot
	local best = { output = 0, interrupts = 0, dispels = 0, avoidable = 0 }
	for _, player in ipairs(players) do
		local values = player.values
		player.output = ns.History.OutputPerSecond(values, player.role == "HEALER", seconds)
		best.output = math.max(best.output, player.role == "HEALER" and 0 or player.output)
		best.interrupts = math.max(best.interrupts, values.interrupts or 0)
		best.dispels = math.max(best.dispels, values.dispels or 0)
		best.avoidable = math.max(best.avoidable, values.avoidable or 0)
	end
	local function Mark(value, top, color)
		local text = type(value) == "number" and ShortNumber(value) or value
		if top > 0 and value == top then
			return Theme.Colorize(text, color or "gold")
		end
		return text
	end

	for index, player in ipairs(players) do
		local line = self:GetDetailLine(detail, index)
		for column, text in ipairs(line) do
			text:ClearAllPoints()
			text:SetPoint("TOPLEFT", columns[column].x, -(top + 16) - (index - 1) * DETAIL_LINE)
		end
		line[1]:SetWidth(columns[1].width or 190)
		local values = player.values
		local name = Util.ClassName(Ambiguate(player.name or player.key or "?", "short"), player.class)
		line[1]:SetText((player.role and Util.RoleIcon(player.role, 14) .. "  " or "") .. name)
		local output = ShortNumber(player.output)
		if player.role ~= "HEALER" and player.output == best.output and best.output > 0 then
			output = Theme.Colorize(output, "gold")
		end
		line[2]:SetText(output .. Theme.Colorize(player.role == "HEALER" and " HPS" or " DPS", "muted"))
		line[3]:SetText(Mark(values.interrupts or 0, best.interrupts))
		line[4]:SetText(Mark(values.dispels or 0, best.dispels))
		line[5]:SetText(Mark(values.avoidable or 0, best.avoidable, "blocked"))
		local deaths = values.deaths or 0
		line[6]:SetText(deaths > 0 and Theme.Colorize(deaths, "blocked") or "0")
		for _, text in ipairs(line) do
			text:Show()
		end
	end
	for index = #players + 1, #detail.lines do
		for _, text in ipairs(detail.lines[index]) do
			text:Hide()
		end
	end

	local height = hasStats and (top + 16 + #players * DETAIL_LINE + 6) or (info == "" and 34 or top + 24)
	detail:SetHeight(height)
	detail:Show()
	return height + 10
end

-- Fenster kompakt/groß: Zusammenfassung zweizeilig, Spieler nur als Kacheln (Name im Tooltip)
function HistoryTab:SetCompact(compact)
	self.compact = compact
	self.summaryCard:SetHeight(compact and 84 or 56)
	self.summaryText:ClearAllPoints()
	self.showAll:ClearAllPoints()
	if compact then
		Theme.SetFont(self.summaryText, 13, true)
		self.summaryText:SetPoint("TOPLEFT", 2, -14)
		self.showAll:SetPoint("TOPLEFT", 0, -42)
	else
		Theme.SetFont(self.summaryText, 15, true)
		self.summaryText:SetPoint("LEFT", 2, 0)
		self.showAll:SetPoint("RIGHT", 0, 0)
	end
	if self.page:IsVisible() then
		self:Refresh()
	end
end

function HistoryTab:Refresh()
	if not self.page then
		return
	end
	local onlyMe = not KeyQueue.db.global.historyShowAll
	self.showAll:SetChecked(not onlyMe)

	local runs = ns.History:GetRuns(onlyMe)
	local summary = ns.History:GetSummary(runs)
	self.summaryText:SetText(L["HISTORY_SUMMARY"]:format(summary.count, summary.timedPercent,
		("%.1f"):format(summary.averageLevel), summary.leavers))
	self.empty:SetShown(#runs == 0)

	local count = math.min(#runs, MAX_ROWS)
	local y = 0
	for index = 1, count do
		local run = runs[index]
		local row = self:GetRow(index)
		row.run = run
		local height = self.compact and COMPACT_ROW_HEIGHT or ROW_HEIGHT
		row.more:SetShown(not self.compact) -- kompakt öffnet ein Klick auf den Key das Run-Fenster
		if self.expanded[run.id] and not self.compact then
			height = height + self:RefreshDetail(row, run)
			row.more:SetText(L["HISTORY_DETAILS_LESS"])
		else
			local panel = rawget(row, "statsPanel")
			if panel then
				panel:Hide()
			end
			row.more:SetText(L["HISTORY_DETAILS_MORE"])
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", self.child, "RIGHT", 0, 0)
		row:SetHeight(height)
		y = y + height + ROW_GAP
		row.icon:SetTexture(run.texture or NO_ICON)
		row.title:SetText(Theme.Colorize("+" .. (run.level or "?"), "gold") .. "  " .. (run.name or "?"))
		row.result:SetText(ResultText(run))
		row.badge:SetShown(run.viaKeyQueue and true or false)
		row.details:SetText(DetailsText(run))
		self:RefreshMembers(row, run, true) -- eigener Charakter immer vorne (auch ohne "Alle Charaktere")
		row.block:SetShown(not self.compact and ns.History:HasUnblockedLeaver(run))
		row.details:SetWidth(math.max(100, ns.MainFrame:PageWidth() - 80))
		row.details:SetWordWrap(false)
		row.block:SetScript("OnClick", function()
			ns.History:BlockLeavers(run)
			KeyQueue:Msg(L["HISTORY_BLOCKED"])
		end)
		row:Show()
	end
	for index = count + 1, #self.rows do
		self.rows[index]:Hide()
	end
	self.child:SetHeight(math.max(1, y))
end
