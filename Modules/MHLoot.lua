local mod = ManyHow:NewModule("MHLoot", "AceTimer-3.0","AceEvent-3.0" )
local L = LibStub("AceLocale-3.0"):GetLocale("ManyHow")
local B = LibStub("LibBabble-Faction-3.0")
local BL = B:GetLookupTable()
mod.modName = L["MHLoot"]
mod.canBeDisabled = true;

-- Find my parser module.  If it's not there, then, well, I can't do anything
local ParseMod = ManyHow:GetModule("Parser")
local HMDebPrint = ManyHow.DebugPrint
local MAX_DELAY_TIME = 2.0
local MIN_DELAY_TIME = 0.3
local DELAY_TIME_INC = 0.1

-- contains items we've received recently, and are holding to see if any more come in.
-- Keyed by item link.  Value is a table, with keys "TimeReceived" and "ParserEvent", "TimerHandle"
local ItemHash = {}
local lootChatFrame

-- Money strings.  Take copies of the global strings, remove the parameters.  This gives us, essentially, translated words for Gold, silver, copper
local GOLD = gsub(GOLD_AMOUNT, "%%d ", "")
local SILVER = gsub(SILVER_AMOUNT, "%%d ", "")
local COPPER = gsub(COPPER_AMOUNT, "%%d ", "")

local player = UnitName("player")
local defaults = {
	profile = {
		trackMoney = true,
		moneyAsWords = false,
		moneyAsColors = true,
		trackItems = true,
		trackFaction = true,
		trackCurrency = true,
		delayItems = false,
		delayTime = 1.0
	}
}

local options = {
	type = "group",
	name = L["MHLoot Options"],
	order = 1,
	childGroups = 'tree',
	args = {
		--[[
		Enable = {
			type = "toggle",
			name = L["Enable "] .. L["module"] .. " MHLoot",
			desc = L["Enable "] .. L["module"] .. " MHLoot",
			order = 11,
			get = function()
				return ManyHow.db.profile.modules["MHLoot"] ~= false or false
			end,
			set = function(_, v)
				ManyHow.db.profile.modules["MHLoot"] = v
				if v then
					ManyHow:EnableModule("MHLoot")
				else
					ManyHow:DisableModule("MHLoot")
				end
			end
		},
		]]--
		MoneyOptions = {
			type = "group",
			name = L["Money Loot Options"],
			order = 1,
			args = {
				money = {
					type = "toggle",
					name = L["Show Total Money"],
					desc = L["Show total money on loot messages"],
					descStyle = "inline",
					order = 5,
					width = "full",
					get = function()
						return mod.db.profile.trackMoney
					end,
					set = function(info, v)
						mod.db.profile.trackMoney = v
					end
				},
				moneywords = {
					type = "toggle",
					name = L["Show with words"],
					desc = L["Show denomination with words.  321 Gold 45 Silver 67 Copper"],
					descStyle = "inline",
					order = 7,
					width = "full",
					get = function()
						return mod.db.profile.moneyAsWords
					end,
					set = function(info, v)
						mod.db.profile.moneyAsWords = v
					end
				},
				moneycolor = {
					type = "toggle",
					name = L["Colorize money loots"],
					desc = L["Show total money using colors. |cffffd700321|r |cff80808045|r |cffeda55f67|r"],
					descStyle = "inline",
					order = 8,
					width = "full",
					get = function()
						return mod.db.profile.moneyAsColors
					end,
					set = function(info, v)
						mod.db.profile.moneyAsColors = v
					end
				}
			}
		},
		ItemOptions = {
			type = "group",
			name = L["Item Loot Options"],
			order = 2,
			args = {
				items = {
					type = "toggle",
					name = L["Show Bags Total"],
					desc = L["Show total in bags on loot messages"],
					descStyle = "inline",
					order = 1,
					width = "full",
					get = function()
						return mod.db.profile.trackItems
					end,
					set = function(info, v)
						mod.db.profile.trackItems = v
					end
				} --[[,
				delay = {
					type = "toggle",
					name = L["Delay item loot messages"],
					desc = L["Sometimes your inventory hasn't updated when the loot message is sent.  Setting this option will delay loot messages to allow inventory to update."],
					descStyle = "inline",
					order = 2,
					width = "full",
					get = function()
						return mod.db.profile.delayItems
					end,
					set = function(info, v)
						mod.db.profile.delayItems = v
					end
				},
				delayTime = {
					type = "range",
					order = 3,
					name = L["Delay time (seconds)"],
					desc = L["How long to delay item loot messages"],
					min = MIN_DELAY_TIME,
					max = MAX_DELAY_TIME,
					step = DELAY_TIME_INC,
					width = "full",
					get = function(info) return mod.db.profile.delayTime or 1.0 end,
					set = function(info, val)
							mod.db.profile.delayTime = val
						end,
				}
				]]
			}
		},
		CurrencyOptions = {
			type = "group",
			name = L["Currency Loot Options"],
			order = 3,
			args = {
				items = {
					type = "toggle",
					name = L["Show New Total"],
					desc = L["Show new currency total on loot messages"],
					descStyle = "inline",
					order = 6,
					width = "full",
					get = function()
						return mod.db.profile.trackCurrency
					end,
					set = function(info, v)
						mod.db.profile.trackCurrency = v
					end
				}
			}
		},
		FactionOptions = {
			type = "group",
			name = L["Faction Options"],
			order = 2,
			args = {
				items = {
					type = "toggle",
					name = L["Show New Total"],
					desc = L["Show new faction standing on faction messages"],
					descStyle = "inline",
					order = 6,
					width = "full",
					get = function()
						return mod.db.profile.trackFaction
					end,
					set = function(info, v)
						mod.db.profile.trackFaction = v
					end
				}
			}
		},
		--[[
		CombineOptions = {
			type = "group",
			name = L["Combine Messages"],
			order = 2,
			args = {
				items = {
					type = "toggle",
					name = L["Combine Similar Loot Messages"],
					desc = L["Combine multiple loots for the same item in a short timeframe together into a single message."],
					descStyle = "inline",
					order = 6,
					get = function()
						return mod.db.profile.trackCurrency
					end,
					set = function(info, v)
						mod.db.profile.trackCurrency = v
					end
				}
			}
		}
		]]--


	}
}

