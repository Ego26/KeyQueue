-- Theme: KeyQueue-Design (Farben, Schrift, Flächen) und eigene Widgets statt Blizzard-/AceGUI-Look
-- Leitlinie "Big App Feeling": flache, fast schwarze Flächen, feine Linien statt Kästen, Hierarchie über
-- Größe und Gewicht, genau eine Akzentfarbe (Blau) für Hauptaktion und Aktives. Markenrichtlinien: Branding/README.md
local ADDON_NAME, ns = ...

local Theme = {}
ns.Theme = Theme

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
Theme.media = {
	icon = MEDIA .. "Icon",       -- 64 x 64, Bildmarke auf Kachel
	mark = MEDIA .. "Mark",       -- 64 x 64, Bildmarke transparent
	logo = MEDIA .. "Logo",       -- 512 x 128, Bildmarke + Wortmarke
	rounded = MEDIA .. "Rounded", -- 32 x 32, abgerundete Fläche (9-Slice)
	shadow = MEDIA .. "Shadow",   -- 64 x 64, weicher Schatten (9-Slice)
	circle = MEDIA .. "Circle",   -- 64 x 64, weicher weißer Kreis (mit SetVertexColor einfärben)
	roleTank = MEDIA .. "RoleTank",     -- 64 x 64, Rollen-Glyphen weiß (einfärbbar)
	roleHealer = MEDIA .. "RoleHealer",
	roleDps = MEDIA .. "RoleDps",
	roleLeader = MEDIA .. "RoleLeader", -- Krone (Gruppenleiter)
	logoSheet = MEDIA .. "LogoSheet", -- 512 x 512, Logo in mehreren Breiten (siehe Theme.SetLogo)
	refresh = MEDIA .. "Refresh",     -- 64 x 64, Linien-Icon weiß (einfärbbar)
	chevron = MEDIA .. "Chevron",     -- 64 x 64, Pfeil nach unten, weiß (einfärbbar)
	expand = MEDIA .. "Expand",       -- 64 x 64, Fenster groß (Linien-Icon)
	collapse = MEDIA .. "Collapse",   -- 64 x 64, Fenster kompakt
	gear = MEDIA .. "Gear",           -- 64 x 64, Einstellungen
	filter = MEDIA .. "Filter",       -- 64 x 64, Filter-Dropdown
	plus = MEDIA .. "Plus",           -- 64 x 64, Anmelden
	check = MEDIA .. "Check",         -- 64 x 64, Angemeldet
	close = MEDIA .. "Close",         -- 64 x 64, Abmelden
	flags = MEDIA .. "Flags\\",       -- 64 x 64 je Flagge (DE, GB, ...), Flagge 60 x 40 mittig (Util.FlagMarkup)
}

-- Geist (SIL OFL) für KeyQueue-Texte, Geist Mono für Zahlen (Spalten fluchten);
-- Gruppen- und Spielernamen bleiben in der WoW-Schrift (alle Schriftsysteme)
Theme.font = {
	regular = MEDIA .. "Fonts\\Geist-Medium.ttf",
	bold = MEDIA .. "Fonts\\Geist-SemiBold.ttf",
	mono = MEDIA .. "Fonts\\GeistMono-Medium.ttf",
}

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ROUNDED_SLICE = 10
local SHADOW_SLICE, SHADOW_SPREAD = 24, 18

-- Alle Flächen deckend, damit sich abgerundete Ebenen nicht durchmischen
-- Palette "Graphite" (siehe Branding/README.md): flache, fast schwarze Flächen, feine Linien statt
-- Kästen, Weiß/Grau für Hierarchie und genau EINE Akzentfarbe (Blau) für Hauptaktion und Aktives.
-- Die Namen violet*/gold* sind historisch und zeigen beide auf den Akzent.
local ACCENT       = { 0.243, 0.416, 0.882, 1 } -- #3E6AE1 Hauptaktion, aktiver Reiter, Schalter
local ACCENT_HOVER = { 0.306, 0.475, 0.918, 1 } -- #4E79EA
local ACCENT_SOFT  = { 0.102, 0.114, 0.153, 1 } -- #1A1D27 aktive Pillen/Chips
local ACCENT_SOFT2 = { 0.133, 0.153, 0.220, 1 } -- #222738
local ACCENT_TEXT  = { 0.561, 0.690, 1.000, 1 } -- #8FB0FF Zahlen/Text in Akzentfarbe
Theme.color = {
	violet       = ACCENT,
	primaryHover = ACCENT_HOVER,
	onPrimary    = { 1.000, 1.000, 1.000, 1 },
	violetSoft   = ACCENT_SOFT,
	violetHover  = ACCENT_SOFT2,
	violetText   = ACCENT_TEXT,
	gold         = ACCENT_TEXT, -- früher Gold: Keystufe, Krone, Hervorhebungen
	goldHover    = ACCENT_HOVER,
	goldSoft     = ACCENT_SOFT,
	onGold       = { 1.000, 1.000, 1.000, 1 },
	bg           = { 0.055, 0.055, 0.063, 1 }, -- #0E0E10 Fenster
	dark         = { 0.039, 0.039, 0.043, 1 }, -- #0A0A0B Eingabefelder
	card         = { 0.055, 0.055, 0.063, 1 }, -- #0E0E10 Bereiche = Fenster (nur Linie drumherum)
	cardHover    = { 0.078, 0.078, 0.090, 1 }, -- #141417
	surface      = { 0.078, 0.078, 0.090, 1 }, -- #141417 Zeilen, Knöpfe
	surfaceHover = { 0.110, 0.110, 0.125, 1 }, -- #1C1C20
	border       = { 0.137, 0.137, 0.149, 1 }, -- #232326 Umrisse (Knöpfe, Pillen, Fenster)
	line         = { 0.110, 0.110, 0.122, 1 }, -- #1C1C1F Trennlinien zwischen Bereichen und Zeilen
	none         = { 0, 0, 0, 0 },
	text         = { 0.929, 0.929, 0.937, 1 }, -- #EDEDEF
	muted        = { 0.639, 0.639, 0.678, 1 }, -- #A3A3AD Sekundärtext (hell genug für kleine Größen)
	dim          = { 0.471, 0.471, 0.514, 1 }, -- #787883 Spaltenköpfe, Nebeninfos
	activeBorder = { 0.173, 0.208, 0.314, 1 }, -- #2C3550 Umriss aktiver Pillen/Chips
	disabled     = { 0.290, 0.290, 0.314, 1 },
}
Theme.color.violetDim = Theme.color.violetSoft -- ältere Bezeichnung

-- Statusfarben (Testergebnisse, Ergebnisse, Leaver)
Theme.status = {
	idle    = { 0.380, 0.380, 0.450, 1 },
	pending = Theme.color.violet,
	ok      = { 0.290, 0.820, 0.565, 1 }, -- #4AD190
	blocked = { 0.949, 0.396, 0.431, 1 }, -- #F2656E
	failed  = { 1.000, 0.584, 0.302, 1 },
	error   = { 1.000, 0.388, 0.620, 1 },
	unclear = { 1.000, 0.820, 0.302, 1 },
	skipped = { 0.500, 0.500, 0.580, 1 },
}

