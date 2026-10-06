-- SettingsTab: Tab "Einstellungen" als saubere Liste - pro Einstellung eine Zeile: links Name und
-- kurze Erklärung, rechts das Bedienelement (Schalter, Stepper, Knopf). Auswahlen mit mehreren
-- Optionen (Segment-Umschalter) stehen unter dem Text. Groß: zwei Spalten, kompakt: eine Spalte.
local _, ns = ...

local KeyQueue = ns.addon
local L = ns.L
local Theme, Util = ns.Theme, ns.Util

local SettingsTab = {}
ns.SettingsTab = SettingsTab

local BLACKLIST_ROWS = 6
local PAD = 12

local function General()
	return KeyQueue.db.profile.general
end

---------------------------------------------------------------------------
-- Bausteine: Bereich mit Überschrift, Zeilen darin
---------------------------------------------------------------------------

local function Section(parent, title)
	local section = Theme.Card(parent)
	section.header = Theme.Text(section, 13, "text", nil, nil, true)
	section.header:SetPoint("TOPLEFT", PAD, -14)
	section.header:SetText(title)
	section.rows = {}
	return section
end

-- kind: "inline" (Bedienelement rechts) oder "stacked" (Bedienelement unter dem Text);
-- custom(row, width) für eigene Inhalte, gibt die Höhe zurück
-- Rückgabe: Zeilen-Daten { frame, kind, control, custom, title, desc, rule }
local function AddRow(section, title, desc, control, kind, custom)
	local frame = CreateFrame("Frame", nil, section)
	local row = { frame = frame, kind = kind or "inline", control = control, custom = custom }
	if title then
		row.title = Theme.Text(frame, 13, "text")
		row.title:SetText(title)
		row.title:SetWordWrap(false)
	end
	if desc then
		row.desc = Theme.Text(frame, 11, "muted")
		row.desc:SetText(desc)
		row.desc:SetSpacing(2)
	end
	if control then
		control:SetParent(frame)
	end
	row.rule = Theme.Rule(frame, "BOTTOM", PAD)
	table.insert(section.rows, row)
	return row
end

