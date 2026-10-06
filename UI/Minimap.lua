-- Minimap: KeyQueue-Button über LibDataBroker + LibDBIcon. Dadurch passt er sich automatisch an
-- (rund bei Blizzard, eckig bei ElvUI & Co.) und Sammel-Addons wie HidingBar, ElvUI oder
-- Minimap Button Bag können ihn einsammeln. Dazu ein Eintrag im Addon-Compartment und eine Seite
-- in Blizzards Optionen (Esc -> Optionen -> AddOns -> KeyQueue).
local ADDON_NAME, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Theme = ns.Theme

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local LDB = LibStub("LibDataBroker-1.1")
local DBIcon = LibStub("LibDBIcon-1.0")

-- Linksklick: Gruppensuche (dort sitzt die Queue), Rechtsklick: History und Einstellungen
local function Open(button)
	if button == "RightButton" then
		KeyQueue:ToggleMainWindow()
	else
		KeyQueue:ToggleGroupFinder()
	end
end

function MinimapButton:Init()
	if self.registered then
		return
	end
	self.registered = true

	-- LibDBIcon speichert Position und Sichtbarkeit in diesem Profil-Teil (minimapPos, hide)
	local store = KeyQueue.db.profile.minimap
	if store.minimapPos == nil and store.angle then
		store.minimapPos = store.angle -- alte KeyQueue-Position übernehmen
	end

	self.launcher = LDB:NewDataObject(ADDON_NAME, {
		type = "launcher",
		label = "KeyQueue",
		icon = Theme.media.icon,
		OnClick = function(_, button)
			Open(button)
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine(Theme.Brand())
			tooltip:AddLine(L["TAGLINE"], 0.6, 0.6, 0.65)
			tooltip:AddLine(" ")
			tooltip:AddLine(L["MINIMAP_TOOLTIP_CLICK"], 1, 1, 1)
			tooltip:AddLine(L["MINIMAP_TOOLTIP_RIGHT"], 1, 1, 1)
			tooltip:AddLine(L["MINIMAP_TOOLTIP_DRAG"], 0.6, 0.6, 0.65)
		end,
	})
	DBIcon:Register(ADDON_NAME, self.launcher, store)
	if DBIcon.AddButtonToCompartment then
		DBIcon:AddButtonToCompartment(ADDON_NAME)
	end
	self:CreateOptions()
end

function MinimapButton:IsShown()
	return not KeyQueue.db.profile.minimap.hide
end

function MinimapButton:SetShown(shown)
	KeyQueue.db.profile.minimap.hide = not shown
	if shown then
		DBIcon:Show(ADDON_NAME)
	else
		DBIcon:Hide(ADDON_NAME)
	end
	if self.optionsChip then
		self.optionsChip:SetChecked(shown)
	end
	if ns.SettingsTab.minimap then
		ns.SettingsTab.minimap:SetChecked(shown)
	end
end

-- Profilwechsel: Button-Einstellungen des neuen Profils übernehmen
function MinimapButton:Refresh()
	if not self.registered then
		return
	end
	DBIcon:Refresh(ADDON_NAME, KeyQueue.db.profile.minimap)
	self:SetShown(self:IsShown())
end

---------------------------------------------------------------------------
-- Seite in Blizzards Optionen: Minimap-Button an/aus und KeyQueue öffnen
---------------------------------------------------------------------------

function MinimapButton:CreateOptions()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return
	end
	local panel = CreateFrame("Frame")
	local logo = panel:CreateTexture(nil, "ARTWORK")
	logo:SetPoint("TOPLEFT", 16, -16)
	Theme.SetLogo(logo, 192)

	local text = Theme.Text(panel, 12, "muted")
	text:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -10)
	text:SetText(L["TAGLINE"])

	local open = Theme.Button(panel, L["OPTIONS_OPEN"], "primary", 200, 32)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -20)
	open:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then
			HideUIPanel(SettingsPanel)
		end
		KeyQueue:ToggleMainWindow()
	end)

	self.optionsChip = Theme.Chip(panel, L["SETTINGS_MINIMAP"], self:IsShown(), function(checked)
		self:SetShown(checked)
	end)
	self.optionsChip:SetHeight(28)
	self.optionsChip:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -16)

	local hint = Theme.Text(panel, 11, "muted")
	hint:SetPoint("TOPLEFT", self.optionsChip, "BOTTOMLEFT", 0, -10)
	hint:SetWidth(460)
	hint:SetText(L["OPTIONS_HINT"])

	panel:SetScript("OnShow", function()
		self.optionsChip:SetChecked(self:IsShown())
	end)
	local category = Settings.RegisterCanvasLayoutCategory(panel, "KeyQueue")
	Settings.RegisterAddOnCategory(category)
end
