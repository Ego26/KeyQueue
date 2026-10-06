-- KeyQueue Core: Init, Events, Slash-Befehl /kq
local ADDON_NAME, ns = ...

local KeyQueue = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0", "AceTimer-3.0")
_G.KeyQueue = KeyQueue -- einzige globale Variable des Addons

ns.addon = KeyQueue

-- Entwickler-Build: Werkzeuge nur zum Testen (z. B. Vorschau im Tab "Erstellen"). Der Packager
-- (.pkgmeta, CurseForge/Wago) kommentiert den Block beim Paketbau aus - im Release ist ns.DEV nil.
-- Lokal (scripts/deploy.ps1) bleibt er aktiv.
--@debug@
ns.DEV = true
--@end-debug@

---------------------------------------------------------------------------
-- Sprache: Deutsch und Englisch sind immer geladen; aktiv ist, was unter Einstellungen -> Sprache
-- steht ("auto" = Spielsprache wie bei anderen Addons). Alle Dateien halten ns.L - die Tabelle
-- schlägt jeden Text in der aktiven Sprache nach, fehlende auf Englisch.
---------------------------------------------------------------------------

KeyQueue.LANGUAGES = { "auto", "deDE", "enUS" }

local locales = ns.locales
local activeLocale = locales.enUS

ns.L = setmetatable({}, {
	__index = function(_, key)
		return activeLocale[key] or locales.enUS[key] or key
	end,
})

function ns.LocaleHas(key)
	return activeLocale[key] ~= nil or locales.enUS[key] ~= nil
end

-- Spielsprache = Sprache des WoW-Clients (GetLocale)
function KeyQueue:ResolveLanguage(choice)
	-- "Spielsprache" = Sprache des WoW-Clients. GAME_LOCALE (vom Addon "AddonLocale" gesetzt, um
	-- Addons umzustellen) zählt hier nicht - wer eine andere Sprache will, wählt sie direkt.
	if choice == "auto" or not locales[choice] then
		choice = GetLocale()
	end
	return locales[choice] and choice or "enUS"
end

function KeyQueue:ApplyLanguage()
	self.activeLanguage = self:ResolveLanguage(self.db.global.language)
	activeLocale = locales[self.activeLanguage]
end

-- Gewählte Sprache wirkt nach dem Neuladen der Oberfläche (Texte stehen schon in den Fenstern)
function KeyQueue:SetLanguage(choice)
	self.db.global.language = choice
end

function KeyQueue:LanguageNeedsReload()
	return self:ResolveLanguage(self.db.global.language) ~= self.activeLanguage
end

local L = ns.L

KeyQueue.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

local CHAT_PREFIX = "|cff8fb0ffKeyQueue|r: "

function KeyQueue:OnInitialize()
	-- ohne drittes Argument: jeder Charakter hat sein eigenes Profil (Filter, Bedarf, Fenster)
	self.db = LibStub("AceDB-3.0"):New("KeyQueueDB", ns.defaults)
	self:MigrateProfiles()
	self:ApplyLanguage()
	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

	self:RegisterChatCommand("kq", "OnSlashCommand")
	self:RegisterChatCommand("keyqueue", "OnSlashCommand")
end

function KeyQueue:OnEnable()
	-- Beschriftung des Tastenkürzels (Bindings.xml): WoW liest sie nur aus einer globalen Variable -
	-- die einzige Ausnahme von der Regel "keine Globals außer KeyQueue"
	_G.BINDING_NAME_KEYQUEUE_TOGGLE = ns.L["BINDING_TOGGLE"]
	ns.MinimapButton:Init()
	ns.StatusButton:Init()
end

-- Bis hierher teilten sich alle Charaktere das Profil "Default" (AceDB:New mit true). Jeder Charakter
-- bekommt beim ersten Start sein eigenes Profil mit den bisherigen Einstellungen und geht ab dann eigene
-- Wege; ein im Einstellungs-Tab bewusst gewähltes Profil bleibt danach unangetastet. Die Sperrliste gilt
-- für alle Charaktere und zieht aus den Profilen nach global um.
function KeyQueue:MigrateProfiles()
	local db = self.db
	local global = db.global
	if not global.blacklistMoved then
		global.blacklistMoved = true
		for _, profile in pairs(db.sv.profiles or {}) do
			if type(profile.blacklist) == "table" then
				for key, value in pairs(profile.blacklist) do
					global.blacklist[key] = value or nil
				end
				profile.blacklist = nil
			end
		end
	end
	local charKey = db.keys.char
	if global.ownProfile[charKey] then
		return
	end
	global.ownProfile[charKey] = true
	if db:GetCurrentProfile() == "Default" and charKey ~= "Default" then
		db:SetProfile(charKey)
		if db.sv.profiles and db.sv.profiles.Default then
			db:CopyProfile("Default", true)
		end
	end
end

function KeyQueue:OnProfileChanged()
	ns.MinimapButton:Refresh()
	self:SendMessage("KEYQUEUE_PROFILE_CHANGED")
end

-- Chat-Ausgabe mit KeyQueue-Präfix
function KeyQueue:Msg(text)
	DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(text))
end

-- Slash-Befehle sind optional; alles ist auch per GUI erreichbar.
function KeyQueue:OnSlashCommand(input)
	local cmd = strtrim(input or ""):lower()

	if cmd == "" then
		self:ToggleMainWindow()
	elseif cmd == "api" or cmd == "phase0" then
		self:OpenApiCheck()
	elseif ns.MatchTest and cmd == "mm" then
		ns.MatchTest:Toggle()
	elseif ns.DevMemory and cmd:match("^mem") then
		ns.DevMemory:Command(cmd:match("^mem%s*(.*)$"))
	elseif cmd == "minimap" then
		ns.MinimapButton:SetShown(self.db.profile.minimap.hide)
	elseif cmd == "reset" then
		self.db.profile.mainWindow.point = nil
		self.db.profile.window.point = nil
		if ns.MainFrame.frame then
			ns.MainFrame.frame:RestorePosition()
		end
		self:Msg(L["SLASH_RESET_DONE"])
	else
		self:Msg(L["SLASH_HELP"])
	end
end