-- These are the events that I'm interested in parsing.
local valid_events = {
	CHAT_MSG_LOOT = true,
	CHAT_MSG_MONEY = true,
	CHAT_MSG_CURRENCY = true,
	CHAT_MSG_COMBAT_FACTION_CHANGE = true
}

local specialReputations = {
	[BL["Aeda Brightdawn"]]="bodyguard",
	[BL["Chee Chee"]]="friend",
	[BL["Defender Illona"]]="bodyguard",
	[BL["Delvar Ironfist"]]="bodyguard",
	[BL["Ella"]]="friend",
	[BL["Farmer Fung"]]="friend",
	[BL["Fish Fellreed"]]="friend",
	[BL["Gina Mudclaw"]]="friend",
	[BL["Haohan Mudclaw"]]="friend",
	[BL["Jogu the Drunk"]]="friend",
	[BL["Leorajh"]]="bodyguard",
	[BL["Nat Pagle"]]="friend",
	[BL["Nomi"]]="friend",
	[BL["Old Hillpaw"]]="friend",
	[BL["Sho"]]="friend",
	[BL["Talonpriest Ishaal"]]="bodyguard",
	[BL["Tina Mudclaw"]]="friend",
	[BL["Tormmok"]]="bodyguard",
	[BL["Vivianne"]]="bodyguard"
}


local friendReputationLevels = {
	{frMin=0,frMax=8399,frName=BL["Stranger"]},
	{frMin=8400,frMax=16799,frName=BL["Acquaintance"]},
	{frMin=16800,frMax=25199,frName=BL["Buddy"]},
	{frMin=25200,frMax=33599,frName=BL["Friend"]},
	{frMin=33600,frMax=41999,frName=BL["Good Friend"]},
	{frMin=42000,frMax=42999,frName=BL["Best Friend"]}
}

local bodyguardReputationLevels = {
	{frMin=0,frMax=9999,frName="Bodyguard"},
	{frMin=10000,frMax=19999,frName="Trusted Bodyguard"},
	{frMin=20000,frMax=29999,frName="Personal Wingman"}
}