-- Rollenfarben (Bedeutung, kein Schmuck): Tank blau, Heiler grün, DPS rot
Theme.roleColor = {
	TANK    = Theme.color.violetText, -- #8FB0FF
	HEALER  = Theme.status.ok,        -- #4AD190
	DAMAGER = Theme.status.blocked,   -- #F2656E
}

local function ToHex(c)
	local function Byte(value)
		return math.floor(value * 255 + 0.5)
	end
	return ("ff%02x%02x%02x"):format(Byte(c[1]), Byte(c[2]), Byte(c[3]))
end

-- Text in einer Theme- oder Statusfarbe einfärben
function Theme.Colorize(text, key)
	local c = Theme.color[key] or Theme.status[key] or Theme.color.text
	return "|c" .. ToHex(c) .. tostring(text) .. "|r"
end

function Theme.Brand()
	return Theme.Colorize("KeyQueue", "text") -- wie die Wortmarke (eine Farbe)
end

-- Farbe deckend über eine Grundfläche mischen (z. B. getönte Etiketten)
function Theme.Mix(color, base, amount)
	return {
		color[1] * amount + base[1] * (1 - amount),
		color[2] * amount + base[2] * (1 - amount),
		color[3] * amount + base[3] * (1 - amount),
		1,
	}
end

-- 1 UI-Einheit kann bei kleiner UI-Skalierung unter 1 Bildschirmpixel liegen; dann rundet WoW
-- einzelne Kanten weg. Deshalb Konturen und Linien immer mindestens 1 echtes Pixel dick.
function Theme.PixelSize(region, units)
	local scale = region:GetEffectiveScale()
	if PixelUtil and PixelUtil.GetNearestPixelSize and scale and scale > 0 then
		return PixelUtil.GetNearestPixelSize(units or 1, scale, 1)
	end
	return units or 1
end

-- Genau n echte Bildschirmpixel in UI-Einheiten (z. B. für einen 2-Pixel-Rahmen)
function Theme.Pixels(region, n)
	local _, physicalHeight = GetPhysicalScreenSize()
	local factor = region:GetEffectiveScale() * (physicalHeight or 768) / 768
	return factor > 0 and n / factor or n
end

function Theme.PixelHeight(texture, units)
	texture:SetHeight(Theme.PixelSize(texture, units))
end

---------------------------------------------------------------------------
-- Schrift
---------------------------------------------------------------------------

-- Geist ist bei kleinen Größen sehr fein: alles eine Stufe größer, nichts unter 12 px (sonst wirkt
-- die Schrift bei kleiner UI-Skalierung pixelig)
local function ReadableSize(size)
	return math.max(11, size or 12) + 1
end
Theme.ReadableSize = ReadableSize

function Theme.SetFont(fontString, size, bold, flags)
	size = ReadableSize(size)
	local ok = fontString:SetFont(bold and Theme.font.bold or Theme.font.regular, size, flags or "")
	if ok == false then
		fontString:SetFont(STANDARD_TEXT_FONT, size, flags or "")
	end
end

-- Zahlen (RIO, iLvl, Zeiten) in Geist Mono
function Theme.SetMonoFont(fontString, size)
	size = ReadableSize(size)
	local ok = fontString:SetFont(Theme.font.mono, size, "")
	if ok == false then
		fontString:SetFont(STANDARD_TEXT_FONT, size, "")
	end
end

-- Für Text, den Spieler schreiben (Gruppennamen): WoW-Schrift kann alle Schriftsysteme
function Theme.SetGameFont(fontString, size)
	fontString:SetFont(STANDARD_TEXT_FONT, size or 12, "")
end

-- Leerer Platzhalter-Text als erster Text eines Frames: ingame blieb ein Text, der direkt nach einer
-- Größenabfrage mitten im Aufbau entstand, ohne Position (unsichtbar) - trifft es, dann diesen.
-- Für Zeilen, die erst beim Anzeigen angelegt werden (Listen, Bewertungsfenster).
function Theme.Primer(frame)
	local primer = frame:CreateFontString(nil, "OVERLAY")
	Theme.SetFont(primer, 12)
	primer:SetPoint("TOPLEFT")
	primer:SetText(" ")
	return primer
end

function Theme.Text(parent, size, colorKey, flags, layer, bold)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	size = size or 12
	Theme.SetFont(fs, size, bold or size >= 14, flags)
	fs:SetTextColor(unpack(Theme.color[colorKey or "text"] or Theme.color.text))
	fs:SetShadowOffset(0, 0)
	fs:SetJustifyH("LEFT")
	return fs
end

---------------------------------------------------------------------------
-- Flächen: abgerundet per 9-Slice, Kontur als zweite Fläche 1 Pixel darunter
---------------------------------------------------------------------------

local function RoundedTexture(frame, sublevel)
	local texture = frame:CreateTexture(nil, "BACKGROUND", nil, sublevel)
	if texture.SetTextureSliceMargins then
		texture:SetTexture(Theme.media.rounded)
		texture:SetTextureSliceMargins(ROUNDED_SLICE, ROUNDED_SLICE, ROUNDED_SLICE, ROUNDED_SLICE)
		if texture.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
			texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
		end
	else
		texture:SetTexture(WHITE) -- ohne 9-Slice: eckig, aber funktionsfähig
	end
	return texture
end

-- bg = Füllfarbe, border = Konturfarbe (none/nil-Alpha 0 = keine Kontur)
function Theme.SetSurface(frame, bg, border)
	if not rawget(frame, "kqFill") then
		frame.kqBorder = RoundedTexture(frame, -7)
		frame.kqBorder:SetAllPoints()
		frame.kqFill = RoundedTexture(frame, -6)
	end
	border = border or Theme.color.none
	local hasBorder = (border[4] or 1) > 0
	local edge = hasBorder and Theme.PixelSize(frame, 1) or 0
	if frame.kqEdge ~= edge then
		frame.kqEdge = edge
		frame.kqFill:ClearAllPoints()
		frame.kqFill:SetPoint("TOPLEFT", edge, -edge)
		frame.kqFill:SetPoint("BOTTOMRIGHT", -edge, edge)
	end
	frame.kqBorder:SetShown(hasBorder)
	frame.kqBorder:SetVertexColor(unpack(border))
	if bg then
		frame.kqBg = bg
	end
	bg = rawget(frame, "kqBg") or Theme.color.none
	local transparent = (bg[4] or 1) <= 0
	if transparent and hasBorder then
		-- nur Umriss: die Kontur-Fläche liegt unter der Füllung, also innen mit dem Untergrund
		-- (frame.kqBase, sonst Fensterfarbe) füllen - sonst wäre das ganze Feld randfarben
		frame.kqFill:SetVertexColor(unpack(rawget(frame, "kqBase") or Theme.color.bg))
		frame.kqFill:Show()
	else
		frame.kqFill:SetVertexColor(unpack(bg))
		frame.kqFill:SetShown(not transparent)
	end
