-- ProfileCard: Spieler-Profil - M+-Werte (Blizzard, optional Raider.IO), gemeinsame Keys, Notiz,
-- Favorit/Sperren. Öffnet sich per Klick auf einen Namen (History, Bewerberliste, Gruppen-Details).
local _, ns = ...

local L = ns.L
local Theme, Util = ns.Theme, ns.Util

local ProfileCard = {}
ns.ProfileCard = ProfileCard
LibStub("AceEvent-3.0"):Embed(ProfileCard)

local WIDTH, PADDING = 400, 16
local RECENT_RUNS = 5
local SEP = "  \194\183  "

---------------------------------------------------------------------------
-- Gemeinsame Bausteine der Seitenfenster
---------------------------------------------------------------------------

-- Fenster mit Schließen-Knopf (flach wie das Hauptfenster; accentColor wird nicht mehr gezeichnet)
local function CardFrame(width, accentColor, onClose)
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(width, 200)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	Theme.DropShadow(frame)
	Theme.SetSurface(frame, Theme.color.bg, Theme.color.border)
	frame:Hide()

	local close = Theme.Button(frame, "\195\151", "ghost", 28, 28) -- ×
	Theme.SetFont(close.label, 16)
	close:SetPoint("TOPRIGHT", -8, -8)
	close:SetScript("OnClick", function()
		frame:Hide()
		if onClose then
			onClose()
		end
	end)
	frame.close = close
	return frame
end

-- Zeilen untereinander: links Text, rechts optional ein Wert (wie ein Tooltip)
-- entry = { left, right, size, color, rightColor, gap, game (Spielschrift für Namen), bold }
local function RenderRows(card, entries, y)
	card.rows = card.rows or {}
	for index, entry in ipairs(entries) do
		local row = card.rows[index]
		if not row then
			row = { left = Theme.Text(card.frame, 12), right = Theme.Text(card.frame, 12) }
			row.left:SetJustifyH("LEFT")
			row.left:SetWordWrap(false)
			row.right:SetJustifyH("RIGHT")
			row.right:SetWordWrap(false)
			card.rows[index] = row
		end
		local size = entry.size or 12
		if entry.game then
			Theme.SetGameFont(row.left, size)
		else
			Theme.SetFont(row.left, size, entry.bold or size >= 14)
		end
		Theme.SetFont(row.right, size, false)
		row.left:SetTextColor(unpack(Theme.color[entry.color or "text"] or Theme.status[entry.color] or Theme.color.text))
		row.right:SetTextColor(unpack(Theme.color[entry.rightColor or "text"] or Theme.color.text))
		y = y - (entry.gap or 4)
		row.right:ClearAllPoints()
		row.right:SetPoint("TOPRIGHT", -PADDING, y)
		row.right:SetText(entry.right or "")
		row.right:SetShown(entry.right ~= nil)
		row.left:ClearAllPoints()
		row.left:SetPoint("TOPLEFT", PADDING, y)
		if entry.right then
			row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
		else
			row.left:SetPoint("RIGHT", -PADDING, 0)
		end
		row.left:SetText(entry.left or "")
		row.left:Show()
		y = y - (size + 5)
	end
	for index = #entries + 1, #(card.rows or {}) do
		card.rows[index].left:Hide()
		card.rows[index].right:Hide()
	end
	return y
end