local factionNameToID = {
	["7th Legion"] = 2159,
   [BL["Aeda Brightdawn"]] = 1740,
   ["Akama's Trust"] = 1416,
   [BL["Alliance Vanguard"]] = 1037,
   [BL["Arakkoa Outcasts"]] = 1515,
   [BL["Argent Crusade"]] = 1106,
   [BL["Argent Dawn"]] = 529,
   ["Armies of Legionfall"] = 2045,
   [BL["Ashtongue Deathsworn"]] = 1012,
   [BL["Avengers of Hyjal"]] = 1204,
   [BL["Baradin's Wardens"]] = 1177,
   [BL["Barracks Bodyguards"]] = 1735,
   [BL["Bilgewater Cartel"]] = 1133,
   [BL["Bizmo's Brawlpub"]] = 1419,
   [BL["Bloodsail Buccaneers"]] = 87,
   [BL["Booty Bay"]] = 21,
   [BL["Brawl'gar Arena"]] = 1374,
   [BL["Brood of Nozdormu"]] = 910,
   [BL["Cenarion Circle"]] = 609,
   [BL["Cenarion Expedition"]] = 942,
   ["Champions of Azeroth"] = 2164,
   [BL["Chee Chee"]] = 1277,
   [BL["Court of Farondis"]] = 1900,
   [BL["Council of Exarchs"]] = 1731,
   [BL["Darkmoon Faire"]] = 909,
   [BL["Darkspear Trolls"]] = 530,
   [BL["Darnassus"]] = 69,
   [BL["Defender Illona"]] = 1738,
   [BL["Delvar Ironfist"]] = 1733,
   [BL["Dominance Offensive"]] = 1375,
   [BL["Dragonmaw Clan"]] = 1172,
   [BL["Dreamweavers"]] = 1883,
   [BL["Ella"]] = 1275,
   ["Emperor Shaohao"]=1492,
   [BL["Everlook"]] = 577,
   [BL["Exodar"]] = 930,
   [BL["Explorers' League"]] = 1068,
   [BL["Farmer Fung"]] = 1283,
   [BL["Fish Fellreed"]] = 1282,
   [BL["Forest Hozen"]] = 1228,
   [BL["Frenzyheart Tribe"]] = 1104,
   [BL["Frostwolf Clan"]] = 729,
   [BL["Frostwolf Orcs"]] = 1445,
   [BL["Gadgetzan"]] = 369,
   [BL["Gelkis Clan Centaur"]] = 92,
   [BL["Gilnean Survivors"]] = 1815,
   [BL["Gilneas"]] = 1134,
   [BL["Gina Mudclaw"]] = 1281,
   [BL["Gnomeregan"]] = 54,
   [BL["Golden Lotus"]] = 1269,
   [BL["Guardians of Hyjal"]] = 1158,
   [BL["Guild"]] = 1168,
   [BL["Hand of the Prophet"]] = 1847,
   [BL["Haohan Mudclaw"]] = 1279,
   [BL["Hellscream's Reach"]] = 1178,
   [BL["Highmountain Tribe"]] = 1828,
   [BL["Honor Hold"]] = 946,
   [BL["Horde Expedition"]] = 1052,
   [BL["Huojin Pandaren"]] = 1352,
   [BL["Hydraxian Waterlords"]] = 749,
   [BL["Illidari"]] = 1947,
   [BL["Ironforge"]] = 47,
   [BL["Jandvik Vrykul"]] = 1888,
   [BL["Jogu the Drunk"]] = 1273,
   [BL["Keepers of Time"]] = 989,
   [BL["Kirin Tor"]] = 1090,
   [BL["Kirin Tor Offensive"]] = 1387,
   [BL["Knights of the Ebon Blade"]] = 1098,
   [BL["Kurenai"]] = 978,
   [BL["Laughing Skull Orcs"]] = 1708,
   [BL["Leorajh"]] = 1741,
   [BL["Lower City"]] = 1011,
   [BL["Magram Clan Centaur"]] = 93,
   [BL["Nat Pagle"]] = 1358,
   [BL["Netherwing"]] = 1015,
   [BL["Nomi"]] = 1357,
   [BL["Ogri'la"]] = 1038,
   [BL["Old Hillpaw"]] = 1276,
   [BL["Operation: Aardvark"]] = 1679,
   [BL["Operation: Shieldwall"]] = 1376,
   ["Order of Embers"] = 2161,
   [BL["Order of the Awakened"]] = 1849,
   [BL["Order of the Cloud Serpent"]] = 1271,
   [BL["Orgrimmar"]] = 76,
   [BL["Pearlfin Jinyu"]] = 1242,
   ["Proudmoore Admiralty"] = 2160,
   [BL["Ramkahen"]] = 1173,
   [BL["Ratchet"]] = 470,
   [BL["Ravenholdt"]] = 349,
   [BL["Shado-Pan"]] = 1270,
   [BL["Shado-Pan Assault"]] = 1435,
   [BL["Shadowmoon Exiles"]] = 1520,
   [BL["Shang Xi's Academy"]] = 1216,
   [BL["Sha'tari Defense"]] = 1710,
   [BL["Sha'tari Skyguard"]] = 1031,
   [BL["Shattered Sun Offensive"]] = 1077,
   [BL["Shen'dralar"]] = 809,
   [BL["Sho"]] = 1278,
   [BL["Silvermoon City"]] = 911,
   [BL["Silverwing Sentinels"]] = 890,
   [BL["Sporeggar"]] = 970,
   [BL["Steamwheedle Draenor Expedition"]] = 1732,
   [BL["Steamwheedle Preservation Society"]] = 1711,
   [BL["Stormpike Guard"]] = 730,
   ["Storm's Wake"] = 2162,
   [BL["Stormwind"]] = 72,
   [BL["Sunreaver Onslaught"]] = 1388,
   [BL["Syndicate"]] = 70,
   ["Talanji's Expedition"] = 2156,
   [BL["Talonpriest Ishaal"]] = 1737,
   [BL["The Aldor"]] = 932,
   [BL["The Anglers"]] = 1302,
   [BL["The Ashen Verdict"]] = 1156,
   [BL["The August Celestials"]] = 1341,
   [BL["The Black Prince"]] = 1359,
   [BL["The Brewmasters"]] = 1351,
   [BL["The Consortium"]] = 933,
   [BL["The Defilers"]] = 510,
   [BL["The Earthen Ring"]] = 1135,
   [BL["The First Responders"]] = 1984,
   [BL["The Frostborn"]] = 1126,
   [BL["The Hand of Vengeance"]] = 1067,
   ["The Honorbound"] = 2157,
   [BL["The Kalu'ak"]] = 1073,
   [BL["The Klaxxi"]] = 1337,
   [BL["The League of Arathor"]] = 509,
   [BL["The Lorewalkers"]] = 1345,
   [BL["The Mag'har"]] = 941,
   [BL["The Nightfallen"]] = 1859,
   [BL["The Oracles"]] = 1105,
   [BL["Therazane"]] = 1171,
   [BL["The Scale of the Sands"]] = 990,
   [BL["The Saberstalkers"]] = 1850,
   [BL["The Scryers"]] = 934,
   [BL["The Sha'tar"]] = 935,
   [BL["The Silver Covenant"]] = 1094,
   [BL["The Sons of Hodir"]] = 1119,
   [BL["The Sunreavers"]] = 1124,
   [BL["The Taunka"]] = 1064,
   [BL["The Tillers"]] = 1272,
   [BL["The Violet Eye"]] = 967,
   [BL["The Wardens"]] = 1894,
   [BL["The Wyrmrest Accord"]] = 1091,
   [BL["Thorium Brotherhood"]] = 59,
   [BL["Thrallmar"]] = 947,
   [BL["Thunder Bluff"]] = 81,
   [BL["Timbermaw Hold"]] = 576,
   [BL["Tina Mudclaw"]] = 1280,
   [BL["Tormmok"]] = 1736,
   ["Tortollan Seekers"] = 2163,
   [BL["Tranquillien"]] = 922,
   [BL["Tushui Pandaren"]] = 1353,
   [BL["Undercity"]] = 68,
   [BL["Valarjar"]] = 1948,
   [BL["Valiance Expedition"]] = 1050,
   [BL["Vivianne"]] = 1739,
   ["Voldunai"] = 2158,
   [BL["Vol'jin's Headhunters"]] = 1848,
   [BL["Vol'jin's Spear"]] = 1681,
   [BL["Warsong Offensive"]] = 1085,
   [BL["Warsong Outriders"]] = 889,
   [BL["Wildhammer Clan"]] = 1174,
   [BL["Wintersaber Trainers"]] = 589,
   [BL["Wrynn's Vanguard"]] = 1682,
   [BL["Zandalar Tribe"]] = 270,
   ["Zandalari Dinosaurs"] = 2111,
   ["Zandalari Empire"] = 2103
 }


