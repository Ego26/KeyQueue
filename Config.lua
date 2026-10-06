-- KeyQueue Config: Profile und Defaults (AceDB)
local _, ns = ...

ns.defaults = {
	profile = {
		minimap = {
			hide = false,
			angle = 225,
		},
		mainWindow = {
			scale = 1,
			-- point, relPoint, x, y werden beim Verschieben gespeichert
		},
		window = { -- Phase-0-Fenster
			scale = 1,
		},
		general = {
			sound = true,       -- Sound bei "Gruppe gefunden"
			autoAccept = false, -- Einladungen von Gruppen, bei denen ich mich beworben habe, automatisch annehmen
			lastTab = "search",
			roleDisplay = "spec", -- Rollen-Spalte der Suche: "spec" (Spec-Symbole) oder "class" (Klassenfarben)
			windowDefault = "compact", -- Fenstergröße beim Öffnen: "compact" oder "large"
			statusButton = true, -- Status-Symbol an der Minimap, solange Queue oder Listing läuft
			askFeedback = true, -- nach jedem Key kurz nach den Mitspielern fragen (Lob, Favorit, Nie wieder)
		},
		statusButton = {}, -- Position des Status-Symbols (point, relPoint, x, y); leer = an der Minimap
		leader = {
			minScore = 0,
			maxScore = 0,       -- 0 = egal
			minItemLevel = 0,
			minTimedHere = 0, -- gelisteten Dungeon mindestens auf dieser Stufe getimt (0 = egal)
			needTank = true,
			needHealer = true,
			needDamager = 3,
			needBloodlust = false,
			needBattleRez = false,
			autoInvite = true,
			crossFaction = true, -- Listing auch für die andere Fraktion (die braucht eine Eingabe zum Einladen)
			holdSeconds = 0, -- so lange hält ein Bewerber, der auf die Eingabe wartet, seinen Platz (0 = bis zur Bestätigung)
			inviteOnKey = true, -- andere Fraktion / Gruppen-Bewerbung beim nächsten Tastendruck einladen
		},
		-- Matchmaking-Queue (Panel an der Gruppensuche): Rollen, Stufenbereich, Mindestwertung, Key einbringen
		queue = {
			roles = {}, -- [TANK/HEALER/DAMAGER] = true; leer = Rolle der aktuellen Spec
			-- Keystufe: wie bei Blizzard über den Suchtext der Gruppensuche (ohne: Keys, die etwas bringen)
			includeNormal = true, -- auch Gruppen ohne KeyQueue (am Anfang, solange wenige KeyQueue haben)
			minScore = 0,
			bringKey = true,
		},
		search = {
			activityGroups = {}, -- [groupID] = true; leer = alle Dungeons
			minLeaderScore = 0,
			maxLeaderScore = 0,
			onlyKeyQueue = false,
			bloodlust = "any", -- any, has, missing
			battleRez = "any",
			hasTank = false,
			hasHealer = false,
			notMyClass = false,
			noLeaver = true,
			hideDeclined = true,
			autoApply = true, -- in der Queue bei jedem Tastendruck/Klick den nächsten Schritt (bewerben/suchen)
			showUnmatched = false, -- Trefferliste: nicht passende Gruppen einblenden
			leaderTimed = false,
			playstyles = {}, -- [1..4] = true; leer = alle
			-- membersMin/Max, tanksMin/Max, healersMin/Max, dpsMin/Max, maxAge: nil = egal
			expression = "", -- Experten-Ausdruck, z. B. "tanks == 1 and shamans == 0"
		},
		phase0 = {
			autoAccept = true,
			voiceTag = true,
			chatLog = true,
			inviteTarget = "",
		},
	},
	char = {
		-- laufende Leader-Sitzung, überlebt /reload
		leaderSession = {
			active = false,
			needs = {},
			pending = {},
			joined = {},
		},
	},
	global = {
		language = "auto", -- auto (Spielsprache), deDE, enUS
		onboarded = false,
		history = {}, -- Key-History aller Charaktere, älteste zuerst (max. 500)
		historyShowAll = false, -- History: standardmäßig nur der aktuelle Charakter
		characters = {}, -- [Name(-Realm)] = Klasse, für die eigenen Charakter-Cards in der History
		blacklist = {}, -- [Name oder Name-Realm] = true: Sperrliste für alle Charaktere
		favorites = {}, -- [Name(-Realm)] = true: bei Auto-Invite und in der Suche bevorzugt
		endorsements = {}, -- [runId][Name-Realm] = { tags, at, shared }: Lob nach dem Key (Endorsements.lua)
		notes = {}, -- [Name(-Realm)] = eigene Notiz zum Spieler
		ownProfile = {}, -- [Charakter-Schlüssel] = true: hat sein eigenes Profil bekommen (siehe Core.lua)
		blacklistMoved = false, -- Sperrliste aus den Profilen nach global übernommen
		phase0 = {
			-- results[probeID][mode] = { status, detail, at, build }
			results = {},
		},
	},
}
