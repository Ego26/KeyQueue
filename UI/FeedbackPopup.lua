-- "Wie war's?" nach jedem Key: pro Mitspieler Lob (Guter Mitspieler, Starke Rolle, Sauber gekickt),
-- Favorit oder "Nie wieder". Lob teilt KeyQueue später mit der Matchmaking-Community, "Nie wieder" bleibt
-- privat (Sperrliste: mit dem Spieler wird man nicht mehr gematcht). Freiwillig: Fertig/Esc schließt.
-- Auch aus dem Panel heraus für ältere Runs aufrufbar (FeedbackPopup:Show(run)).
local ADDON_NAME, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Theme, Util = ns.Theme, ns.Util

local FeedbackPopup = {}
ns.FeedbackPopup = FeedbackPopup
LibStub("AceEvent-3.0"):Embed(FeedbackPopup)

local WIDTH, PAD, ROW = 600, 18, 64
local SHOW_DELAY = 4 -- Sekunden nach dem Key (Endbildschirm, Truhe)

local ROLE_TAG = { TANK = "FB_TAG_ROLE_TANK", HEALER = "FB_TAG_ROLE_HEALER", DAMAGER = "FB_TAG_ROLE_DAMAGER" }

local function TagLabel(tag, member)
	if tag == "ROLE" then
		return L[ROLE_TAG[member.role or "DAMAGER"] or "FB_TAG_ROLE_DAMAGER"]
	end
	return L["FB_TAG_" .. tag]
end

local function StatusText(run)
	if run.status == "timed" then
		return Theme.Colorize(L["QP_TIMED"], "ok")
	elseif run.status == "depleted" then
		return Theme.Colorize(L["QP_DEPLETED"], "muted")
	end
	return Theme.Colorize(L["QP_RUNNING"], "muted")
end

function FeedbackPopup:Create()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetWidth(WIDTH)
	frame:SetPoint("CENTER", 0, 120)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	Theme.DropShadow(frame)
	Theme.SetSurface(frame, Theme.color.bg, Theme.color.border)
	frame:Hide()
	self.frame = frame

	self.title = Theme.Text(frame, 18, "text")
	self.title:SetPoint("TOPLEFT", PAD, -PAD)
	self.title:SetText(L["FB_TITLE"])
	self.subtitle = Theme.Text(frame, 12, "muted")
	self.subtitle:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -6)
	local close = Theme.Button(frame, "\195\151", "ghost", 28, 28) -- ×
	Theme.SetFont(close.label, 16)
	close:SetPoint("TOPRIGHT", -10, -12)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	self.rows = {}
	self.empty = Theme.Text(frame, 12, "muted")
	self.empty:SetText(L["FB_NO_MEMBERS"])

	self.hint = Theme.Text(frame, 11, "muted")
	self.hint:SetWidth(WIDTH - 2 * PAD - 120)
	self.hint:SetSpacing(2)
	self.hint:SetText(L["FB_HINT"])
	self.done = Theme.Button(frame, L["FB_DONE"], "primary", 100, 32)
	self.done:SetScript("OnClick", function()
		frame:Hide()
	end)
end

-- eine Zeile pro Mitspieler: Name (Klassenfarbe), Rolle, ggf. "Leaver"; darunter die Schilder
function FeedbackPopup:GetRow(index)
	local row = self.rows[index]
	if row then
		return row
	end
	row = CreateFrame("Frame", nil, self.frame)
	row:SetSize(WIDTH - 2 * PAD, ROW)
	Theme.Primer(row) -- entsteht beim Anzeigen (nach Größenabfragen): siehe Theme.Primer
	row.rule = Theme.Rule(row, "TOP")
	row.name = Theme.Text(row, 13)
	Theme.SetGameFont(row.name, 13)
	row.name:SetPoint("TOPLEFT", 0, -10)
	row.leaver = Theme.Badge(row, L["FB_LEAVER"], "blocked")
	row.leaver:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
	row.chips = {}
	for _, tag in ipairs(ns.Endorsements.TAGS) do
		local chip = Theme.Chip(row, "", false, function()
			ns.Endorsements:Toggle(self.run, row.key, tag)
			self:RefreshRow(row)
		end)
		chip.tag = tag
		table.insert(row.chips, chip)
	end
	row.favorite = Theme.Chip(row, L["FB_FAVORITE"], false, function(checked)
		ns.History:SetFavorite(row.key, checked)
		self:RefreshRow(row)
	end)
	row.block = Theme.Chip(row, L["FB_BLOCK"], false, function(checked)
		ns.History:SetBlocked(row.key, checked)
		self:RefreshRow(row)
	end)
	self.rows[index] = row
	return row