-- *********************************************************
-- This function gets called by a timer in the case we don't
-- get a bag update event within a certain time.  In that case
-- we just push the message out unmodified.
-- *********************************************************
function mod:ItemTimerCallback(tableKey)

	if ( ItemHash[tableKey] ) then  -- ok, we found it

		local event = ItemHash[tableKey].ParserEvent.event

		if ( strsub(event, 1, 8) == "CHAT_MSG" ) then

			local type = strsub(event, 10);
			local info = ChatTypeInfo[type];

			if ( type == "LOOT" ) then

				local numItems = GetItemCount(tableKey) or 0

				-- inventory still hasn't updated.  Delay again.
				if ( numItems == 0 ) then
					-- If we've delayed once already, then just let the message go.
					if ItemHash[tableKey].extraDelayCounter == 0 then

						ItemHash[tableKey].extraDelayCounter = (ItemHash[tableKey].extraDelayCounter or 0)+ 1
						--[[local extraTime = DELAY_TIME_INC

						if mod.db.profile.delayItems then -- delay already turned on, but not high enough?
							if ( mod.db.profile.delayTime < MAX_DELAY_TIME-DELAY_TIME_INC ) then
								mod.db.profile.delayTime = mod.db.profile.delayTime + DELAY_TIME_INC
							end
						else
							--mod.db.profile.delayItems = true  -- delay not on, so turn it on.
							--mod.db.profile.delayTime = MIN_DELAY_TIME

							extraTime = MIN_DELAY_TIME
						end
						]]--
						ItemHash[tableKey].TimerHandle = mod:ScheduleTimer( "ItemTimerCallback", DELAY_TIME_INC, tableKey)

						return
					end

				end

				--local resultString = " " .. L["You now have"] .. " " .. numItems .. "."

				if ( lootChatFrame ) then
					lootChatFrame:AddMessage(ItemHash[tableKey].ParserEvent.OriginalText, info.r, info.g, info.b, info.id);
				else
					DEFAULT_CHAT_FRAME:AddMessage(ItemHash[tableKey].ParserEvent.OriginalText, info.r, info.g, info.b, info.id);
				end

			end
		end
		ItemHash[tableKey] = nil
	end

