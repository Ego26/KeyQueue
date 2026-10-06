-- MainFrame: kleines KeyQueue-Fenster mit History und Einstellungen. Suchen und Gruppen erstellen laufen
-- über die Matchmaking-Queue im Panel an Blizzards Gruppensuche (UI/QueuePanel.lua).
local _, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Theme, Util = ns.Theme, ns.Util

local MainFrame = {}
ns.MainFrame = MainFrame
LibStub("AceEvent-3.0"):Embed(MainFrame)

-- Zwei Größen: kompakt (Standard, wenig Platz - man kann nebenbei spielen) und groß
local LARGE_WIDTH, LARGE_HEIGHT = 820, 666
local COMPACT_WIDTH, COMPACT_HEIGHT = 440, 660
local TABS = {
	{ key = "history", label = "TAB_HISTORY", module = "HistoryTab" },
	{ key = "settings", label = "TAB_SETTINGS", module = "SettingsTab" },
}

function KeyQueue:ToggleMainWindow()
	MainFrame:Toggle()
end

-- Blizzards Gruppensuche bei "Organisierte Gruppen" öffnen bzw. schließen: dort sitzt die Queue
-- (Panel rechts, sobald "Dungeons" offen ist). Nicht im Kampf (Blizzards Fenster sind dann gesperrt).
function KeyQueue:ToggleGroupFinder()
	if InCombatLockdown() then
		return
	end
	if not PVEFrame_ToggleFrame and C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_GroupFinder")
	end
	if PVEFrame_ToggleFrame then
		pcall(PVEFrame_ToggleFrame, "GroupFinderFrame", _G.LFGListPVEStub)
	end
end

function KeyQueue:OpenApiCheck()
	if ns.Phase0Frame then -- Dev/ fehlt in der Fassung auf GitHub
		ns.Phase0Frame:Open()
	end
end

function MainFrame:Toggle()
	if self.frame and self.frame:IsShown() then
		self.frame:Hide()
	else
		self:Open()
	end
end

---------------------------------------------------------------------------
-- Wie Blizzards Fenster: öffnet sich ein Blizzard-Fenster (Charakter, Kontakte, Zauberbuch ...), rückt
-- KeyQueue rechts daneben, statt darüber zu liegen; sind alle zu, geht KeyQueue an seinen Platz zurück.
-- Nur lesend über hooksecurefunc - KeyQueue meldet sich bewusst nicht im Panel-System an (sonst
-- liefe Blizzards Fenster-Verwaltung mit KeyQueue-Code und würde "tainted").
---------------------------------------------------------------------------

local PANEL_KEYS = { "left", "center", "right", "doublewide" }