end

function FeedbackPopup:RefreshRow(row)
	local member, run = row.member, self.run
	local blocked = ns.History:IsBlocked(row.key)
	for _, chip in ipairs(row.chips) do
		chip:SetChecked(ns.Endorsements:Has(run, row.key, chip.tag))
		-- wer "Nie wieder" bekommt, wird nicht gleichzeitig gelobt
		chip:SetEnabled(not blocked)
		chip:SetAlpha(blocked and 0.4 or 1)
	end
	row.favorite:SetChecked(ns.History:IsFavorite(row.key))
	row.block:SetChecked(blocked)
	row.leaver:SetShown(member.left and true or false)
end

function FeedbackPopup:Show(run)
	if not run then
		return
	end
	if not self.frame then
		self:Create()
	end
	self.run = run
	local level = run.level and run.level > 0 and ("+" .. run.level .. " ") or ""
	self.subtitle:SetText(level .. (run.name or "?") .. "  \194\183  " .. StatusText(run))

	local me = ns.History:MyKey()
	local members = {}
	for _, member in ipairs(run.members or {}) do
		if member.key and member.key ~= me then
			table.insert(members, member)
		end
	end

	local y = 74
	for index, member in ipairs(members) do
		local row = self:GetRow(index)
		row.member, row.key = member, member.key
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD, -y)
		row.name:SetText(Util.RoleIcon(member.role or "DAMAGER", 14) .. "  "
			.. Util.ClassName(Ambiguate(member.name or member.key, "none"), member.class))
		-- Schilder in einer Reihe, rechts davon Favorit und Nie wieder
		local x = 0
		for _, chip in ipairs(row.chips) do
			chip.label:SetText(TagLabel(chip.tag, member))
			chip:SetWidth(chip.label:GetStringWidth() + 38)
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", x, -32)
			x = x + chip:GetWidth() + 6
		end
		row.block:ClearAllPoints()
		row.block:SetPoint("TOPRIGHT", 0, -32)
		row.favorite:ClearAllPoints()
		row.favorite:SetPoint("RIGHT", row.block, "LEFT", -6, 0)
		self:RefreshRow(row)
		row:Show()
		y = y + ROW
	end
	for index = #members + 1, #self.rows do
		self.rows[index]:Hide()
	end
	self.empty:ClearAllPoints()
	self.empty:SetPoint("TOPLEFT", PAD, -y)
	self.empty:SetShown(#members == 0)
	if #members == 0 then
		y = y + 30
	end

	self.hint:ClearAllPoints()
	self.hint:SetPoint("TOPLEFT", PAD, -(y + 14))
	self.done:ClearAllPoints()
	self.done:SetPoint("TOPRIGHT", -PAD, -(y + 12))
	self.frame:SetHeight(y + 14 + math.max(32, self.hint:GetStringHeight() or 30) + PAD)
	self.frame:Show()
	self.frame:Raise()
end

-- nach einem Key: kurz warten (Endbildschirm), nie im Kampf
function FeedbackPopup:OnRunCompleted(_, runId)
	if not KeyQueue.db.profile.general.askFeedback then
		return
	end
	C_Timer.After(SHOW_DELAY, function()
		local run = ns.History:GetRun(runId)
		if not run then
			return
		end
		if InCombatLockdown() then
			self.pendingRun = run
			self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
				self:UnregisterEvent("PLAYER_REGEN_ENABLED")
				self:Show(self.pendingRun)
				self.pendingRun = nil
			end)
			return
		end
		self:Show(run)
	end)
end

FeedbackPopup:RegisterMessage("KEYQUEUE_RUN_COMPLETED", "OnRunCompleted")