end

----------------------------------------
-- When we get a bag update, see if there is anything we can force out of the queue
----------------------------------------
function mod:BAG_UPDATE_DELAYED()

	local itemLink
	for itemLink in pairs(ItemHash) do

		local event = ItemHash[itemLink].ParserEvent.event

		if ( strsub(event, 1, 8) == "CHAT_MSG" ) then -- These conditions should always be true, but just being careful

			local type = strsub(event, 10);
			local info = ChatTypeInfo[type];

			if ( type == "LOOT" ) then

				local numItems = GetItemCount(itemLink) or 0

				-- If the count has changed, then we (probably) have gotten our update
				-- If the count hasn't changed yet.. let the timer handle it.
				if numItems ~= ItemHash[itemLink].numItemsBefore then

					-- cancel the timer
					mod:CancelTimer(ItemHash[itemLink].TimerHandle, true)

					local resultString;
					if ( numItems == 0 ) then
						resultString = ""
					else
						resultString = " " .. L["You now have"] .. " " .. numItems .. "."
					end

					if ( lootChatFrame ) then
						lootChatFrame:AddMessage(ItemHash[itemLink].ParserEvent.OriginalText .. resultString, info.r, info.g, info.b, info.id);
						--lootChatFrame:AddMessage(ItemHash[itemLink].ParserEvent.OriginalText .. "(" .. ItemHash[itemLink].Class .. ")" .. resultString, info.r, info.g, info.b, info.id);
					else
						DEFAULT_CHAT_FRAME:AddMessage(ItemHash[itemLink].ParserEvent.OriginalText .. resultString, info.r, info.g, info.b, info.id);
					end

					ItemHash[itemLink] = nil

				end
			end
		end
	end


end