end
Theme.ApplyBackdrop = Theme.SetSurface -- ältere Bezeichnung

-- Feine Trennlinie (1 echtes Pixel) an der Unter- oder Oberkante eines Frames
function Theme.Rule(frame, edge, inset)
	local rule = frame:CreateTexture(nil, "BORDER")
	edge = edge or "BOTTOM"
	rule:SetPoint(edge .. "LEFT", inset or 0, 0)
	rule:SetPoint(edge .. "RIGHT", -(inset or 0), 0)
	Theme.PixelHeight(rule, 1)
	rule:SetColorTexture(unpack(Theme.color.line))
	return rule
end

-- Bereich: flach, ohne Kasten - nur eine feine Linie an der Unterkante (card.rule, bei Bedarf ausblenden).
-- boxed = abgesetzte Fläche mit Umriss (Seitenfenster, Popups)
function Theme.Card(parent, boxed)
	local card = CreateFrame("Frame", nil, parent)
	if boxed then
		Theme.SetSurface(card, Theme.color.card, Theme.color.border)
	else
		card.rule = Theme.Rule(card)
	end
	return card
end

-- Weicher Schatten rund um ein Fenster ("schwebt" über der Spielwelt)
function Theme.DropShadow(frame)
	local shadow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	shadow:SetPoint("TOPLEFT", -SHADOW_SPREAD, SHADOW_SPREAD)
	shadow:SetPoint("BOTTOMRIGHT", SHADOW_SPREAD, -SHADOW_SPREAD)
	if shadow.SetTextureSliceMargins then
		shadow:SetTexture(Theme.media.shadow)
		shadow:SetTextureSliceMargins(SHADOW_SLICE, SHADOW_SLICE, SHADOW_SLICE, SHADOW_SLICE)
		if shadow.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
			shadow:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
		end
		shadow:SetVertexColor(0, 0, 0, 0.75)
	else
		shadow:Hide()
	end
	return shadow
end

---------------------------------------------------------------------------
-- Knöpfe
---------------------------------------------------------------------------

-- primary: Gold (eine Hauptaktion je Ansicht), secondary: neutrale Fläche,
-- accent: violett getönt (z. B. "Bewerben"), ghost: nur Text
local BUTTON_STYLES = {
	primary = {
		bg = Theme.color.violet, bgHover = Theme.color.primaryHover,
		text = Theme.color.onPrimary, bold = true,
	},
	-- "Gruppe gefunden": wie primary (eine Akzentfarbe für alles)
	gold = {
		bg = Theme.color.violet, bgHover = Theme.color.primaryHover,
		text = Theme.color.onPrimary, bold = true,
	},
	-- Umriss: ruhig, erst beim Überfahren hinterlegt
	secondary = {
		bg = Theme.color.none, bgHover = Theme.color.surfaceHover,
		border = Theme.color.border, text = Theme.color.text, bold = true,
	},
	-- Zeilen-Aktion (z. B. "Bewerben"): Umriss, beim Überfahren in der Akzentfarbe
	accent = {
		bg = Theme.color.none, bgHover = Theme.color.violet, border = Theme.color.border,
		text = Theme.color.text, textHover = Theme.color.onPrimary, bold = true,
	},
	ghost = {
		bg = Theme.color.none, bgHover = Theme.color.surface,
		text = Theme.color.muted, textHover = Theme.color.text,
	},
	-- eingeschaltet/aktiv (z. B. "Filter (2)" mit aktiven Filtern oder offenem Filter-Panel)
	active = {
		bg = Theme.color.violetSoft, bgHover = Theme.color.violetHover, border = Theme.color.activeBorder,
		text = Theme.color.violetText, textHover = Theme.color.text, bold = true,
	},
	-- "Beworben": Akzent-getönte Karte; beim Überfahren rot (Klick zieht die Bewerbung zurück)
	applied = {
		bg = Theme.color.violetSoft, bgHover = Theme.Mix(Theme.status.blocked, Theme.color.bg, 0.16),
		border = Theme.color.activeBorder, text = Theme.color.violetText, textHover = Theme.status.blocked, bold = true,
	},
}

local function UpdateButtonVisual(button)
	local style = BUTTON_STYLES[button.style] or BUTTON_STYLES.secondary
	if not button:IsEnabled() then
		Theme.SetSurface(button, button.style == "ghost" and Theme.color.none or Theme.color.surface)
		button.label:SetTextColor(unpack(Theme.color.disabled))
		return
	end
	Theme.SetSurface(button, button.hover and style.bgHover or style.bg, style.border)
	button.label:SetTextColor(unpack(button.hover and style.textHover or style.text))
end

function Theme.Button(parent, text, style, width, height)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width or 120, height or 28)
	button.style = style or "secondary"
	button.label = Theme.Text(button, 12, "text")
	button.label:SetPoint("CENTER")
	button.label:SetJustifyH("CENTER")
	button.label:SetText(text)
	local styleInfo = BUTTON_STYLES[button.style]
	Theme.SetFont(button.label, 12, styleInfo and styleInfo.bold)

	function button:SetLabel(value)
		self.label:SetText(value)
	end

	function button:SetStyle(value)
		self.style = value
		UpdateButtonVisual(self)
	end

	button:SetScript("OnEnter", function(self)
		self.hover = true
		UpdateButtonVisual(self)
	end)
	button:SetScript("OnLeave", function(self)
		self.hover = false
		UpdateButtonVisual(self)
	end)
	-- Versteckte Knöpfe bekommen kein OnLeave mehr: Hover beim Ausblenden zurücksetzen
	button:SetScript("OnHide", function(self)
		if self.hover then
			self.hover = false
			UpdateButtonVisual(self)
		end
	end)
	button:SetScript("OnEnable", UpdateButtonVisual)
	button:SetScript("OnDisable", UpdateButtonVisual)
	button:HookScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end)

	UpdateButtonVisual(button)
	return button
end

---------------------------------------------------------------------------
-- Chips (antippbare Kacheln statt Checkboxen)
---------------------------------------------------------------------------

local function UpdateChipVisual(chip)
	if chip.checked then
		Theme.SetSurface(chip, chip.hover and Theme.color.violetHover or Theme.color.violetSoft, Theme.color.activeBorder)
		chip.box:SetVertexColor(unpack(Theme.color.violetText))
		chip.label:SetTextColor(unpack(Theme.color.text))
	else
		Theme.SetSurface(chip, chip.hover and Theme.color.surfaceHover or Theme.color.none, Theme.color.border)
		chip.box:SetVertexColor(unpack(Theme.color.disabled))
		chip.label:SetTextColor(unpack(chip.hover and Theme.color.text or Theme.color.muted))
	end