-- Zeilen einer Section untereinander anordnen (Höhe folgt den Texten bei der gegebenen Breite)
local function LayoutSection(section, width)
	local y = 44
	for index, row in ipairs(section.rows) do
		local frame = row.frame
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -y)
		frame:SetWidth(width)
		local height
		if row.custom then
			height = row.custom(row, width)
		else
			local control = row.control
			local textWidth = width - 2 * PAD
			if control and row.kind == "inline" then
				textWidth = textWidth - control:GetWidth() - 16
			end
			local top = 12
			if row.title then
				row.title:ClearAllPoints()
				row.title:SetPoint("TOPLEFT", PAD, -top)
				row.title:SetWidth(textWidth)
				top = top + 16
			end
			if row.desc then
				row.desc:ClearAllPoints()
				row.desc:SetPoint("TOPLEFT", PAD, -(top + 3))
				row.desc:SetWidth(textWidth)
				top = top + 3 + math.ceil(row.desc:GetStringHeight() or 14)
			end
			if control and row.kind == "stacked" then
				control:ClearAllPoints()
				control:SetPoint("TOPLEFT", PAD, -(top + 10))
				top = top + 10 + control:GetHeight()
			end
			height = top + 12
			if control and row.kind == "inline" then
				control:ClearAllPoints()
				control:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
			end
		end
		frame:SetHeight(height)
		row.rule:SetShown(index < #section.rows)
		y = y + height
	end
	section:SetHeight(y + 4)
	return y + 4
end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------

function SettingsTab:Create(page)
	self.page = page
	page:SetScript("OnShow", function()
		self:Refresh()
	end)

	local scroll, child = Theme.ScrollArea(page, 48)
	scroll:SetAllPoints(page)
	self.scroll, self.child = scroll, child

	self.sections = {
		general = Section(child, L["SETTINGS_GENERAL"]),
		profile = Section(child, L["SETTINGS_PROFILE"]),
		language = Section(child, L["SETTINGS_LANGUAGE"]),
		blacklist = Section(child, L["SETTINGS_BLACKLIST"]),
		developer = Section(child, L["SETTINGS_DEVELOPER"]),
	}
	self:CreateGeneral(self.sections.general)
	self:CreateProfile(self.sections.profile)
	self:CreateLanguage(self.sections.language)
	self:CreateBlacklist(self.sections.blacklist)
	self:CreateDeveloper(self.sections.developer)
	self:SetCompact(false)
end

function SettingsTab:CreateGeneral(section)
	-- Tastenkürzel zum Öffnen: Knopf klicken, Taste drücken (Esc bricht ab, Rechtsklick entfernt)
	self.keybind = Theme.Button(section, "", "secondary", 130, 30)
	self.keybind:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	self.keybind:SetScript("OnClick", function(button, mouseButton)
		if InCombatLockdown() then
			return
		end
		if mouseButton == "RightButton" then
			for _, key in ipairs({ GetBindingKey("KEYQUEUE_TOGGLE") }) do
				SetBinding(key)
			end
			SaveBindings(GetCurrentBindingSet())
			self:StopKeyCapture()
			return
		end
		self:StartKeyCapture()
	end)
	self.keybind:SetScript("OnKeyDown", function(_, key)
		self:CaptureKey(key)
	end)
	self.keybind:EnableKeyboard(false)
	AddRow(section, L["SETTINGS_KEYBIND"], L["SETTINGS_KEYBIND_DESC"], self.keybind)

	self.minimap = Theme.Switch(section, "", true, function(checked)
		ns.MinimapButton:SetShown(checked)
	end)
	AddRow(section, L["SETTINGS_MINIMAP"], L["SETTINGS_MINIMAP_DESC"], self.minimap)

	self.statusButton = Theme.Switch(section, "", true, function(checked)
		General().statusButton = checked
		ns.StatusButton:Update()
	end)
	AddRow(section, L["SETTINGS_STATUS_BUTTON"], L["SETTINGS_STATUS_BUTTON_DESC"], self.statusButton)

	self.sound = Theme.Switch(section, "", true, function(checked)
		General().sound = checked
	end)
	AddRow(section, L["SETTINGS_SOUND"], L["SETTINGS_SOUND_DESC"], self.sound)

	self.autoAccept = Theme.Switch(section, "", false, function(checked)
		General().autoAccept = checked
	end)
	AddRow(section, L["SETTINGS_AUTOACCEPT"], L["SETTINGS_AUTOACCEPT_DESC"], self.autoAccept)

	self.askFeedback = Theme.Switch(section, "", true, function(checked)
		General().askFeedback = checked
	end)
	AddRow(section, L["SETTINGS_FEEDBACK"], L["SETTINGS_FEEDBACK_DESC"], self.askFeedback)

	self.scale = Theme.Stepper(section, "", 8, 14, 10, function(value)
		KeyQueue.db.profile.mainWindow.scale = value / 10
		ns.MainFrame.frame:SetScale(value / 10)
		ns.MainFrame.frame:SnapToPixels()
		self.scale.value:SetText(value * 10 .. "%")
	end)
	self.scale.value:SetWidth(44)
	self.scale:SetWidth(110)
	AddRow(section, L["SETTINGS_SCALE"], L["SETTINGS_SCALE_DESC"], self.scale)

	self.windowDefault = Theme.Segmented(section, {
		{ value = "compact", text = L["SETTINGS_WINDOW_COMPACT"] },
		{ value = "large", text = L["SETTINGS_WINDOW_LARGE"] },
	}, function(value)
		General().windowDefault = value
	end)
	AddRow(section, L["SETTINGS_WINDOW_DEFAULT"], L["SETTINGS_WINDOW_DEFAULT_DESC"], self.windowDefault, "stacked")
end

function SettingsTab:CreateProfile(section)
	local db = KeyQueue.db
	self.profileDropdown = Theme.Dropdown(section, 190, function()
		local options = {}
		for _, name in ipairs(db:GetProfiles()) do
			table.insert(options, { text = name, value = name })
		end
		return options
	end, function(name)
		db:SetProfile(name)
	end)
	self.profileDropdown:SetHeight(30)
	local reset = Theme.Button(section, L["SETTINGS_PROFILE_RESET"], "secondary", 110, 30)
	reset:SetWidth(reset.label:GetStringWidth() + 28)
	reset:SetScript("OnClick", function()
		db:ResetProfile()
	end)
	local newName = Theme.EditBox(section, 190, L["SETTINGS_PROFILE_NEW_PLACEHOLDER"])
	newName:SetHeight(30)
	newName:SetMaxLetters(32)
	local create = Theme.Button(section, L["SETTINGS_PROFILE_NEW"], "secondary", 110, 30)
	create:SetWidth(create.label:GetStringWidth() + 28)
	create:SetScript("OnClick", function()
		local name = strtrim(newName:GetText())
		if name ~= "" then
			db:SetProfile(name) -- legt das Profil an, falls es noch nicht existiert
			newName:SetText("")
			newName:ClearFocus()
		end
	end)

	-- Zeile 1: aktives Profil (Auswahl + Zurücksetzen), Zeile 2: neues Profil anlegen
	AddRow(section, L["SETTINGS_PROFILE_ACTIVE"], L["SETTINGS_PROFILE_HINT"], nil, nil, function(row, width)
		for _, element in ipairs({ self.profileDropdown, reset }) do
			element:SetParent(row.frame)
		end
		row.title:ClearAllPoints()
		row.title:SetPoint("TOPLEFT", PAD, -12)
		row.title:SetWidth(width - 2 * PAD)
		row.desc:ClearAllPoints()
		row.desc:SetPoint("TOPLEFT", PAD, -31)
		row.desc:SetWidth(width - 2 * PAD)
		local top = 31 + math.ceil(row.desc:GetStringHeight() or 14) + 10
		self.profileDropdown:ClearAllPoints()
		self.profileDropdown:SetPoint("TOPLEFT", PAD, -top)
		reset:ClearAllPoints()
		reset:SetPoint("LEFT", self.profileDropdown, "RIGHT", 8, 0)
		return top + 30 + 12
	end)
	AddRow(section, L["SETTINGS_PROFILE_NEW_TITLE"], nil, nil, nil, function(row, width)
		for _, element in ipairs({ newName, create }) do
			element:SetParent(row.frame)
		end
		row.title:ClearAllPoints()
		row.title:SetPoint("TOPLEFT", PAD, -12)
		newName:ClearAllPoints()
		newName:SetPoint("TOPLEFT", PAD, -38)
		create:ClearAllPoints()
		create:SetPoint("LEFT", newName, "RIGHT", 8, 0)
		return 38 + 30 + 12
	end)
end

---------------------------------------------------------------------------
-- Tastenkürzel aufnehmen
---------------------------------------------------------------------------

local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	LMETA = true, RMETA = true }