function MainFrame:HookBlizzardPanels()
	if self.panelsHooked then
		return
	end
	self.panelsHooked = true
	local function Update()
		self:DockBesidePanels()
	end
	-- Blizzards Fenster-Verwaltung selbst ist für Addons gesperrt - die globalen Funktionen nicht
	for _, name in ipairs({ "ShowUIPanel", "HideUIPanel", "UpdateUIPanelPositions" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, Update)
		end
	end
	-- Esc schließt Blizzard-Fenster teils an diesen Funktionen vorbei: solange KeyQueue daneben steht,
	-- zweimal pro Sekunde nachsehen, ob noch eins offen ist
	local elapsed = 0
	self.frame:HookScript("OnUpdate", function(_, delta)
		if not rawget(self.frame, "docked") then
			return
		end
		elapsed = elapsed + delta
		if elapsed >= 0.5 then
			elapsed = 0
			Update()
		end
	end)
end

-- rechte und obere Kante der offenen Blizzard-Fenster (UIParent-Einheiten), nil wenn keins offen ist
function MainFrame:BlizzardPanelsEdge()
	if type(GetUIPanel) ~= "function" then
		return nil
	end
	local uiScale = UIParent:GetEffectiveScale()
	local right, top
	for _, key in ipairs(PANEL_KEYS) do
		local panel = GetUIPanel(key)
		if panel and panel ~= self.frame and panel:IsShown() then
			local edge, panelTop = panel:GetRight(), panel:GetTop()
			if edge and panelTop then
				local scale = panel:GetEffectiveScale() / uiScale
				right = math.max(right or 0, edge * scale)
				top = math.max(top or 0, panelTop * scale)
			end
		end
	end
	-- KeyQueue-Panel rechts an der Gruppensuche (und im Entwickler-Build der Matchmaking-Test daneben)
	for _, extra in ipairs({ ns.QueuePanel and rawget(ns.QueuePanel, "frame"), ns.MatchTest and rawget(ns.MatchTest, "frame") }) do
		if extra and extra:IsShown() and right and extra:GetRight() then
			right = math.max(right, extra:GetRight() * extra:GetEffectiveScale() / uiScale)
		end
	end
	return right, top
end

function MainFrame:DockBesidePanels()
	local frame = self.frame
	if not frame or not frame:IsShown() then
		return
	end
	local ok, right, top = pcall(self.BlizzardPanelsEdge, self)
	if not ok then
		return
	end
	if right then
		local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		frame.docked = true
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (right + 8) / scale, top / scale)
		frame:SnapToPixels()
	elseif rawget(frame, "docked") then
		frame.docked = nil
		frame:RestorePosition()
	end
end

function MainFrame:Open(tabKey)
	if not self.frame then
		self:Create()
	end
	-- beim Öffnen die Größe aus den Einstellungen (Standard: kompakt)
	if not self.frame:IsShown() then
		self:SetCompact(KeyQueue.db.profile.general.windowDefault ~= "large")
	end
	self.frame:Show()
	self:DockBesidePanels() -- schon ein Blizzard-Fenster offen: gleich daneben
	self:SelectTab(tabKey or KeyQueue.db.profile.general.lastTab or "history")
end

function MainFrame:Create()
	local frame = Theme.Window(LARGE_WIDTH, LARGE_HEIGHT, KeyQueue.db.profile.mainWindow)
	self.frame = frame
	self:HookBlizzardPanels()
	-- Seitenfenster (Gruppen-Details, Spieler-Profil) schließen mit dem Hauptfenster (auch per ESC)
	frame:HookScript("OnHide", function()
		for _, card in ipairs({ ns.ProfileCard, ns.RunCard }) do
			local side = card and rawget(card, "frame")
			if side then
				side:Hide()
			end
		end
	end)
	frame.info:SetText("v" .. KeyQueue.version)

	-- kompakt: nur die Bildmarke statt des ganzen Logos
	frame.mark = frame.header:CreateTexture(nil, "ARTWORK")
	frame.mark:SetSize(Theme.PixelSize(frame, 26), Theme.PixelSize(frame, 26))
	frame.mark:SetPoint("LEFT", 14, 0)
	frame.mark:SetTexture(Theme.media.mark, nil, nil, "TRILINEAR")

	-- rechts oben: groß/kompakt umschalten (und im kompakten Modus: Einstellungen)
	self.sizeButton = Theme.IconButton(frame.header, Theme.media.collapse, 28)
	self.sizeButton:SetPoint("RIGHT", frame.close, "LEFT", -2, 0)
	self.sizeButton:SetScript("OnClick", function()
		self:SetCompact(not self.compact)
	end)
	frame.info:ClearAllPoints()
	frame.info:SetPoint("RIGHT", self.sizeButton, "LEFT", -8, 0)

	self.tabs, self.pages = {}, {}
	local previous
	for _, def in ipairs(TABS) do
		-- Reiter sitzen in der Kopfzeile rechts neben dem Logo
		local tab = Theme.Tab(frame.header, L[def.label])
		if previous then
			tab:SetPoint("LEFT", previous, "RIGHT", 0, 0)
		end
		tab:SetScript("OnClick", function()
			self:SelectTab(def.key)
		end)
		self.tabs[def.key] = tab

		local page = CreateFrame("Frame", nil, frame)
		page:Hide()
		ns[def.module]:Create(page)
		self.pages[def.key] = page
		previous = tab
	end

	self:SetCompact(false)
	self:RegisterMessage("KEYQUEUE_PROFILE_CHANGED", "RefreshAll")