end

function Theme.Chip(parent, text, checked, onToggle)
	local chip = CreateFrame("Button", nil, parent)
	chip:SetHeight(26)

	-- kleiner runder Punkt als Zustandsanzeige
	chip.box = chip:CreateTexture(nil, "ARTWORK")
	chip.box:SetSize(7, 7)
	chip.box:SetPoint("LEFT", 11, 0)
	chip.box:SetTexture(WHITE)
	Theme.MakeRound(chip.box)

	chip.label = Theme.Text(chip, 11)
	chip.label:SetPoint("LEFT", chip.box, "RIGHT", 7, 0)
	chip.label:SetText(text)
	chip:SetWidth(chip.label:GetStringWidth() + 38)

	function chip:SetChecked(value)
		self.checked = value and true or false
		UpdateChipVisual(self)
	end

	function chip:GetChecked()
		return self.checked
	end

	chip:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		if onToggle then
			onToggle(self.checked)
		end
	end)
	chip:SetScript("OnEnter", function(self)
		self.hover = true
		UpdateChipVisual(self)
	end)
	chip:SetScript("OnLeave", function(self)
		self.hover = false
		UpdateChipVisual(self)
	end)

	chip:SetChecked(checked)
	return chip
end

---------------------------------------------------------------------------
-- Eingabefeld
---------------------------------------------------------------------------

function Theme.EditBox(parent, width, placeholder)
	local edit = CreateFrame("EditBox", nil, parent)
	edit:SetSize(width or 160, 28)
	Theme.SetFont(edit, 12)
	edit:SetTextColor(unpack(Theme.color.text))
	edit:SetTextInsets(10, 10, 0, 0)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(64)
	Theme.SetSurface(edit, Theme.color.dark, Theme.color.border)

	edit.placeholder = Theme.Text(edit, 12, "disabled")
	edit.placeholder:SetPoint("LEFT", 10, 0)
	edit.placeholder:SetText(placeholder or "")

	local function UpdatePlaceholder(self)
		self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
	end

	edit:SetScript("OnEditFocusGained", function(self)
		Theme.SetSurface(self, Theme.color.dark, Theme.color.violet)
		UpdatePlaceholder(self)
	end)
	edit:SetScript("OnEditFocusLost", function(self)
		Theme.SetSurface(self, Theme.color.dark, Theme.color.border)
		UpdatePlaceholder(self)
	end)
	edit:SetScript("OnTextChanged", UpdatePlaceholder)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	edit:SetScript("OnEnterPressed", edit.ClearFocus)

	return edit
end

-- Status-Knopf: zeigt Testergebnis farbig an und startet beim Klick den Test (Phase-0-Fenster)
function Theme.StatusButton(parent, width, height)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(width, height)
	Theme.SetSurface(button, Theme.color.dark, Theme.color.border)

	button.dot = button:CreateTexture(nil, "ARTWORK")
	button.dot:SetSize(8, 8)
	button.dot:SetPoint("LEFT", 10, 0)
	button.dot:SetTexture(WHITE)
	Theme.MakeRound(button.dot)

	button.label = Theme.Text(button, 11)
	button.label:SetPoint("LEFT", button.dot, "RIGHT", 7, 0)
	button.label:SetPoint("RIGHT", -8, 0)
	button.label:SetWordWrap(false)

	local pulse = button.dot:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.2)
	fade:SetDuration(0.45)
	fade:SetSmoothing("IN_OUT")

	function button:SetStatus(status, text)
		local color = Theme.status[status] or Theme.status.idle
		self.status = status
		self.dot:SetVertexColor(unpack(color))
		Theme.SetSurface(self, self.hover and Theme.color.cardHover or Theme.color.dark,
			status == "idle" and Theme.color.border or color)
		self.label:SetText(text)
		self.label:SetTextColor(unpack(status == "idle" and Theme.color.muted or Theme.color.text))
		if status == "pending" then
			pulse:Play()
		else
			pulse:Stop()
			self.dot:SetAlpha(1)
		end
	end

	button:SetScript("OnEnter", function(self)
		self.hover = true
		self:SetStatus(self.status, self.label:GetText())
	end)
	button:SetScript("OnLeave", function(self)
		self.hover = false
		self:SetStatus(self.status, self.label:GetText())
		GameTooltip:Hide()
	end)

	button:SetStatus("idle", "")
	return button
end

-- Scrollbereich mit Mausrad und schmalem violetten Scroll-Indikator
function Theme.ScrollArea(parent, step)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)

	local track = scroll:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("TOPRIGHT")
	track:SetPoint("BOTTOMRIGHT")
	track:SetWidth(4)
	track:SetColorTexture(unpack(Theme.color.surface))

	local thumb = scroll:CreateTexture(nil, "ARTWORK")
	thumb:SetWidth(4)
	thumb:SetColorTexture(unpack(Theme.color.violet))

	function scroll:UpdateThumb()
		local range = self:GetVerticalScrollRange()
		local height = self:GetHeight()
		if range <= 0 or height <= 0 then
			track:Hide()
			thumb:Hide()
			return
		end
		track:Show()
		thumb:Show()
		local thumbHeight = math.max(24, height * height / (height + range))
		local offset = (height - thumbHeight) * (self:GetVerticalScroll() / range)
		thumb:SetHeight(thumbHeight)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -offset)
	end

	function scroll:ScrollBy(delta)
		local range = self:GetVerticalScrollRange()
		local value = math.max(0, math.min(range, self:GetVerticalScroll() + delta))
		self:SetVerticalScroll(value)
		self:UpdateThumb()
	end

	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:ScrollBy(-delta * (step or 48))
	end)
	scroll:SetScript("OnScrollRangeChanged", function(self)
		self:ScrollBy(0)
	end)
	scroll:SetScript("OnSizeChanged", function(self, width)
		child:SetWidth(width - 12)
		self:UpdateThumb()
	end)

	return scroll, child
end