-- Kopier-Fenster: Addons dürfen nicht in die Zwischenablage schreiben - der Link steht markiert
-- in einem Feld, Strg+C kopiert ihn, danach schließt sich das Fenster von selbst
local copyPopup
local function ShowCopy(text)
	if not copyPopup then
		local frame = CreateFrame("Frame", nil, UIParent)
		frame:SetSize(460, 96)
		frame:SetPoint("CENTER", 0, 160)
		frame:SetFrameStrata("FULLSCREEN_DIALOG")
		frame:EnableMouse(true)
		Theme.DropShadow(frame)
		Theme.SetSurface(frame, Theme.color.bg, Theme.color.border)
		local hint = Theme.Text(frame, 11, "muted")
		hint:SetPoint("TOPLEFT", 16, -14)
		hint:SetText(L["COPY_HINT"])
		local close = Theme.Button(frame, "\195\151", "ghost", 24, 24) -- ×
		close:SetPoint("TOPRIGHT", -8, -8)
		close:SetScript("OnClick", function()
			frame:Hide()
		end)
		local edit = Theme.EditBox(frame, 428, "")
		edit:SetPoint("TOPLEFT", 16, -40)
		edit:SetMaxLetters(255)
		edit:SetScript("OnEscapePressed", function()
			frame:Hide()
		end)
		edit:SetScript("OnEnterPressed", function()
			frame:Hide()
		end)
		edit:HookScript("OnKeyDown", function(_, key)
			if key == "C" and IsControlKeyDown() then
				C_Timer.After(0.1, function()
					frame:Hide()
				end)
			end
		end)
		-- Text bleibt fest: Tippen setzt ihn zurück und markiert ihn wieder
		edit:HookScript("OnTextChanged", function(box, userInput)
			if userInput then
				box:SetText(frame.text or "")
				box:HighlightText()
			end
		end)
		frame.edit = edit
		copyPopup = frame
	end
	copyPopup.text = text
	copyPopup:Show()
	copyPopup.edit:SetText(text)
	copyPopup.edit:SetFocus()
	copyPopup.edit:HighlightText()
end

-- kleiner Knopf "Raider.IO" links neben dem Schließen-Knopf
local function RaiderIOButton(frame, getKey)
	local button = Theme.Button(frame, "Raider.IO", "secondary", 78, 24)
	Theme.SetFont(button.label, 10, true)
	button:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
	button:SetScript("OnClick", function()
		local key = getKey()
		if key then
			ShowCopy(Util.RaiderIOUrl(key))
		end
	end)
	button:HookScript("OnEnter", function()
		GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["PROFILE_RIO_LINK"], 1, 1, 1)
		GameTooltip:Show()
	end)
	button:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return button
end