-- *********************************************************
-- *********************************************************
local function HandleCurrency(parserEvent)

	if ( not mod.db.profile.trackCurrency ) then return end

	local idx, wasCurrency
	wasCurrency = false
	-- Debug
	-- DEFAULT_CHAT_FRAME:AddMessage( parserEvent.moneyString );
	for idx = 1, C_CurrencyInfo.GetCurrencyListSize() do
		local info = C_CurrencyInfo.GetCurrencyListInfo(idx)
		if info and info.name ~= "Legion" and info.quantity ~= 0 then
			local matchEnd = strfind(parserEvent.moneyString, info.name)
			-- Debug
			-- DEFAULT_CHAT_FRAME:AddMessage( cname .. " " .. tostring(ccount) );
			-- Check if a match was found.
			if (matchEnd) then
				ItemHash[parserEvent.moneyString] = nil  -- We don't have to worry about the timer any more, so just forget it.
				parserEvent.MessageDelayed = false  -- we're not combining this message.  Just let it go through
				parserEvent.resultString = " " .. L["You now have"] .. " " .. info.quantity .. "."
				wasCurrency = true -- don't bother to search any more
				break
			end
		end
	end

	if not wasCurrency then
		for idx = 1, GetNumArchaeologyRaces() do
			local raceName, numFragmentsCollected, numFragmentsRequired
			raceName, _, _, numFragmentsCollected, numFragmentsRequired = GetArchaeologyRaceInfo(idx)
			local matchEnd = strfind(parserEvent.moneyString, raceName)
			-- Check if a match was found.
			if (matchEnd) then
				ItemHash[parserEvent.moneyString] = nil  -- We don't have to worry about the timer any more, so just forget it.
				parserEvent.MessageDelayed = false  -- we're not combining this message.  Just let it go through
				local numToGo = numFragmentsRequired - numFragmentsCollected
				local msgAdd = ""
				if ( numFragmentsRequired == 0 ) then  -- no arch skill?
					msgAdd = ""
				elseif ( numToGo <= 0 ) then
					msgAdd = " (Artifact complete)"
				else
					msgAdd = " (" .. numToGo .. " more to complete)"
				end
				parserEvent.resultString = " " .. L["You now have"] .. " " .. numFragmentsCollected .. msgAdd .. "."
				wasCurrency = true -- don't bother to search any more
				break
			end
		end
	end
end



-- *********************************************************
-- *********************************************************
local function HandleFaction(parserEvent)
	-- HMDebPrint("In HandleFaction.." .. parserEvent.factionString .. " "  .. parserEvent.amount )

	-- barValue
	-- -42000 - -6001 (36000) - Hated
	--  -6000 - -3001 ( 3000) - Hostile
	--  -3000 -    -1 ( 3000) - Unfriendly
	--+  0000 -  2999 ( 3000) - Neutral
	--+  3000 -  8999 ( 6000) - Friendly
	--+  9000 - 20999 (12000) - Honored
	--+ 21000 - 41999 (21000) - Revered
	--+ 42000 - 42999 ( 1000) - Exalted

	--  0000 -  8390 (8400) - Stranger
	--  8400 - 16799 (8400) - Acquaintence
	-- 16800 - 25199 (8400) - Buddy
	-- 25200 - 33599 (8400) - Friend
	-- 33600 - 41999 (8400) - Good Friend
	-- 42000 - 42999 (1000) - Best Friend

	if ( not mod.db.profile.trackFaction ) then return end
	-- See if we can find the faction ID
	if not factionNameToID[parserEvent.factionString] then
		return
	end
	local factionID = factionNameToID[parserEvent.factionString]
	local name, _, standingID, barMin, barMax, barValue, _, _, isHeader, _, hasRep = GetFactionInfoByID(factionID)
	local paragonTag = ""

	-- Paragon faction level?
	if C_Reputation.IsFactionParagon(factionID) then
		local currentValue, threshold = C_Reputation.GetFactionParagonInfo(factionID);
		barMin, barMax, barValue = 0, threshold, currentValue;
		paragonTag = "(Paragon)"
	-- Debug
	-- DEFAULT_CHAT_FRAME:AddMessage( "Is Paragon min=" .. tostring(barMin) .. " max=" .. tostring(barMax) .. " value=" .. tostring(barValue) );
	-- else
	-- DEFAULT_CHAT_FRAME:AddMessage( "Is NOT Paragon min=" .. tostring(barMin) .. " max=" .. tostring(barMax) .. " value=" .. tostring(barValue) );
	end
	--HMDebPrint("standingID=" .. standingID .. ", barMin=" .. barMin .. ", barMax=" .. barMax .. ", barValue=" .. barValue )
	local repType = specialReputations[parserEvent.factionString] or "normal"
	if repType == "friend" then
		for _, frRep in pairs(friendReputationLevels) do
			if ( barValue >= frRep.frMin and barValue <= frRep.frMax ) then
				local progress = barValue-frRep.frMin
				local nextTransition = frRep.frMax-frRep.frMin
				-- You are now (progress)/(next) into (standing)
				parserEvent.resultString = " " .. L["You are now"] .. " " .. progress .. "/" .. nextTransition .. " " .. L["into"] .. " " .. frRep.frName
			end
		end
	elseif repType == "bodyguard" then
		for _, frRep in pairs(bodyguardReputationLevels	) do
			if ( barValue >= frRep.frMin and barValue <= frRep.frMax ) then
				local progress = barValue-frRep.frMin
				local nextTransition = frRep.frMax-frRep.frMin
				-- You are now (progress)/(next) into (standing)
				parserEvent.resultString = " " .. L["You are now"] .. " " .. progress .. "/" .. nextTransition .. " " .. L["into"] .. " " .. frRep.frName
			end
		end
	else
		local progress = barValue-barMin
		local nextTransition = barMax-barMin
		-- You are now (progress)/(next) into (standing)
		parserEvent.resultString = " " .. L["You are now"] .. " " .. progress .. "/" .. nextTransition .. " " .. L["into"] .. " " .. _G["FACTION_STANDING_LABEL" .. standingID] .. " " .. paragonTag
	end