-- Fenster im KeyQueue-Look: abgerundet, schwebend mit Schatten, verschiebbar, ESC schließt, Fade-in
function Theme.Window(width, height, store)
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(width, height)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetScale(store.scale or 1)
	Theme.DropShadow(frame)
	Theme.SetSurface(frame, Theme.color.bg, Theme.color.border)

	-- Fenster immer mit der linken oberen Ecke auf einem ganzen Bildschirmpixel: so liegen alle
	-- Inhalte (Symbole, Linien, Text) auf dem Pixelraster statt dazwischen
	function frame:SnapToPixels()
		local left, top = self:GetLeft(), self:GetTop()
		if not (left and top) then
			return
		end
		local x, y = Theme.PixelSize(self, left), Theme.PixelSize(self, top)
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
		-- angeheftet neben Blizzard-Fenstern (MainFrame:DockBesidePanels): eigenen Platz nicht überschreiben
		if not rawget(self, "docked") then
			store.point, store.relPoint, store.x, store.y = "TOPLEFT", "BOTTOMLEFT", x, y
		end
	end

	function frame:RestorePosition()
		self:ClearAllPoints()
		if store.point then
			self:SetPoint(store.point, UIParent, store.relPoint, store.x, store.y)
		else
			self:SetPoint("CENTER")
		end
		self:SnapToPixels()
	end
	frame:RestorePosition()

	-- Kopfzeile 48 px: Logo links, Reiter daneben (setzt MainFrame), rechts Version und Schließen
	local header = CreateFrame("Frame", nil, frame)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(48)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function()
		frame.docked = nil -- selbst verschoben: das ist jetzt der eigene Platz
		frame:StartMoving()
	end)
	header:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		store.point, store.relPoint, store.x, store.y = point, relPoint, x, y
		frame:SnapToPixels()
	end)
	frame.header = header

	frame.logo = header:CreateTexture(nil, "ARTWORK")
	frame.logo:SetPoint("LEFT", 16, 0)
	Theme.SetLogo(frame.logo, 120) -- scharf in der passenden Pixelgröße

	frame.subtitle = Theme.Text(header, 12, "muted")
	frame.subtitle:SetPoint("LEFT", frame.logo, "RIGHT", 6, -2)

	local close = Theme.Button(header, "\195\151", "ghost", 28, 28) -- ×
	Theme.SetFont(close.label, 16)
	close:SetPoint("RIGHT", -10, 0)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)
	frame.close = close

	frame.info = Theme.Text(header, 11, "dim")
	frame.info:SetPoint("RIGHT", close, "LEFT", -10, 0)

	local separator = frame:CreateTexture(nil, "ARTWORK")
	separator:SetPoint("TOPLEFT", 1, -48)
	separator:SetPoint("TOPRIGHT", -1, -48)
	Theme.PixelHeight(separator, 1)
	separator:SetColorTexture(unpack(Theme.color.border))

	-- ESC schließt das Fenster, ohne eine globale UISpecialFrames-Eintragung
	frame:EnableKeyboard(true)
	if not InCombatLockdown() then
		frame:SetPropagateKeyboardInput(true)
	end
	frame:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then
			return
		end
		if key == "ESCAPE" then
			self:SetPropagateKeyboardInput(false)
			self:Hide()
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)

	local fadeIn = frame:CreateAnimationGroup()
	local alpha = fadeIn:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.18)
	alpha:SetSmoothing("OUT")

	frame:SetScript("OnShow", function(self)
		self:SnapToPixels()
		fadeIn:Play()
		if not InCombatLockdown() then
			self:SetPropagateKeyboardInput(true)
		end
	end)

	frame:Hide()
	return frame
end

---------------------------------------------------------------------------
-- Weitere Bausteine für Hauptfenster und Tabs
---------------------------------------------------------------------------

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

function Theme.MakeRound(texture)
	local mask = texture:GetParent():CreateMaskTexture()
	mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
end

-- Reiter als reiner Text in der Kopfzeile: aktiv = heller Text mit Akzent-Unterstrich
function Theme.Tab(parent, text)
	local tab = CreateFrame("Button", nil, parent)
	tab.label = Theme.Text(tab, 13, "muted", nil, nil, true)
	tab.label:SetPoint("CENTER", 0, 0)
	tab.label:SetJustifyH("CENTER")
	tab.label:SetText(text)
	tab:SetSize(tab.label:GetStringWidth() + 24, 48)

	-- Beschriftung wechseln (z. B. kurze Namen im kompakten Fenster); Breite folgt dem Text
	function tab:SetLabel(value)
		self.label:SetText(value)
		self:SetWidth(self.label:GetStringWidth() + 24)
	end

	-- Unterstrich liegt genau auf der Trennlinie der Kopfzeile
	tab.line = tab:CreateTexture(nil, "OVERLAY")
	tab.line:SetPoint("BOTTOMLEFT", 12, 0)
	tab.line:SetPoint("BOTTOMRIGHT", -12, 0)
	Theme.PixelHeight(tab.line, 2)
	tab.line:SetColorTexture(unpack(Theme.color.violet))

	local function Refresh(self)
		local color = Theme.color.muted
		if not self:IsEnabled() then
			color = Theme.color.disabled
		elseif self.active or self.hover then
			color = Theme.color.text
		end
		self.label:SetTextColor(unpack(color))
		self.line:SetShown(self.active and true or false)
	end

	function tab:SetActive(active)
		self.active = active
		Refresh(self)
	end

	tab:SetScript("OnEnter", function(self)
		self.hover = true
		Refresh(self)
	end)
	tab:SetScript("OnLeave", function(self)
		self.hover = false
		Refresh(self)
		GameTooltip:Hide()
	end)
	tab:SetScript("OnEnable", Refresh)
	tab:SetScript("OnDisable", Refresh)
	Refresh(tab)
	return tab
end

-- Zähler mit - und +, z. B. Anzahl gesuchter DPS
function Theme.Stepper(parent, text, minValue, maxValue, value, onChange)
	local stepper = CreateFrame("Frame", nil, parent)
	stepper:SetHeight(26)

	stepper.label = Theme.Text(stepper, 11)
	stepper.label:SetPoint("LEFT", 10, 0)
	stepper.label:SetText(text)

	local minus = Theme.Button(stepper, "-", "ghost", 22, 22)
	minus:SetPoint("LEFT", stepper.label, "RIGHT", 8, 0)
	stepper.value = Theme.Text(stepper, 12, "violetText")
	stepper.value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
	stepper.value:SetWidth(18)
	stepper.value:SetJustifyH("CENTER")
	local plus = Theme.Button(stepper, "+", "ghost", 22, 22)
	plus:SetPoint("LEFT", stepper.value, "RIGHT", 2, 0)
	stepper:SetWidth(stepper.label:GetStringWidth() + 90)

	function stepper:SetValue(newValue)
		self.current = math.max(minValue, math.min(maxValue, newValue))
		self.value:SetText(self.current)
		Theme.SetSurface(self, self.current > 0 and Theme.color.violetSoft or Theme.color.surface)
		self.label:SetTextColor(unpack(self.current > 0 and Theme.color.text or Theme.color.muted))
	end

	local function Step(delta)
		local before = stepper.current
		stepper:SetValue(before + delta)
		if stepper.current ~= before and onChange then
			onChange(stepper.current)
		end
	end
	minus:SetScript("OnClick", function()
		Step(-1)
	end)
	plus:SetScript("OnClick", function()
		Step(1)
	end)

	stepper:SetValue(value or minValue)
	return stepper
end