local function Entries()
	local list = {}
	local function Add(left, right, size, color, gap, rightColor)
		table.insert(list, { left = left, right = right, size = size, color = color, gap = gap, rightColor = rightColor })
		return list[#list]
	end
	local function Header(key)
		Add(L[key], nil, 11, "dim", 14)
	end
	return list, Add, Header
end

-- Dungeon-Name aus einem Raider.IO-Dungeon (lokalisiert über Blizzard, sonst Raider.IOs Name)
local function RioDungeonName(dungeon)
	local name = dungeon and dungeon.keystone_instance and C_ChallengeMode.GetMapUIInfo(dungeon.keystone_instance)
	return name or (dungeon and (dungeon.shortNameLocale or dungeon.name)) or "?"
end

-- Keystufe wie bei Raider.IO: getimt = je Truhe ein goldenes "+" vor der weißen Stufe, sonst grau
local function LevelText(level, timed, chests)
	if not timed then
		return Theme.Colorize(tostring(level), "muted")
	end
	return "|cffffcf40" .. ("+"):rep(math.max(1, chests or 1)) .. "|r" .. Theme.Colorize(tostring(level), "text")
end

-- Truhen des besten Runs: aus der Liste pro Dungeon (wie Raider.IO selbst) - maxDungeonUpgrades
-- ist nicht in jeder Raider.IO-Version befüllt und zeigte getimte Runs sonst als nicht getimt
local function BestChests(mplus)
	for _, entry in ipairs(mplus.sortedDungeons or {}) do
		if entry.dungeon == mplus.maxDungeon and entry.level == mplus.maxDungeonLevel then
			return entry.chests or 0
		end
	end
	return mplus.maxDungeonUpgrades or 0
end

-- "++18 Nalorakks Bau": Stufe wie oben, Dungeon in der Farbe der Wertung (wie Raider.IO)
local function RunText(level, chests, dungeon, score)
	return LevelText(level, (chests or 0) > 0, chests) .. " " .. Util.ScoreColored(RioDungeonName(dungeon), score)
end

-- Raider.IO-Teil wie Raider.IOs eigener Tooltip (Inhalt und Farben): Wertung (+ Main, Kriegsmeute),
-- bester Run, bester Run im Dungeon der Gruppe, getimte Runs nach Stufen, Raid-Fortschritt.
-- opts.full (Shift bzw. Profil): dazu beste Runs pro Dungeon (Dungeon der Gruppe grün) und alle Raids.
-- Keine Daten doppelt: steht die Wertung bzw. der beste Run schon woanders auf der Karte, lassen
-- skipScore/skipBest sie weg; mit der Liste pro Dungeon (full) entfallen "Bester Run" und "Bester Run hier".
-- Add(left, right, size, color, gap) wie Entries();
-- opts = { full, mapID = Dungeon der Gruppe, key = Name, skipScore, skipBest }
local function AddRaiderIO(Add, Header, mplus, opts)
	opts = opts or {}
	local score = mplus.currentScore or 0
	-- Wertungen mit den gespielten Rollen davor (wie Raider.IO)
	if not opts.skipScore then
		Add(L["PROFILE_SCORE_RIO"], Util.RioScoreText(score, mplus.mplusCurrent))
	end
	if (mplus.mainCurrentScore or 0) > score then
		Add(L["PROFILE_MAIN_SCORE"], Util.RioScoreText(mplus.mainCurrentScore, mplus.mplusMainCurrent))
	end
	if (mplus.warbandCurrentScore or 0) > score then
		Add(L["PROFILE_WARBAND_SCORE"], Util.RioScoreText(mplus.warbandCurrentScore, mplus.mplusWarbandCurrent))
	end
	local here
	for _, entry in ipairs(mplus.sortedDungeons or {}) do
		if opts.mapID and entry.dungeon and entry.dungeon.keystone_instance == opts.mapID then
			here = entry
		end
	end
	local hereIsBest = here and here.dungeon == mplus.maxDungeon
	local bestLines = not opts.full
	if bestLines and not opts.skipBest and (mplus.maxDungeonLevel or 0) > 0 and not hereIsBest then
		Add(L["ME_BEST"], RunText(mplus.maxDungeonLevel, BestChests(mplus), mplus.maxDungeon, score))
	end
	if bestLines and here and (here.level or 0) > 0 then
		-- grün, wenn es zugleich der beste Run überhaupt ist (wie Raider.IO)
		Add(L["RIO_BEST_HERE"], RunText(here.level, here.chests, here.dungeon, score), nil, hereIsBest and "ok" or nil)
	end
	for _, milestone in ipairs(mplus.sortedMilestones or {}) do
		Add(milestone.label, milestone.text)
	end
	if opts.full then
		local first = true
		for _, entry in ipairs(mplus.sortedDungeons or {}) do
			if (entry.level or 0) > 0 then
				if first then
					Header("ME_PER_DUNGEON")
				end
				Add(RioDungeonName(entry.dungeon), LevelText(entry.level, (entry.chests or 0) > 0, entry.chests), nil,
					entry == here and "ok" or nil, first and 6 or nil)
				first = false
			end
		end
	end
	local raids = opts.key and Util.GetRaiderIORaids(opts.key, opts.full) or {}
	if #raids > 0 then
		Header("PROFILE_RAID")
		for _, raid in ipairs(raids) do
			Add(raid.name, raid.text)
		end
	end
end

-- M+-Abschnitte: Wertung, bester Run, getimte Runs nach Stufen, beste Runs pro Dungeon
-- extra = Blizzard-Daten aus der Suche { score, best = { level, name, timed } } (optional)
-- key = Name des Spielers (für den Raid-Fortschritt), brief = ohne Runs pro Dungeon und ältere Raids
-- skip = { score = true, best = true }: steht schon an anderer Stelle der Karte
local function AddMythicPlus(Add, Header, mplus, extra, brief, key, skip)
	if not (mplus or extra) then
		return
	end
	Header("PROFILE_MPLUS")
	if mplus then
		skip = skip or {}
		AddRaiderIO(Add, Header, mplus, { full = not brief, key = key, skipScore = skip.score, skipBest = skip.best })
		return
	end
	-- ohne Raider.IO: Blizzards Werte aus der Suche
	if (extra.score or 0) > 0 then
		Add(L["PROFILE_SCORE_RIO"], Util.ScoreText(extra.score))
	end
	if extra.best then
		Add(L["ME_BEST"], LevelText(extra.best.level, extra.best.timed) .. " "
			.. Util.ScoreColored(extra.best.name or "", extra.score))
	end
end

---------------------------------------------------------------------------
-- Spieler-Profil
---------------------------------------------------------------------------

function ProfileCard:Create()
	local frame = CardFrame(WIDTH, Theme.color.violet)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	self.frame = frame

	self.name = Theme.Text(frame, 18)
	Theme.SetGameFont(self.name, 18) -- Spielernamen: WoW-Schrift kann alle Schriftsysteme
	self.name:SetPoint("TOPLEFT", PADDING, -PADDING)
	self.rioButton = RaiderIOButton(frame, function()
		return self.key
	end)
	self.name:SetPoint("RIGHT", self.rioButton, "LEFT", -8, 0)
	self.name:SetWordWrap(false)

	self.realm = Theme.Text(frame, 11, "muted")
	Theme.SetGameFont(self.realm, 11)
	self.realm:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -4)

	self.state = Theme.Text(frame, 11)
	self.state:SetPoint("LEFT", self.realm, "RIGHT", 10, 0)

	self.noteLabel = Theme.Text(frame, 11, "dim")
	self.noteLabel:SetText(L["PROFILE_NOTE"])
	self.note = Theme.EditBox(frame, WIDTH - 2 * PADDING, L["PROFILE_NOTE_HINT"])
	self.note:SetMaxLetters(120)
	self.note:HookScript("OnTextChanged", function(edit, userInput)
		if userInput and self.key then
			ns.History:SetNote(self.key, edit:GetText())
		end
	end)

	self.favorite = Theme.Button(frame, "", "accent", 180, 32)
	self.favorite:SetScript("OnClick", function()
		ns.History:SetFavorite(self.key, not ns.History:IsFavorite(self.key))
	end)
	self.block = Theme.Button(frame, "", "secondary", 180, 32)
	self.block:SetPoint("LEFT", self.favorite, "RIGHT", 8, 0)
	self.block:SetScript("OnClick", function()
		ns.History:SetBlocked(self.key, not ns.History:IsBlocked(self.key))
	end)

	self:RegisterMessage("KEYQUEUE_PLAYERS_UPDATE", "Refresh")
	self:RegisterMessage("KEYQUEUE_HISTORY_UPDATE", "Refresh")
