-- StatusButton: rundes Status-Symbol (wie Blizzards "Auge" an der Minimap), solange KeyQueue in der
-- Queue ist oder eine Gruppe gelistet hat. Ring pulsiert in der Akzentfarbe, Tooltip zeigt den Stand.
-- Linksklick: Fenster öffnen/schließen, Rechtsklick: Menü (Queue verlassen / Listing beenden),
-- Ziehen: verschieben (Position im Profil).
local _, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Theme, Util = ns.Theme, ns.Util

local StatusButton = {}
ns.StatusButton = StatusButton
LibStub("AceEvent-3.0"):Embed(StatusButton)

local SIZE = 36

local function Options()
	return KeyQueue.db.profile
end

-- Was läuft gerade? "found", "queued", "party", "listed" oder nil
local function CurrentState()
	local search = ns.Search
	if search.state == "found" then
		return "found"
	end
	if search:IsQueued() and search:CanQueue() then
		return "queued"
	end
	local partyQueue = ns.Comm.partyQueue
	if partyQueue and partyQueue.state ~= "idle" and IsInGroup() and not UnitIsGroupLeader("player") then
		return "party"
	end
	if ns.Listing:IsListed() and GetNumGroupMembers() < 5 then
		return "listed"
	end
end

function StatusButton:Init()
	if self.button then
		return
	end
	local button = CreateFrame("Button", nil, UIParent)
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(20)
	button:SetMovable(true)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	self.button = button

	-- Ring (pulsiert), dunkle Scheibe, Bildmarke
	button.ring = button:CreateTexture(nil, "BACKGROUND")
	button.ring:SetAllPoints()
	button.ring:SetTexture(Theme.media.circle, nil, nil, "TRILINEAR")
	button.disc = button:CreateTexture(nil, "BORDER")
	button.disc:SetPoint("CENTER")
	button.disc:SetSize(SIZE - 6, SIZE - 6)
	button.disc:SetTexture(Theme.media.circle, nil, nil, "TRILINEAR")
	button.disc:SetVertexColor(unpack(Theme.color.bg))
	button.mark = button:CreateTexture(nil, "ARTWORK")
	button.mark:SetPoint("CENTER")
	button.mark:SetSize(22, 22)
	button.mark:SetTexture(Theme.media.mark, nil, nil, "TRILINEAR")

	local pulse = button.ring:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.9)
	fade:SetSmoothing("IN_OUT")
	button.pulse, button.fade = pulse, fade

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			self:ToggleMenu()
		else
			self.menu:Hide()
			KeyQueue:ToggleGroupFinder() -- dort sitzt die Queue
		end
	end)
	button:SetScript("OnDragStart", function(frame)
		self.menu:Hide()
		frame:StartMoving()
	end)
	button:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		local store = Options().statusButton
		store.point, store.relPoint, store.x, store.y = point, relPoint, x, y
	end)
	button:SetScript("OnEnter", function(frame)
		self:ShowTooltip(frame)
	end)
	button:SetScript("OnLeave", function()
		self:HideTooltip()
	end)

	self:CreateMenu()
	self:RestorePosition()

	-- Zeit im Tooltip und Zustand nachführen
	local elapsed = 0
	button:SetScript("OnUpdate", function(frame, delta)
		elapsed = elapsed + delta
		if elapsed >= 1 then
			elapsed = 0
			if self.tip and self.tip:IsShown() then
				self:ShowTooltip(frame)
			end
		end
	end)

	for _, message in ipairs({ "KEYQUEUE_SEARCH_UPDATE", "KEYQUEUE_PARTY_UPDATE", "KEYQUEUE_LEADER_UPDATE" }) do
		self:RegisterMessage(message, "Update")
	end
	self:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", "Update")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "Update")
	self:Update()
end

-- Standard: unten links an der Minimap (wie Blizzards Auge); sonst die gespeicherte Position
function StatusButton:RestorePosition()
	local button, store = self.button, Options().statusButton
	button:ClearAllPoints()
	if store.point then
		button:SetPoint(store.point, UIParent, store.relPoint, store.x, store.y)
	elseif Minimap and Minimap:IsShown() then
		button:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 14, 14)
	else
		button:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -220)
	end
end