function SettingsTab:RefreshKeybind()
	local key = GetBindingKey("KEYQUEUE_TOGGLE")
	self.keybind:SetLabel(key and GetBindingText(key) or L["SETTINGS_KEYBIND_NONE"])
	self.keybind:SetWidth(math.max(130, self.keybind.label:GetStringWidth() + 28))
end

function SettingsTab:StartKeyCapture()
	self.capturing = true
	self.keybind:SetLabel(L["SETTINGS_KEYBIND_PRESS"])
	self.keybind:EnableKeyboard(true)
	self.keybind:SetPropagateKeyboardInput(false)
end

function SettingsTab:StopKeyCapture()
	self.capturing = nil
	self.keybind:EnableKeyboard(false)
	self:RefreshKeybind()
end

function SettingsTab:CaptureKey(key)
	if not self.capturing or MODIFIER_KEYS[key] then
		return
	end
	if key == "ESCAPE" or InCombatLockdown() then
		return self:StopKeyCapture()
	end
	local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "") .. key
	-- war die Taste schon belegt, sagen wir es (Blizzards Belegung wird dabei ersetzt)
	local previous = GetBindingAction(combo)
	if previous and previous ~= "" and previous ~= "KEYQUEUE_TOGGLE" then
		KeyQueue:Msg(L["SETTINGS_KEYBIND_REPLACED"]:format(GetBindingText(combo), _G["BINDING_NAME_" .. previous] or previous))
	end
	for _, old in ipairs({ GetBindingKey("KEYQUEUE_TOGGLE") }) do
		SetBinding(old)
	end
	SetBinding(combo, "KEYQUEUE_TOGGLE")
	SaveBindings(GetCurrentBindingSet())
	self:StopKeyCapture()
end

-- Sprachnamen immer in der eigenen Sprache, damit man sie auch in der falschen Sprache findet
local LANGUAGE_NAMES = { deDE = "Deutsch", enUS = "English" }