end


-- *********************************************************
-- *********************************************************
local function HandleMoney(parserEvent)
	-- HMDebPrint("In HandleMoney.." .. parserEvent.moneyString )
	if ( not mod.db.profile.trackMoney ) then return end
	local mstart, mend, capCopper, capSilver, capGold

	-- pull the amount of gold, silver, copper in this loot message
	mstart, mend, capCopper = strfind(parserEvent.moneyString,"(%d+) " .. COPPER)
	capCopper = capCopper or 0
	mstart, mend, capSilver = strfind(parserEvent.moneyString,"(%d+) " .. SILVER)
	capSilver = capSilver or 0
	mstart, mend, capGold = strfind(parserEvent.moneyString,"(%d+) " .. GOLD)
	capGold = capGold or 0

	-- Add what was just looted to the player total..  As of 5.1, this is no longer necessary.
	local playerMoney = GetMoney() -- + capCopper + 100*capSilver + 100*100*capGold
	local playerGold = floor(playerMoney / (100 * 100))
	playerMoney = playerMoney - 100*100 * playerGold
	local playerSilver = floor(playerMoney / 100)
	local playerCopper = playerMoney % 100

	-- Format the result
	if ( mod.db.profile.moneyAsWords ) then
		playerGold = tostring(playerGold) .. " " .. GOLD
		playerSilver = tostring(playerSilver) .. " " .. SILVER
		playerCopper = tostring(playerCopper) .. " " .. COPPER
	end

	if ( mod.db.profile.moneyAsColors ) then
		parserEvent.resultString = ". " .. L["You now have"] .. " |cffffd700" .. playerGold .. "|r |cff808080" .. playerSilver .. "|r " .. "|cffeda55f" .. playerCopper .. "|r"
	else
		parserEvent.resultString = ". " .. L["You now have"] .. " " .. playerGold .. " " .. playerSilver .. " " .. playerCopper
	end

	parserEvent.MessageDelayed = false  -- we're not delaying this message.  Just let it go through
end


-- *********************************************************
-- *********************************************************
local function HandleItems(parserEvent)
	--HMDebPrint("In HandleItems" )
	-- Created items are subject to a race condition.  Sometimes they're already in inventory when we get notified,
	-- sometimes they're not.  So always delay them.

	-- Get information about the looted item.
	local itemLink = parserEvent.itemLink

	-- Get the number of items already existing in inventory and add the amount
	-- looted to it if the item wasn't the result of a conjure.

	--if (not parserEvent.isCreate) then
	--	numTotal = numTotal + numLooted
	--end

	local numLooted = parserEvent.amount or 1
	local numItems = GetItemCount(itemLink) or 0
	local numTotal = numItems -- + numLooted   -- removed because of apparent race condition

	local _,_,_,_,_,itemClass,itemSubClass,_,_,_,_=GetItemInfo(itemLink);

	if ( ItemHash[itemLink] ) then -- we've recently seen one of these..
		-- Cancel the old timer and refresh it
		if ItemHash[itemLink].TimerHandle then
			mod:CancelTimer(ItemHash[itemLink].TimerHandle, true)
		end
	end

	ItemHash[itemLink] = {}
	ItemHash[itemLink].TimeReceived = GetTime()
	ItemHash[itemLink].ParserEvent = parserEvent
	ItemHash[itemLink].Class = itemClass
	ItemHash[itemLink].SubClass = itemSubClass

	-- Start the timer here..
	if mod.db.profile.delayItems then
		ItemHash[itemLink].TimerHandle = mod:ScheduleTimer( "ItemTimerCallback", mod.db.profile.delayTime, itemLink)
	else
		ItemHash[itemLink].TimerHandle = mod:ScheduleTimer( "ItemTimerCallback", 1.0, itemLink)
	end

	ItemHash[itemLink].numItemsBefore = numItems
	ItemHash[itemLink].extraDelayCounter = 0

	parserEvent.resultString = ""
	parserEvent.MessageDelayed = true  -- we're delaying this message, so kill the event here.