end

function MainFrame:IsCompact()
	return self.compact and true or false
end

-- Breite einer Seite (Inhalt eines Tabs) im aktuellen Modus - fest, weil Frames direkt nach dem
-- Umschalten noch ihre alte Breite melden können
function MainFrame:PageWidth()
	if self.compact then
		return COMPACT_WIDTH - 2 * 14
	end
	return LARGE_WIDTH - 18 - 16
end

-- Fenstergröße umschalten: Kopfzeile, Seitenränder und jeder Tab ordnen sich neu an
function MainFrame:SetCompact(compact)
	compact = compact and true or false
	local frame = self.frame
	if not frame or (self.compact == compact and self.laidOut) then
		return
	end
	self.compact, self.laidOut = compact, true
	frame:SetSize(compact and COMPACT_WIDTH or LARGE_WIDTH, compact and COMPACT_HEIGHT or LARGE_HEIGHT)

	frame.logo:SetShown(not compact)
	frame.mark:SetShown(compact)
	frame.info:SetShown(not compact)
	self.sizeButton:SetIcon(compact and Theme.media.expand or Theme.media.collapse,
		compact and L["WINDOW_LARGE"] or L["WINDOW_COMPACT"])

	local first = true
	for _, def in ipairs(TABS) do
		local tab = self.tabs[def.key]
		tab:SetLabel(L[(compact and def.short) or def.label])
		if first then
			tab:ClearAllPoints()
			tab:SetPoint("LEFT", compact and frame.mark or frame.logo, "RIGHT", compact and 6 or 10, 0)
			first = false
		end
		local page = self.pages[def.key]
		local side = compact and 14 or 18
		page:ClearAllPoints()
		page:SetPoint("TOPLEFT", Theme.PixelSize(frame, side), -Theme.PixelSize(frame, 64))
		page:SetPoint("BOTTOMRIGHT", -Theme.PixelSize(frame, compact and 14 or 16), Theme.PixelSize(frame, compact and 14 or 16))
		local module = ns[def.module]
		if module.SetCompact then
			module:SetCompact(compact)
		end
	end

	-- Run-Fenster gibt es nur kompakt (groß stehen die Details in der Liste)
	local runCard = ns.RunCard and rawget(ns.RunCard, "frame")
	if runCard and not compact then
		runCard:Hide()
	end
	frame:SnapToPixels()
	local current = KeyQueue.db.profile.general.lastTab or "history"
	if frame:IsShown() and self.pages[current] then
		self:SelectTab(current)
	end
end

function MainFrame:SelectTab(key)
	if not self.pages[key] then
		key = "history" -- früher gemerkte Reiter (Suchen/Erstellen) gibt es nicht mehr
	end
	KeyQueue.db.profile.general.lastTab = key
	-- Seitenfenster gehören zum vorigen Tab (Profil, Run-Details); die eigene Saison bleibt
	for _, card in ipairs({ ns.ProfileCard, ns.RunCard }) do
		local side = card and rawget(card, "frame")
		if side then
			side:Hide()
		end
	end
	for _, def in ipairs(TABS) do
		local active = def.key == key
		self.tabs[def.key]:SetActive(active)
		self.pages[def.key]:SetShown(active)
		if active then
			ns[def.module]:Refresh()
		end
	end
end

function MainFrame:RefreshAll()
	if not self.frame then
		return
	end
	self.frame:SetScale(KeyQueue.db.profile.mainWindow.scale or 1)
	self.frame:SnapToPixels()
	for _, def in ipairs(TABS) do
		ns[def.module]:Refresh()
	end
end