-- Auswahlliste im KeyQueue-Look (z. B. Profile)
function Theme.Dropdown(parent, width, getOptions, onSelect)
	local dropdown = Theme.Button(parent, "", "secondary", width, 26)
	dropdown.label:ClearAllPoints()
	dropdown.label:SetPoint("LEFT", 10, 0)
	dropdown.label:SetPoint("RIGHT", -24, 0)
	dropdown.label:SetJustifyH("LEFT")
	dropdown.label:SetWordWrap(false)

	local arrow = Theme.Text(dropdown, 10, "muted")
	arrow:SetPoint("RIGHT", -10, 0)
	arrow:SetText("v")

	local menu = CreateFrame("Frame", nil, dropdown)
	menu:SetFrameStrata("DIALOG")
	menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -4)
	menu:SetWidth(width)
	menu:EnableMouse(true)
	Theme.DropShadow(menu)
	Theme.SetSurface(menu, Theme.color.card, Theme.color.border)
	menu:Hide()
	menu.items = {}

	function dropdown:SetValue(text)
		self.label:SetText(text)
	end

	local function Close()
		menu:Hide()
	end

	dropdown:SetScript("OnClick", function()
		if menu:IsShown() then
			return Close()
		end
		local options = getOptions()
		for index, option in ipairs(options) do
			local item = menu.items[index]
			if not item then
				item = Theme.Button(menu, "", "ghost", width - 4, 22)
				item.label:ClearAllPoints()
				item.label:SetPoint("LEFT", 8, 0)
				item:SetPoint("TOPLEFT", 2, -2 - (index - 1) * 22)
				menu.items[index] = item
			end
			item:SetLabel(option.text)
			item:SetScript("OnClick", function()
				Close()
				onSelect(option.value)
			end)
			item:Show()
		end
		for index = #options + 1, #menu.items do
			menu.items[index]:Hide()
		end
		menu:SetHeight(#options * 22 + 4)
		menu:Show()
	end)
	dropdown:HookScript("OnHide", Close)
	return dropdown
end

-- Kleines farbiges Etikett, z. B. "KQ"
function Theme.Badge(parent, text, colorKey)
	local badge = CreateFrame("Frame", nil, parent)
	badge.label = Theme.Text(badge, 9, "text", nil, nil, true)
	badge.label:SetPoint("CENTER", 0, 0)
	badge.label:SetJustifyH("CENTER")
	-- Farbe: Paletten- oder Status-Farbe (z. B. "ok" für Grün); Fläche = Farbe leicht auf dunklem Grund
	function badge:SetColor(key)
		local color = Theme.color[key] or Theme.status[key] or Theme.color.gold
		Theme.SetSurface(self, Theme.Mix(color, Theme.color.surface, 0.22))
		self.label:SetTextColor(unpack(color))
	end
	badge:SetColor(colorKey or "gold")
	function badge:SetText(value)
		self.label:SetText(value)
		self:SetSize(self.label:GetStringWidth() + 12, 16)
	end
	badge:SetText(text)
	return badge
end

-- Pulsierender Queue-Ring mit Text in der Mitte
function Theme.Ring(parent, size)
	local ring = CreateFrame("Frame", nil, parent)
	ring:SetSize(size, size)

	local outer = ring:CreateTexture(nil, "BACKGROUND")
	outer:SetAllPoints()
	outer:SetColorTexture(unpack(Theme.color.violet))
	Theme.MakeRound(outer)
	ring.outer = outer

	local inner = ring:CreateTexture(nil, "BORDER")
	inner:SetPoint("CENTER")
	inner:SetSize(size - 6, size - 6) -- Ring 3 px breit
	inner:SetColorTexture(unpack(Theme.color.bg))
	Theme.MakeRound(inner)

	ring.text = Theme.Text(ring, 14, "text")
	ring.text:SetPoint("CENTER")
	ring.text:SetJustifyH("CENTER")

	local pulse = outer:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.8)
	fade:SetSmoothing("IN_OUT")

	-- colorKey: violet (Queue), gold (gefunden), muted (bereit)
	-- colorKey: Name aus Theme.color oder direkt eine Farbe { r, g, b }
	function ring:SetMode(colorKey, animate)
		local color = type(colorKey) == "table" and colorKey or Theme.color[colorKey] or Theme.color.violet
		outer:SetColorTexture(unpack(color))
		if animate then
			pulse:Play()
		else
			pulse:Stop()
			outer:SetAlpha(1)
		end
	end

	return ring
end

-- Ordnet Elemente nebeneinander an und bricht bei Bedarf um; gibt die Gesamthöhe zurück
function Theme.Flow(items, parent, width, x, y, gap, rowHeight)
	local cursorX, cursorY = 0, 0
	for _, item in ipairs(items) do
		local itemWidth = item:GetWidth()
		if cursorX > 0 and cursorX + itemWidth > width then
			cursorX = 0
			cursorY = cursorY + rowHeight + gap
		end
		item:ClearAllPoints()
		item:SetPoint("TOPLEFT", parent, "TOPLEFT", x + cursorX, -(y + cursorY))
		cursorX = cursorX + itemWidth + gap
	end
	return cursorY + rowHeight
end