function StatusButton:Update()
	local button = self.button
	if not button then
		return
	end
	local state = CurrentState()
	local enabled = Options().general.statusButton ~= false
	if not state or not enabled then
		button:Hide()
		self.menu:Hide()
		button.pulse:Stop()
		return
	end
	-- gefunden: hell und schnell; Queue: Akzent pulsierend; gelistet: Akzent ruhig
	local color = state == "found" and Theme.color.violetText or Theme.color.violet
	button.ring:SetVertexColor(unpack(color))
	button.fade:SetDuration(state == "found" and 0.35 or 0.9)
	if state == "listed" then
		button.pulse:Stop()
		button.ring:SetAlpha(1)
	elseif not button.pulse:IsPlaying() then
		button.pulse:Play()
	end
	button:Show()
end

-- Eigenes Info-Panel statt GameTooltip: Gruppennamen sind geschützte |K-Strings und erscheinen im
-- WoW-Tooltip nur als "Unbekannt" - eigene Textfelder zeigen sie richtig an (wie die Gruppenliste)
local TIP_WIDTH, TIP_PAD = 290, 14

function StatusButton:CreateTip()
	local tip = CreateFrame("Frame", nil, UIParent)
	tip:SetFrameStrata("TOOLTIP")
	tip:SetWidth(TIP_WIDTH)
	Theme.DropShadow(tip)
	Theme.SetSurface(tip, Theme.color.bg, Theme.color.border)
	tip:Hide()
	tip.lines = {}
	self.tip = tip
end

-- Zeile n: links Text (optional WoW-Schrift für Gruppennamen), rechts optional ein Wert
function StatusButton:TipLine(index, left, right, size, color, game, gap)
	local tip = self.tip
	local line = tip.lines[index]
	if not line then
		line = { left = Theme.Text(tip, 12), right = Theme.Text(tip, 12) }
		line.left:SetWordWrap(false)
		line.right:SetJustifyH("RIGHT")
		tip.lines[index] = line
	end
	if game then
		Theme.SetGameFont(line.left, size or 13)
	else
		Theme.SetFont(line.left, size or 12, color == "title")
	end
	line.left:SetTextColor(unpack(Theme.color[color == "title" and "text" or color or "text"] or Theme.color.text))
	line.left:SetText(left or "")
	line.right:SetText(right or "")
	line.gap = gap or 4
	line.left:Show()
	line.right:Show()
	return line
end