end

-- key = Name(-Realm) wie in der History; name = Anzeigename; class = Klasse, falls keine Keys bekannt;
-- extra = Blizzard-Daten aus der Suche (Leader): { score, best = { level, name, timed } }
function ProfileCard:Open(key, name, class, extra)
	if not key then
		return
	end
	if not self.frame then
		self:Create()
	end
	if self.frame:IsShown() and self.key == key then
		self.frame:Hide()
		return
	end
	self.key, self.displayName, self.displayClass, self.extra = key, name, class, extra
	self.frame:ClearAllPoints()
	local main = ns.MainFrame and rawget(ns.MainFrame, "frame")
	if main and main:IsShown() then
		self.frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
	else
		self.frame:SetPoint("CENTER")
	end
	self.frame:Show()
	self:Refresh()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

function ProfileCard:Refresh()
	local frame = self.frame
	if not frame or not frame:IsShown() or not self.key then
		return
	end
	local history = ns.History
	local key = self.key
	local profile = history:GetProfile(key)
	local short, realm = key:match("^([^%-]+)%-(.+)$")
	short = short or Ambiguate(self.displayName or key, "short")

	local favorite, blocked = history:IsFavorite(key), history:IsBlocked(key)
	self.name:SetText((favorite and Util.FavoriteIcon(16) .. " " or "") .. Util.ClassName(short, profile.class or self.displayClass))
	self.realm:SetText(realm or GetRealmName() or "")
	if favorite then
		self.state:SetText(Theme.Colorize(L["PROFILE_IS_FAVORITE"], "gold"))
	elseif blocked then
		self.state:SetText(Theme.Colorize(L["PROFILE_IS_BLOCKED"], "blocked"))
	else
		self.state:SetText("")
	end

	local entries, Add, Header = Entries()
	local mplus = Util.GetRaiderIOProfile(key)
	AddMythicPlus(Add, Header, mplus, self.extra, false, key)

	-- gemeinsam mit dir (KeyQueue-History)
	Header("PROFILE_TOGETHER")
	if profile.count == 0 then
		Add(L["PROFILE_NONE"], nil, 12, "muted")
	else
		local summary = L["PROFILE_SUMMARY"]:format(profile.count, profile.timed)
		if profile.left > 0 then
			summary = summary .. SEP .. Theme.Colorize(L["PROFILE_LEAVES"]:format(profile.left), "blocked")
		end
		Add(summary)
		local extra = {}
		if profile.best > 0 then
			table.insert(extra, L["PROFILE_BEST"]:format(profile.best))
		end
		if profile.lastSeen then
			table.insert(extra, L["PROFILE_LAST"]:format(date("%d.%m.", profile.lastSeen)))
		end
		if #extra > 0 then
			Add(table.concat(extra, SEP), nil, 11, "muted")
		end
		local avg = profile.avg
		if avg then
			Add(L["PROFILE_AVG"]:format(Util.ShortNumber(avg.output) .. " " .. avg.outputRole,
				("%.1f"):format(avg.interrupts), ("%.1f"):format(avg.deaths), Util.ShortNumber(avg.avoidable), avg.runs), nil, 11)
		end
		local resultText = ns.HistoryTab.ResultText
		for index = 1, math.min(RECENT_RUNS, #profile.runs) do
			local run = profile.runs[index]
			Add(Theme.Colorize("+" .. (run.level or "?"), "gold") .. "  " .. (run.name or "?") .. SEP .. resultText(run),
				Theme.Colorize(date("%d.%m.", run.startedAt or 0), "muted"), 11, nil, index == 1 and 8 or 4)
		end
	end
	if not mplus and not _G.RaiderIO then
		Add(L["PROFILE_RIO_HINT"], nil, 10, "muted", 12)
	elseif not mplus then
		Add(L["PROFILE_RIO_NO_DATA"], nil, 11, "muted", 12) -- Raider.IO kennt den Spieler (noch) nicht
	end

	local y = RenderRows(self, entries, -PADDING - 46)

	-- Notiz und Knöpfe
	y = y - 14
	self.noteLabel:ClearAllPoints()
	self.noteLabel:SetPoint("TOPLEFT", PADDING, y)
	self.note:ClearAllPoints()
	self.note:SetPoint("TOPLEFT", PADDING, y - 16)
	if not self.note:HasFocus() then
		self.note:SetText(history:GetNote(key))
	end
	y = y - 16 - 28 - 14
	self.favorite:ClearAllPoints()
	self.favorite:SetPoint("TOPLEFT", PADDING, y)
	self.favorite:SetLabel(favorite and L["PROFILE_UNFAVORITE"] or L["PROFILE_FAVORITE"])
	self.block:SetLabel(blocked and L["PROFILE_UNBLOCK"] or L["PROFILE_BLOCK"])
	frame:SetHeight(-y + 32 + PADDING)
end

---------------------------------------------------------------------------
-- RunCard: Details eines Keys als eigenes Fenster rechts neben dem (kompakten) Hauptfenster -
-- oben Key, Ergebnis und Infos, darunter pro Spieler die Werte untereinander
---------------------------------------------------------------------------

local RunCard = {}
ns.RunCard = RunCard

local RUN_WIDTH = 300

function RunCard:Create()
	local frame = CardFrame(RUN_WIDTH, Theme.color.violet)
	frame:HookScript("OnHide", function()
		self.runID = nil
	end)
	self.frame = frame
end

function RunCard:Open(run)
	if not run then
		return
	end
	if not self.frame then
		self:Create()
	end
	if self.frame:IsShown() and self.runID == run.id then
		self.frame:Hide()
		return
	end
	self.runID, self.run = run.id, run
	for _, card in ipairs({ ns.ProfileCard }) do
		local side = card and rawget(card, "frame")
		if side then
			side:Hide()
		end
	end
	self.frame:ClearAllPoints()
	local main = ns.MainFrame and rawget(ns.MainFrame, "frame")
	if main and main:IsShown() then
		self.frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
	else
		self.frame:SetPoint("CENTER")
	end
	self.frame:Show()
	self:Refresh()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

local ROLE_OUTPUT = { HEALER = "HPS" }

function RunCard:Refresh()
	local frame, run = self.frame, self.run
	if not frame or not frame:IsShown() or not run then
		return
	end
	local history = ns.HistoryTab
	local entries, Add = Entries()
	Add(Theme.Colorize("+" .. (run.level or "?"), "gold") .. "  " .. (run.name or "?"), nil, 15, "text", 0).bold = true
	Add(history.ResultText(run) .. SEP .. date("%d.%m. %H:%M", run.startedAt or 0), nil, 12, "muted", 6)
	for _, part in ipairs(history.DetailInfoParts(run)) do
		Add(part, nil, 11, "muted", 3)
	end

	local hasStats = run.stats and next(run.stats.players) ~= nil
	if not hasStats then
		Add(L["HISTORY_NO_STATS"], nil, 11, "muted", 14)
	else
		local players = Util.SortByRole(history.StatPlayers(run))
		local seconds = run.stats.combatTime
		if not seconds or seconds <= 0 then
			seconds = run.duration or 1
		end
		-- Bestwerte der Gruppe (DPS, Kicks, Dispels) hervorheben, meister vermeidbarer Schaden rot
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
			local text = Util.ShortNumber(value)
			if top > 0 and value == top then
				return Theme.Colorize(text, color or "gold")
			end
			return text
		end
		for _, player in ipairs(players) do
			local values = player.values
			local name = Util.ClassName(Ambiguate(player.name or player.key or "?", "short"), player.class)
			if player.key == run.character then
				name = name .. "  " .. Theme.Colorize(L["SEARCH_GROUP_YOU_SHORT"], "violetText")
			end
			Add((player.role and Util.RoleIcon(player.role, 14) .. "  " or "") .. name, nil, 13, "text", 14).game = true
			local outputTop = player.role ~= "HEALER" and best.output or 0
			Add(ROLE_OUTPUT[player.role] or "DPS", Mark(player.output, outputTop), 12, "muted", 4)
			Add(L["HISTORY_COL_INTERRUPTS"], Mark(values.interrupts or 0, best.interrupts), 12, "muted", 2)
			Add(L["HISTORY_COL_DISPELS"], Mark(values.dispels or 0, best.dispels), 12, "muted", 2)
			Add(L["HISTORY_COL_AVOIDABLE"], Mark(values.avoidable or 0, best.avoidable, "blocked"), 12, "muted", 2)
			local deaths = values.deaths or 0
			Add(L["HISTORY_COL_DEATHS"], deaths > 0 and Theme.Colorize(deaths, "blocked") or "0", 12, "muted", 2)
		end
	end
	local y = RenderRows(self, entries, -PADDING)
	frame:SetHeight(-y + PADDING)
end