-- Chip, der bei jedem Klick zur nächsten Option springt (z. B. egal -> vorhanden -> fehlt).
-- options = { { value = ..., text = ... }, ... }; die erste Option gilt als "aus".
function Theme.CycleChip(parent, options, value, onChange)
	local chip = Theme.Chip(parent, options[1].text, false)
	local widest = 0
	for _, option in ipairs(options) do
		chip.label:SetText(option.text)
		widest = math.max(widest, chip.label:GetStringWidth())
	end
	chip:SetWidth(widest + 36)

	function chip:SetValue(newValue)
		self.index = 1
		for index, option in ipairs(options) do
			if option.value == newValue then
				self.index = index
			end
		end
		self.label:SetText(options[self.index].text)
		self:SetChecked(self.index > 1)
	end

	chip:SetScript("OnClick", function(self)
		self:SetValue(options[self.index % #options + 1].value)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		if onChange then
			onChange(options[self.index].value)
		end
	end)

	chip:SetValue(value)
	return chip
end

-- Aufklapp-Panel (z. B. Ausdruck-Baukasten, Menü des Status-Symbols); ein Klick daneben schließt es
function Theme.Popover(root, width)
	local catcher = CreateFrame("Button", nil, root)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("DIALOG")
	catcher:RegisterForClicks("AnyDown")
	catcher:Hide()

	local popover = CreateFrame("Frame", nil, root)
	popover:SetWidth(width)
	popover:SetFrameStrata("DIALOG")
	popover:SetFrameLevel(catcher:GetFrameLevel() + 10)
	popover:SetClampedToScreen(true)
	popover:EnableMouse(true)
	Theme.DropShadow(popover)
	Theme.SetSurface(popover, Theme.color.card, Theme.color.border)
	popover:Hide()

	-- onClose läuft nur bei Schließen per Klick (Hardware-Event: darf z. B. neu suchen)
	catcher:SetScript("OnClick", function()
		popover:Hide()
		if popover.onClose then
			popover.onClose()
		end
	end)
	popover:SetScript("OnShow", function()
		catcher:Show()
	end)
	popover:SetScript("OnHide", function()
		catcher:Hide()
	end)

	return popover
end

---------------------------------------------------------------------------
-- Hero-Bausteine (Suchen + Gruppe erstellen)
---------------------------------------------------------------------------

-- Hauptknopf rechts, darunter eine Zeile mit Optionen: left = links bündig unter dem Knopf (z. B.
-- Auto-Bewerben), right = rechts bündig, von rechts nach links (versteckte werden übersprungen).
-- Knopf + Zeile sitzen zusammen vertikal mittig; der Textblock endet links neben dem Knopf.
function Theme.LayoutHeroActions(card, box, main, left, right, compact)
	local rowHeight = 28
	if compact then
		-- kompakter Modus: oben Avatar (verkleinert) + Textblock, darunter der Knopf in voller Breite,
		-- darunter die Optionen-Zeile
		local anchor = rawget(box, "anchor")
		local top = 12 + 40 + 10
		box:ClearAllPoints()
		if anchor and anchor:IsShown() then
			box:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
			top = 10 + (anchor:GetHeight() or 46) * (anchor:GetScale() or 1) + 12
		else
			box:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -12)
		end
		box:SetPoint("RIGHT", card, "RIGHT", 0, 0)
		-- eine Zeile: Hauptknopf, rechts daneben die übrigen Knöpfe (z. B. Queue verlassen, Aktualisieren)
		local previous
		for _, control in ipairs(right or {}) do
			if control:IsShown() then
				control:ClearAllPoints()
				control:SetHeight(main:GetHeight())
				if previous then
					control:SetPoint("TOPRIGHT", previous, "TOPLEFT", -6, 0)
				else
					control:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -top)
				end
				previous = control
			end
		end
		main:ClearAllPoints()
		main:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -top)
		if previous then
			main:SetPoint("TOPRIGHT", previous, "TOPLEFT", -6, 0)
		else
			main:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -top)
		end
		if main.sub then
			main.sub:SetWidth(math.max(100, (main:GetWidth() or 300) - 16))
		end
		return
	end
	-- Knopf so breit, dass die Zeile darunter immer passt - auch mit allen Optionen sichtbar
	-- (gleichbleibende Breite, damit nichts springt, wenn z. B. "Queue verlassen" dazukommt)
	local needed = left and (left:GetWidth() + 16) or 0
	for index, control in ipairs(right or {}) do
		needed = needed + control:GetWidth() + (index > 1 and 6 or 0)
	end
	main:SetWidth(math.max(220, math.ceil(needed)))
	if main.sub then
		main.sub:SetWidth(main:GetWidth() - 16)
	end
	main:ClearAllPoints()
	main:SetPoint("RIGHT", card, "RIGHT", 0, (rowHeight + 8) / 2)
	box:ClearAllPoints()
	box:SetPoint("LEFT", rawget(box, "anchor") or card, "RIGHT", 14, 0)
	if left then
		left:ClearAllPoints()
		left:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -8)
		left:SetHeight(rowHeight)
	end
	local previous
	for _, control in ipairs(right or {}) do
		if control:IsShown() then
			control:ClearAllPoints()
			if previous then
				control:SetPoint("RIGHT", previous, "LEFT", -6, 0)
			else
				control:SetPoint("TOPRIGHT", main, "BOTTOMRIGHT", 0, -8)
			end
			control:SetHeight(rowHeight)
			previous = control
		end
	end
	box:SetPoint("RIGHT", main, "LEFT", -24, 0)
end

-- Textblock neben dem Ring: Titel (+ Zusatz rechts daneben), Infozeile, optionale Statuszeile.
-- Der Block wird vertikal mittig zur Karte gesetzt, egal wie viele Zeilen sichtbar sind.
function Theme.HeroText(card, ring)
	local box = CreateFrame("Frame", nil, card)
	box:SetPoint("LEFT", ring, "RIGHT", 14, 0)
	box:SetPoint("RIGHT", card, "RIGHT", -300, 0)
	box:SetHeight(40)
	box.anchor = ring

	box.title = Theme.Text(box, 15, nil, nil, nil, true)
	box.title:SetPoint("TOPLEFT")
	box.title:SetWordWrap(false)
	box.extra = Theme.Text(box, 12, "dim")
	box.extra:SetPoint("BOTTOMLEFT", box.title, "BOTTOMRIGHT", 8, 1)
	box.extra:SetWordWrap(false)

	box.info = Theme.Text(box, 12, "muted")
	box.info:SetPoint("TOPLEFT", box.title, "BOTTOMLEFT", 0, -7)
	box.info:SetPoint("RIGHT")
	box.info:SetJustifyH("LEFT")
	box.info:SetWordWrap(false)

	box.status = Theme.Text(box, 12)
	box.status:SetPoint("TOPLEFT", box.info, "BOTTOMLEFT", 0, -5)
	box.status:SetPoint("RIGHT")
	box.status:SetJustifyH("LEFT")
	box.status:SetWordWrap(false)

	function box:Set(title, extra, info, status)
		local maxWidth = (self:GetWidth() or 0) > 0 and self:GetWidth() or 330
		self.title:SetText(title or "")
		self.extra:SetText(extra or "")
		local titleWidth = math.min((self.title:GetUnboundedStringWidth() or 0) + 2, maxWidth)
		self.title:SetWidth(titleWidth)
		self.extra:SetWidth(math.max(1, maxWidth - titleWidth - 8))
		self.extra:SetShown((extra or "") ~= "" and maxWidth - titleWidth > 40)
		-- kompakt (box.compact): nur zwei Zeilen - läuft etwas, ersetzt der Status die Infozeile
		if rawget(self, "compact") and (status or "") ~= "" then
			info, status = status, ""
		end
		self.info:SetText(info or "")
		self.status:SetText(status or "")
		self.status:SetShown((status or "") ~= "")

		local height = 18 + 7 + 14
		if self.status:IsShown() then
			height = height + 5 + 14
		end
		self:SetHeight(height)
	end
	return box
end