function StatusButton:ShowTooltip(owner)
	if not self.tip then
		self:CreateTip()
	end
	local tip = self.tip
	local index = 0
	local function Add(left, right, size, color, game, gap)
		index = index + 1
		return self:TipLine(index, left, right, size, color, game, gap)
	end

	Add(Theme.Brand(), nil, 13, "title", false, 0)
	local state = CurrentState()
	local search = ns.Search
	if state == "found" then
		Add(L["SEARCH_TITLE_FOUND"], nil, 12, "violetText")
	elseif state == "queued" then
		Add(L["SEARCH_TITLE_QUEUED"] .. "  " .. Util.FormatTime(search:GetElapsed()), nil, 12, "text")
		Add(L["SEARCH_DETAIL_QUEUED"]:format(search:CountMatches(), search:CountApplications(),
			MAX_LFG_LIST_APPLICATIONS or 5), nil, 11, "muted", false, 2)
	elseif state == "party" then
		Add(L["SEARCH_TITLE_PARTY"], nil, 12, "text")
	elseif state == "listed" then
		local session = ns.AutoInvite.session
		local since = session.listedAt and ("  " .. Util.FormatTime(time() - session.listedAt)) or ""
		Add(L["LEADER_LISTED_TITLE"] .. since, nil, 12, "text")
		Add(L["LEADER_APPLICANTS_COUNT"]:format(#ns.AutoInvite:GetFeed()), nil, 11, "muted", false, 2)
	end

	-- Bewerbungen: Gruppenname (mit Stufe), darunter Dungeon und Leader-RIO, rechts der Status
	local applications = (state == "queued" or state == "found") and search:GetActiveApplications() or {}
	if #applications > 0 then
		Add(L["STATUS_APPLICATIONS"], nil, 11, "dim", false, 12)
		for _, app in ipairs(applications) do
			local group = app.group
			local statusText = app.status == "invited" and Theme.Colorize(L["SEARCH_STATUS_INVITED"], "gold")
				or Theme.Colorize(L["SEARCH_STATUS_APPLIED"], "violetText")
			Add(group.title or "?", statusText, 13, "text", true, 8)
			local detail = group.dungeon or ""
			if (tonumber(group.leaderScore) or 0) > 0 then
				detail = detail .. "  -  " .. Util.ScoreText(group.leaderScore)
			end
			Add(detail, nil, 11, "muted", false, 2)
		end
	end

	Add(L["STATUS_HINT_OPEN"], nil, 11, "dim", false, 12)
	if self:MenuAction() then
		Add(L["STATUS_HINT_MENU"], nil, 11, "dim", false, 2)
	end
	Add(L["STATUS_HINT_DRAG"], nil, 11, "dim", false, 2)

	-- untereinander anordnen
	local y = TIP_PAD
	for lineIndex = 1, index do
		local line = tip.lines[lineIndex]
		y = y + (lineIndex > 1 and line.gap or 0)
		line.left:ClearAllPoints()
		line.left:SetPoint("TOPLEFT", TIP_PAD, -y)
		line.right:ClearAllPoints()
		line.right:SetPoint("TOPRIGHT", -TIP_PAD, -y)
		local rightWidth = (line.right:GetText() or "") ~= "" and (line.right:GetStringWidth() + 10) or 0
		line.left:SetWidth(TIP_WIDTH - 2 * TIP_PAD - rightWidth)
		y = y + math.max(14, math.ceil(line.left:GetStringHeight() or 14))
	end
	for lineIndex = index + 1, #tip.lines do
		tip.lines[lineIndex].left:Hide()
		tip.lines[lineIndex].right:Hide()
	end
	tip:SetHeight(y + TIP_PAD)
	tip:ClearAllPoints()
	tip:SetPoint("TOPRIGHT", owner, "BOTTOMLEFT", -4, -4)
	tip:SetClampedToScreen(true)
	tip:Show()
end

function StatusButton:HideTooltip()
	if self.tip then
		self.tip:Hide()
	end
end

-- Was der Menü-Knopf tun kann: Queue verlassen oder (als Leader) das Listing beenden
function StatusButton:MenuAction()
	local state = CurrentState()
	if state == "queued" or state == "found" then
		return L["SEARCH_CANCEL"], function()
			ns.Search:Cancel() -- direkt im Klick: CancelApplication braucht den Hardware-Event
		end
	elseif state == "listed" and (not IsInGroup() or UnitIsGroupLeader("player")) then
		return L["LEADER_BTN_REMOVE"], function()
			ns.Listing:Remove() -- direkt im Klick: RemoveListing braucht den Hardware-Event
		end
	end
end

-- Kleines Menü per Rechtsklick
function StatusButton:CreateMenu()
	local menu = Theme.Popover(self.button, 190)
	self.menu = menu
	menu.action = Theme.Button(menu, "", "secondary", 166, 30)
	menu.action:SetPoint("TOPLEFT", 12, -12)
	menu.action:SetScript("OnClick", function()
		local _, run = self:MenuAction()
		menu:Hide()
		if run then
			run()
		end
	end)
	menu.open = Theme.Button(menu, L["STATUS_OPEN"], "ghost", 166, 30)
	menu.open:SetPoint("TOPLEFT", menu.action, "BOTTOMLEFT", 0, -6)
	menu.open:SetScript("OnClick", function()
		menu:Hide()
		KeyQueue:ToggleGroupFinder()
	end)
	menu:SetHeight(12 + 30 + 6 + 30 + 12)
end

function StatusButton:ToggleMenu()
	local menu = self.menu
	if menu:IsShown() then
		menu:Hide()
		return
	end
	local label = self:MenuAction()
	menu.action:SetShown(label ~= nil)
	menu.action:SetLabel(label or "")
	menu.open:ClearAllPoints()
	if label then
		menu.open:SetPoint("TOPLEFT", menu.action, "BOTTOMLEFT", 0, -6)
		menu:SetHeight(12 + 30 + 6 + 30 + 12)
	else
		menu.open:SetPoint("TOPLEFT", 12, -12)
		menu:SetHeight(12 + 30 + 12)
	end
	self:HideTooltip()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", self.button, "BOTTOMRIGHT", 4, 0)
	menu:Show()
end