function SettingsTab:CreateLanguage(section)
	local choices = {}
	for _, choice in ipairs(KeyQueue.LANGUAGES) do
		table.insert(choices, { value = choice, text = choice })
	end
	self.language = Theme.Segmented(section, choices, function(value)
		KeyQueue:SetLanguage(value)
		self:RefreshLanguage()
	end)
	-- Texte stehen schon in den Fenstern: neue Sprache wirkt nach dem Neuladen
	self.languageReload = Theme.Button(section, L["SETTINGS_LANGUAGE_RELOAD"], "primary", 130, 30)
	self.languageReload:SetWidth(self.languageReload.label:GetStringWidth() + 28)
	self.languageReload:SetScript("OnClick", function()
		if C_UI and C_UI.Reload then
			C_UI.Reload()
		else
			ReloadUI()
		end
	end)
	self.languageRow = AddRow(section, L["SETTINGS_LANGUAGE_TITLE"], "", self.language, "stacked")
	self.languageReload:SetParent(self.languageRow.frame)
	self.languageReload:SetPoint("LEFT", self.language, "RIGHT", 10, 0)
end

function SettingsTab:CreateBlacklist(section)
	local input = Theme.EditBox(section, 190, L["SETTINGS_BLACKLIST_PLACEHOLDER"])
	input:SetHeight(30)
	local add = Theme.Button(section, L["SETTINGS_BLACKLIST_ADD"], "secondary", 90, 30)
	add:SetWidth(add.label:GetStringWidth() + 28)
	local function Add()
		local key = Util.NameKey(strtrim(input:GetText()))
		if key and key ~= "" then
			KeyQueue.db.global.blacklist[key] = true
			input:SetText("")
			input:ClearFocus()
			self:RefreshBlacklist()
		end
	end
	add:SetScript("OnClick", Add)
	input:SetScript("OnEnterPressed", Add)

	AddRow(section, nil, L["SETTINGS_BLACKLIST_EMPTY"], nil, nil, function(row, width)
		for _, element in ipairs({ input, add }) do
			element:SetParent(row.frame)
		end
		row.desc:ClearAllPoints()
		row.desc:SetPoint("TOPLEFT", PAD, -12)
		row.desc:SetWidth(width - 2 * PAD)
		local top = 12 + math.ceil(row.desc:GetStringHeight() or 14) + 10
		input:ClearAllPoints()
		input:SetPoint("TOPLEFT", PAD, -top)
		add:ClearAllPoints()
		add:SetPoint("LEFT", input, "RIGHT", 8, 0)
		top = top + 30 + 8
		for index, entry in ipairs(self.blacklistRows) do
			entry:ClearAllPoints()
			entry:SetPoint("TOPLEFT", row.frame, "TOPLEFT", PAD, -(top + (index - 1) * 28))
			entry:SetPoint("RIGHT", row.frame, "RIGHT", -PAD, 0)
		end
		self.blacklistMore:ClearAllPoints()
		self.blacklistMore:SetPoint("TOPLEFT", row.frame, "TOPLEFT", PAD, -(top + (self.blacklistCount or 0) * 28))
		local listHeight = (self.blacklistCount or 0) * 28 + (self.blacklistMoreShown and 18 or 0)
		return top + listHeight + 8
	end)

	local row = section.rows[#section.rows]
	self.blacklistRows = {}
	for index = 1, BLACKLIST_ROWS do
		local entry = CreateFrame("Frame", nil, row.frame)
		entry:SetHeight(26)
		entry.name = Theme.Text(entry, 12)
		Theme.SetGameFont(entry.name, 12)
		entry.name:SetPoint("LEFT")
		entry.remove = Theme.Button(entry, "\195\151", "ghost", 26, 26)
		entry.remove:SetPoint("RIGHT")
		self.blacklistRows[index] = entry
	end
	self.blacklistMore = Theme.Text(row.frame, 11, "muted")
end

function SettingsTab:CreateDeveloper(section)
	-- API-Check (Dev/) fehlt in der Fassung auf GitHub: dann nur die Version
	if not ns.Phase0Frame then
		AddRow(section, "KeyQueue v" .. KeyQueue.version)
		return
	end
	local apiCheck = Theme.Button(section, L["SETTINGS_API_CHECK"], "secondary", 160, 30)
	apiCheck:SetWidth(apiCheck.label:GetStringWidth() + 28)
	apiCheck:SetScript("OnClick", function()
		KeyQueue:OpenApiCheck()
	end)
	AddRow(section, "KeyQueue v" .. KeyQueue.version, L["SETTINGS_API_CHECK_DESC"], apiCheck)
end

---------------------------------------------------------------------------
-- Anordnung: groß zwei Spalten (links Allgemein, rechts der Rest), kompakt eine Spalte
---------------------------------------------------------------------------

function SettingsTab:SetCompact(compact)
	self.compact = compact
	self:Layout()
	self.scroll:SetVerticalScroll(0)
end

function SettingsTab:Layout()
	local s, child = self.sections, self.child
	if not s then
		return
	end
	for _, section in pairs(s) do
		section:ClearAllPoints()
	end
	local width = ns.MainFrame:PageWidth() - 12 -- Inhalt des Scrollbereichs (ohne Scrollleiste)
	local gap = 10
	if self.compact then
		local y = 0
		for _, key in ipairs({ "general", "profile", "language", "blacklist", "developer" }) do
			local section = s[key]
			section:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
			section:SetWidth(width)
			y = y + LayoutSection(section, width) + gap
		end
		child:SetHeight(y)
	else
		local column = math.floor((width - 16) / 2)
		s.general:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
		s.general:SetWidth(column)
		local left = LayoutSection(s.general, column)
		local y = 0
		for _, key in ipairs({ "profile", "language", "blacklist", "developer" }) do
			local section = s[key]
			section:SetPoint("TOPLEFT", child, "TOPLEFT", column + 16, -y)
			section:SetWidth(column)
			y = y + LayoutSection(section, column) + gap
		end
		child:SetHeight(math.max(left, y))
	end
end

---------------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------------

function SettingsTab:RefreshLanguage()
	local current = KeyQueue.db.global.language or "auto"
	local texts = {}
	for index, choice in ipairs(KeyQueue.LANGUAGES) do
		texts[index] = choice == "auto" and L["SETTINGS_LANGUAGE_AUTO"] or LANGUAGE_NAMES[choice] or choice
	end
	self.language:SetTexts(texts)
	self.language:SetValue(current)
	local needsReload = KeyQueue:LanguageNeedsReload()
	self.languageReload:SetShown(needsReload)
	self.languageRow.desc:SetText(needsReload and L["SETTINGS_LANGUAGE_PENDING"]
		or L["SETTINGS_LANGUAGE_HINT"]:format(LANGUAGE_NAMES[KeyQueue:ResolveLanguage("auto")] or "?"))
end

function SettingsTab:RefreshBlacklist()
	local names = {}
	for key in pairs(KeyQueue.db.global.blacklist) do
		table.insert(names, key)
	end
	table.sort(names)
	for index, entry in ipairs(self.blacklistRows) do
		local key = names[index]
		if key then
			entry.name:SetText(key)
			entry.remove:SetScript("OnClick", function()
				KeyQueue.db.global.blacklist[key] = nil
				self:RefreshBlacklist()
				self:Layout()
			end)
			entry:Show()
		else
			entry:Hide()
		end
	end
	self.blacklistCount = math.min(#names, BLACKLIST_ROWS)
	self.blacklistMoreShown = #names > BLACKLIST_ROWS
	self.blacklistMore:SetText(self.blacklistMoreShown and L["SETTINGS_BLACKLIST_MORE"]:format(#names - BLACKLIST_ROWS) or "")
end

function SettingsTab:Refresh()
	if not self.page then
		return
	end
	local profile = KeyQueue.db.profile
	self.profileDropdown:SetValue(KeyQueue.db:GetCurrentProfile())
	self.minimap:SetChecked(not profile.minimap.hide)
	self.statusButton:SetChecked(profile.general.statusButton ~= false)
	self.sound:SetChecked(profile.general.sound)
	self.autoAccept:SetChecked(profile.general.autoAccept)
	self.askFeedback:SetChecked(profile.general.askFeedback ~= false)
	self.windowDefault:SetValue(profile.general.windowDefault or "compact")
	local scale = math.floor((profile.mainWindow.scale or 1) * 10 + 0.5)
	self.scale:SetValue(scale)
	self.scale.value:SetText(scale * 10 .. "%")
	self:RefreshKeybind()
	self:RefreshLanguage()
	self:RefreshBlacklist()
	self:Layout()
end