-- Segment-Umschalter: mehrere Optionen nebeneinander in einer Fläche, genau eine ist gewählt
-- choices = { { value = ..., text = ... }, ... }; onSelect(value)
function Theme.Segmented(parent, choices, onSelect)
	local control = CreateFrame("Frame", nil, parent)
	control:SetHeight(30)
	Theme.SetSurface(control, Theme.color.bg, Theme.color.border)
	control.buttons = {}
	local previous
	for _, choice in ipairs(choices) do
		local button = CreateFrame("Button", nil, control)
		button:SetHeight(24)
		button.label = Theme.Text(button, 12, "muted")
		button.label:SetPoint("CENTER")
		button.label:SetJustifyH("CENTER")
		button.value = choice.value
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
		else
			button:SetPoint("LEFT", 3, 0)
		end
		button:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			control:SetValue(self.value)
			if onSelect then
				onSelect(self.value)
			end
		end)
		button:SetScript("OnEnter", function(self)
			if not self.selected then
				self.label:SetTextColor(unpack(Theme.color.text))
			end
		end)
		button:SetScript("OnLeave", function(self)
			if not self.selected then
				self.label:SetTextColor(unpack(Theme.color.muted))
			end
		end)
		table.insert(control.buttons, button)
		previous = button
	end

	-- Beschriftungen setzen (auch später, z. B. Sprachnamen); Breite folgt dem Text
	function control:SetTexts(texts)
		local width = 6 + 2 * (#self.buttons - 1)
		for index, button in ipairs(self.buttons) do
			button.label:SetText(texts[index] or "")
			button:SetWidth(button.label:GetStringWidth() + 24)
			width = width + button:GetWidth()
		end
		self:SetWidth(width)
	end

	function control:SetValue(value)
		for _, button in ipairs(self.buttons) do
			button.selected = button.value == value
			Theme.SetSurface(button, button.selected and Theme.color.violetSoft or Theme.color.none,
				button.selected and Theme.color.activeBorder or nil)
			button.label:SetTextColor(unpack(button.selected and Theme.color.text or Theme.color.muted))
		end
	end

	local texts = {}
	for index, choice in ipairs(choices) do
		texts[index] = choice.text
	end
	control:SetTexts(texts)
	return control
end

-- Quadratischer Knopf nur mit Linien-Icon (Fensterkopf: groß/kompakt, Einstellungen)
function Theme.IconButton(parent, icon, size, tooltip)
	local button = Theme.Button(parent, "", "ghost", size or 28, size or 28)
	button.icon = button:CreateTexture(nil, "OVERLAY")
	button.icon:SetSize(14, 14)
	button.icon:SetPoint("CENTER")
	button.icon:SetVertexColor(unpack(Theme.color.muted))
	function button:SetIcon(path, text)
		self.icon:SetTexture(path, nil, nil, "TRILINEAR")
		self.tooltip = text
	end
	button:SetIcon(icon, tooltip)
	button:HookScript("OnEnter", function(self)
		self.icon:SetVertexColor(unpack(Theme.color.text))
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(self.tooltip, 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	button:HookScript("OnLeave", function(self)
		self.icon:SetVertexColor(unpack(Theme.color.muted))
		GameTooltip:Hide()
	end)
	return button
end

-- Schalter (Ein/Aus) mit Beschriftung rechts daneben; gleiche Schnittstelle wie Theme.Chip
function Theme.Switch(parent, text, checked, onToggle)
	local switch = CreateFrame("Button", nil, parent)
	switch:SetHeight(32)

	-- Spur als Pille: zwei Kreise und ein Rechteck dazwischen
	local track = {}
	local left = switch:CreateTexture(nil, "ARTWORK")
	left:SetSize(16, 16)
	left:SetPoint("LEFT", 0, 0)
	local right = switch:CreateTexture(nil, "ARTWORK")
	right:SetSize(16, 16)
	right:SetPoint("LEFT", 12, 0)
	for _, part in ipairs({ left, right }) do
		part:SetTexture(Theme.media.circle, nil, nil, "TRILINEAR")
		table.insert(track, part)
	end
	local middle = switch:CreateTexture(nil, "ARTWORK")
	middle:SetSize(12, 16)
	middle:SetPoint("LEFT", 8, 0)
	middle:SetTexture(WHITE)
	table.insert(track, middle)

	local knob = switch:CreateTexture(nil, "OVERLAY")
	knob:SetSize(12, 12)
	knob:SetTexture(Theme.media.circle, nil, nil, "TRILINEAR")

	switch.label = Theme.Text(switch, 12, "muted")
	switch.label:SetPoint("LEFT", 38, 0)
	switch.label:SetText(text)
	switch:SetWidth(38 + switch.label:GetStringWidth() + 2)

	local function Refresh(self)
		-- aus: deutlich sichtbare graue Spur mit hellem Knopf; an: Akzent mit weißem Knopf
		local color = self.checked and Theme.color.violet
			or (self.hover and { 0.290, 0.290, 0.322, 1 } or { 0.227, 0.227, 0.259, 1 }) -- #4A4A52 / #3A3A42
		for _, part in ipairs(track) do
			part:SetVertexColor(unpack(color))
		end
		knob:ClearAllPoints()
		knob:SetPoint("CENTER", left, "CENTER", self.checked and 12 or 0, 0)
		knob:SetVertexColor(1, 1, 1, self.checked and 1 or 0.85)
		self.label:SetTextColor(unpack((self.checked or self.hover) and Theme.color.text or Theme.color.muted))
	end

	function switch:SetChecked(value)
		self.checked = value and true or false
		Refresh(self)
	end

	function switch:GetChecked()
		return self.checked
	end

	switch:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		PlaySound(self.checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		if onToggle then
			onToggle(self.checked)
		end
	end)
	switch:SetScript("OnEnter", function(self)
		self.hover = true
		Refresh(self)
	end)
	switch:SetScript("OnLeave", function(self)
		self.hover = false
		Refresh(self)
	end)

	switch:SetChecked(checked)
	return switch
end

---------------------------------------------------------------------------
-- Scharfes Logo: aus LogoSheet.tga die Größe nehmen, die den tatsächlichen Bildschirm-Pixeln am
-- nächsten kommt (Breite, Höhe, y im Sheet; erzeugt von Branding/build.cjs)
---------------------------------------------------------------------------

Theme.logoSheet = {
	{ 96, 24, 0 }, { 112, 28, 26 }, { 128, 32, 56 }, { 144, 36, 90 }, { 160, 40, 128 },
	{ 176, 44, 170 }, { 192, 48, 216 }, { 216, 54, 266 }, { 240, 60, 322 }, { 288, 72, 384 },
}

local function ApplyLogo(texture)
	local width = texture.logoWidth
	local _, physicalHeight = GetPhysicalScreenSize()
	local pixels = width * texture:GetEffectiveScale() * ((physicalHeight or 768) / 768)
	local best
	for _, entry in ipairs(Theme.logoSheet) do
		if not best or math.abs(entry[1] - pixels) < math.abs(best[1] - pixels) then
			best = entry
		end
	end
	texture:SetTexture(Theme.media.logoSheet, nil, nil, "LINEAR")
	texture:SetTexCoord(0, best[1] / 512, best[3] / 512, (best[3] + best[2]) / 512)
end

function Theme.SetLogo(texture, width)
	texture.logoWidth = width
	texture:SetSize(width, width / 4)
	ApplyLogo(texture)
	-- Skalierung kann sich ändern (Fenstergröße, UI-Skalierung): beim Anzeigen neu wählen
	local parent = texture:GetParent()
	if parent and parent.HookScript then
		parent:HookScript("OnShow", function()
			ApplyLogo(texture)
		end)
		parent:HookScript("OnSizeChanged", function()
			ApplyLogo(texture)
		end)
	end
end