end


-- *********************************************************
-- *********************************************************
local function ParserEventsHandler(parserEvent,msgText)
	--HMDebPrint("In ParserEventsHandler" )
	-- Ignore the event if it isn't for the player or not a loot event.
	if (parserEvent.recipientUnit ~= "player" or (parserEvent.eventType ~= "loot" and parserEvent.eventType ~= "currency" and parserEvent.eventType ~= "faction")) then return end

	-- Call the correct handler for the loot type.
	if (parserEvent.eventType == "currency") then HandleCurrency(parserEvent) elseif (parserEvent.isMoney) then
		HandleMoney(parserEvent)
	elseif (parserEvent.eventType == "faction") then
		HandleFaction(parserEvent)
	elseif (parserEvent.itemLink) then
		HandleItems(parserEvent)
	end
end


-- *********************************************************
-- First two parms will be self and event.  The remaining args will be the args passed on the triggering event
-- CHAT_MSG_LOOT   ("message", "author", "language", "channelString", "target", "flags", unknown, channelNumber, "channelName", unknown, counter)
-- *********************************************************
local function messageFilter(self, event, arg1, arg2, ... )
	local pEvent = nil
	if arg1 and type(arg1) == "string" then
		if ( ParseMod ~= nil ) then
			pEvent = ParseMod.ParseRawChatEvent(event, arg1)
			if ( pEvent ) then
				ParserEventsHandler(pEvent,arg1)
				if ( pEvent.resultString ) then
					arg1 = arg1 .. pEvent.resultString
				end
				if ( pEvent.MessageDelayed ) then
					pEvent.event = event
				end
			end
		end
	end

	if ( pEvent and pEvent.MessageDelayed ) then
		return true   -- Don't display this message now...
	else
		return false, arg1, arg2, ...
	end
end




-- *********************************************************
-- *********************************************************
function mod:OnEnable()
	--HMDebPrint("In MHLoot:OnEnable" )
	for event in pairs(valid_events) do
		ChatFrame_AddMessageEventFilter(event, messageFilter )
	end

	-- Round to even tenths..
	mod.db.profile.delayTime = mod.db.profile.delayTime and floor(mod.db.profile.delayTime / 10)*10

	-- Find the correct chat frame to send loot messages to, if we're delaying loots
	local chatFrame
	local i,j=1,1

	for i=1,10 do
		chatFrame = _G["ChatFrame"..i]

		if (chatFrame) then
			for _,j in pairs {GetChatWindowMessages(chatFrame:GetID())} do
				if ( j == "LOOT" ) then
					lootChatFrame = chatFrame
				end
			end
		end
	end
	self:RegisterEvent("BAG_UPDATE_DELAYED")
end


-- *********************************************************
-- *********************************************************
function mod:OnDisable()
	-- Stop receiving updates.
	for event in pairs(valid_events) do
		ChatFrame_RemoveMessageEventFilter(event, messageFilter )
		--ChatFrame_RemoveMessageEventFilter("CHAT_MSG_LOOT", messageFilter )
	end
	self:UnregisterEvent("BAG_UPDATE_DELAYED")
end


-- *********************************************************
-- *********************************************************
function mod:OnInitialize()
	self.db = ManyHow.db:RegisterNamespace("MHLoot", defaults)
	mod.db.profile.delayItems = false;
end



-- *********************************************************
-- Present some information to Ace
-- *********************************************************
function mod:Info()
	return L["When looting money or items, show how much/many you now have."]
end

function mod:GetOptions()
	return options
end
