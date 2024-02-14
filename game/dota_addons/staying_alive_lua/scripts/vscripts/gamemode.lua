-- This is the primary barebones gamemode script and should be used to assist in initializing your game mode
BAREBONES_VERSION = "2.0.17"

-- Selection library (by Noya) provides player selection inspection and management from server lua
require('libraries/selection')

-- settings.lua is where you can specify many different properties for your game mode and is one of the core barebones files.
require('settings')
-- events.lua is where you can specify the actions to be taken when any event occurs and is one of the core barebones files.
require('events')
-- filters.lua
require('filters')
-- gathering_nodes.lua
require('gathering_nodes')

--[[
  This function should be used to set up Async precache calls at the beginning of the gameplay.

  In this function, place all of your PrecacheItemByNameAsync and PrecacheUnitByNameAsync.  These calls will be made
  after all players have loaded in, but before they have selected their heroes. PrecacheItemByNameAsync can also
  be used to precache dynamically-added datadriven abilities instead of items.  PrecacheUnitByNameAsync will 
  precache the precache{} block statement of the unit and all precache{} block statements for every Ability# 
  defined on the unit.

  This function should only be called once.  If you want to/need to precache more items/abilities/units at a later
  time, you can call the functions individually (for example if you want to precache units in a new wave of
  holdout).

  This function should generally only be used if the Precache() function in addon_game_mode.lua is not working.
]]
function barebones:PostLoadPrecache()
	DebugPrint("[BAREBONES] Performing Post-Load precache.")
	--PrecacheItemByNameAsync("item_example_item", function(...) end)
	--PrecacheItemByNameAsync("example_ability", function(...) end)

	--PrecacheUnitByNameAsync("npc_dota_hero_viper", function(...) end)
	--PrecacheUnitByNameAsync("npc_dota_hero_enigma", function(...) end)
end

--[[
  This function is called once and only once after all players have loaded into the game, right as the hero selection time begins.
  It can be used to initialize non-hero player state or adjust the hero selection (i.e. force random etc)
]]
function barebones:OnAllPlayersLoaded()
  DebugPrint("[BAREBONES] All Players have loaded into the game.")
  
  -- Force Random a hero for every player that didnt pick a hero when time runs out (we do this so players don't end up without a hero)
  local delay = HERO_SELECTION_TIME + HERO_SELECTION_PENALTY_TIME + STRATEGY_TIME - 0.1
  if ENABLE_BANNING_PHASE then
    delay = delay + BANNING_PHASE_TIME
  end
  Timers:CreateTimer(delay, function()
    for playerID = 0, DOTA_MAX_TEAM_PLAYERS-1 do
      if PlayerResource:IsValidPlayerID(playerID) then
        -- If this player still hasn't picked a hero, random one
        -- PlayerResource:IsConnected(index) is custom-made! Can be found in 'player_resource.lua' library
        if not PlayerResource:HasSelectedHero(playerID) and PlayerResource:IsConnected(playerID) and not PlayerResource:IsBroadcaster(playerID) then
          PlayerResource:GetPlayer(playerID):MakeRandomHeroSelection() -- this will cause an error if player is disconnected, that's why we check if player is connected
          PlayerResource:SetHasRandomed(playerID)
          PlayerResource:SetCanRepick(playerID, false)
          DebugPrint("[BAREBONES] Randomed a hero for a player number "..playerID)
        end
      end
    end
  end)
end

--[[
  This function is called once and only once when the game completely begins (about 0:00 on the clock).  At this point,
  gold will begin to go up in ticks if configured, creeps will spawn, towers will become damageable etc.  This function
  is useful for starting any game logic timers/thinkers, beginning the first round, etc.
]]
function barebones:OnGameInProgress()
	DebugPrint("[BAREBONES] The game has officially begun.")
	Timers(function()
		spawn_game_unit()
		return get_next_wave_timer()
	end)


	Timers:CreateTimer(CU_START_ANCIENT_NEUTRLAS, function()

		spawn_ancient_game_unit()

		return get_next_ancient_wave_timer()
	  end
	)


	local countdown_to_increase_ancients = Timers:CreateTimer(SA_START_SCALING_ANCIENTS, function()
		print("[debug][Ancients are now starting to scale in health]")
		local gamemode = GameRules:GetGameModeEntity()
		gamemode.bAncientScalingEnabled = true

		return
	  end
	)


	-- If the day/night is not changed at 00:00, uncomment the following line:
	--GameRules:SetTimeOfDay(0.251)
end

-- This function initializes the game mode and is called before anyone loads into the game
-- It can be used to pre-initialize any values/tables that will be needed later
function barebones:InitGameMode()
	DebugPrint("[BAREBONES] Starting to load Game Rules.")

	-- Setup rules
	GameRules:SetSameHeroSelectionEnabled(ALLOW_SAME_HERO_SELECTION)
	GameRules:SetUseUniversalShopMode(UNIVERSAL_SHOP_MODE)
	GameRules:SetHeroRespawnEnabled(ENABLE_HERO_RESPAWN)

	GameRules:SetHeroSelectionTime(HERO_SELECTION_TIME) -- THIS IS IGNORED when "EnablePickRules" is "1" in 'addoninfo.txt' !
	GameRules:SetHeroSelectPenaltyTime(HERO_SELECTION_PENALTY_TIME)

	GameRules:SetPreGameTime(PRE_GAME_TIME)
	GameRules:SetPostGameTime(POST_GAME_TIME)
	GameRules:SetShowcaseTime(SHOWCASE_TIME)
	GameRules:SetStrategyTime(STRATEGY_TIME)

	GameRules:SetTreeRegrowTime(TREE_REGROW_TIME)

	if USE_CUSTOM_HERO_LEVELS then
		GameRules:SetUseCustomHeroXPValues(true)
	end

	--GameRules:SetGoldPerTick(GOLD_PER_TICK) -- Doesn't work; Last time tested: 24.2.2020
	--GameRules:SetGoldTickTime(GOLD_TICK_TIME) -- Doesn't work; Last time tested: 24.2.2020
	GameRules:SetStartingGold(NORMAL_START_GOLD)

	if USE_CUSTOM_HERO_GOLD_BOUNTY then
		GameRules:SetUseBaseGoldBountyOnHeroes(false) -- if true Heroes will use their default base gold bounty which is similar to creep gold bounty, rather than DOTA specific formulas
	end

	GameRules:SetHeroMinimapIconScale(MINIMAP_ICON_SIZE)
	GameRules:SetCreepMinimapIconScale(MINIMAP_CREEP_ICON_SIZE)
	GameRules:SetRuneMinimapIconScale(MINIMAP_RUNE_ICON_SIZE)
	GameRules:SetFirstBloodActive(ENABLE_FIRST_BLOOD)
	GameRules:SetHideKillMessageHeaders(HIDE_KILL_BANNERS)
	GameRules:LockCustomGameSetupTeamAssignment(LOCK_TEAMS)

	-- This is multi-team configuration stuff
	if USE_AUTOMATIC_PLAYERS_PER_TEAM then
		local num = math.floor(10/MAX_NUMBER_OF_TEAMS)
		local count = 0
		for team, number in pairs(TEAM_COLORS) do
			if count >= MAX_NUMBER_OF_TEAMS then
				GameRules:SetCustomGameTeamMaxPlayers(team, 0)
			else
				GameRules:SetCustomGameTeamMaxPlayers(team, num)
			end
			count = count + 1
		end
	else
		local count = 0
		for team, number in pairs(CUSTOM_TEAM_PLAYER_COUNT) do
			if count >= MAX_NUMBER_OF_TEAMS then
				GameRules:SetCustomGameTeamMaxPlayers(team, 0)
			else
				GameRules:SetCustomGameTeamMaxPlayers(team, number)
			end
			count = count + 1
		end
	end

	if USE_CUSTOM_TEAM_COLORS then
		for team, color in pairs(TEAM_COLORS) do
			SetTeamCustomHealthbarColor(team, color[1], color[2], color[3])
		end
	end

	DebugPrint("[BAREBONES] Done with setting Game Rules.")

	-- Event Hooks / Listeners
	DebugPrint("[BAREBONES] Setting Event Hooks / Listeners.")
	ListenToGameEvent('dota_player_gained_level', Dynamic_Wrap(barebones, 'OnPlayerLevelUp'), self)
	ListenToGameEvent('dota_player_learned_ability', Dynamic_Wrap(barebones, 'OnPlayerLearnedAbility'), self)
	ListenToGameEvent('entity_killed', Dynamic_Wrap(barebones, 'OnEntityKilled'), self)
	ListenToGameEvent('player_connect_full', Dynamic_Wrap(barebones, 'OnConnectFull'), self)
	ListenToGameEvent('player_disconnect', Dynamic_Wrap(barebones, 'OnDisconnect'), self)
	ListenToGameEvent('dota_item_picked_up', Dynamic_Wrap(barebones, 'OnItemPickedUp'), self)
	ListenToGameEvent('last_hit', Dynamic_Wrap(barebones, 'OnLastHit'), self)
	ListenToGameEvent('dota_rune_activated_server', Dynamic_Wrap(barebones, 'OnRuneActivated'), self)
	ListenToGameEvent('tree_cut', Dynamic_Wrap(barebones, 'OnTreeCut'), self)

	ListenToGameEvent('dota_player_used_ability', Dynamic_Wrap(barebones, 'OnAbilityUsed'), self)
	ListenToGameEvent('game_rules_state_change', Dynamic_Wrap(barebones, 'OnGameRulesStateChange'), self)
	ListenToGameEvent('npc_spawned', Dynamic_Wrap(barebones, 'OnNPCSpawned'), self)
	ListenToGameEvent('dota_player_pick_hero', Dynamic_Wrap(barebones, 'OnPlayerPickHero'), self)
	ListenToGameEvent("player_reconnected", Dynamic_Wrap(barebones, 'OnPlayerReconnect'), self)
	ListenToGameEvent("player_chat", Dynamic_Wrap(barebones, 'OnPlayerChat'), self)

	ListenToGameEvent("dota_tower_kill", Dynamic_Wrap(barebones, 'OnTowerKill'), self)
	ListenToGameEvent("dota_player_selected_custom_team", Dynamic_Wrap(barebones, 'OnPlayerSelectedCustomTeam'), self)
	ListenToGameEvent("dota_npc_goal_reached", Dynamic_Wrap(barebones, 'OnNPCGoalReached'), self)

	-- Change random seed for math.random function
	local timeTxt = string.gsub(string.gsub(GetSystemTime(), ':', ''), '0','')
	math.randomseed(tonumber(timeTxt))

	DebugPrint("[BAREBONES] Setting Filters.")

	local gamemode = GameRules:GetGameModeEntity()

	-- Setting the Order filter 
	gamemode:SetExecuteOrderFilter(Dynamic_Wrap(barebones, "OrderFilter"), self)

	-- Setting the Damage filter
	gamemode:SetDamageFilter(Dynamic_Wrap(barebones, "DamageFilter"), self)

	-- Setting the Modifier filter
	gamemode:SetModifierGainedFilter(Dynamic_Wrap(barebones, "ModifierFilter"), self)

	-- Setting the Experience filter
	gamemode:SetModifyExperienceFilter(Dynamic_Wrap(barebones, "ExperienceFilter"), self)

	-- Setting the Tracking Projectile filter
	gamemode:SetTrackingProjectileFilter(Dynamic_Wrap(barebones, "ProjectileFilter"), self)

	-- Setting the bounty rune pickup filter
	gamemode:SetBountyRunePickupFilter(Dynamic_Wrap(barebones, "BountyRuneFilter"), self)

	-- Setting the Healing filter
	gamemode:SetHealingFilter(Dynamic_Wrap(barebones, "HealingFilter"), self)

	-- Setting the Gold Filter
	gamemode:SetModifyGoldFilter(Dynamic_Wrap(barebones, "GoldFilter"), self)

	-- Setting the Inventory filter
	gamemode:SetItemAddedToInventoryFilter(Dynamic_Wrap(barebones, "InventoryFilter"), self)

	DebugPrint("[BAREBONES] Done with setting Filters.")

	-- Global Lua Modifiers
	LinkLuaModifier("modifier_custom_invulnerable", "modifiers/modifier_custom_invulnerable.lua", LUA_MODIFIER_MOTION_NONE)
	LinkLuaModifier("modifier_custom_passive_gold", "modifiers/modifier_custom_passive_gold_example.lua", LUA_MODIFIER_MOTION_NONE)

	print("[BAREBONES] initialized.")
	DebugPrint("[BAREBONES] Done loading the game mode!\n\n")
	
	-- Increase/decrease maximum item limit per hero
	Convars:SetInt('dota_max_physical_items_purchase_limit', 64)
end

-- This function is called as the first player loads and sets up the game mode parameters
function barebones:CaptureGameMode()
	local gamemode = GameRules:GetGameModeEntity()

	-- Set GameMode parameters
	gamemode:SetRecommendedItemsDisabled(RECOMMENDED_BUILDS_DISABLED)
	gamemode:SetCameraDistanceOverride(CAMERA_DISTANCE_OVERRIDE)
	gamemode:SetBuybackEnabled(BUYBACK_ENABLED)
	gamemode:SetCustomBuybackCostEnabled(CUSTOM_BUYBACK_COST_ENABLED)
	gamemode:SetCustomBuybackCooldownEnabled(CUSTOM_BUYBACK_COOLDOWN_ENABLED)
	gamemode:SetTopBarTeamValuesOverride(USE_CUSTOM_TOP_BAR_VALUES) -- Probably does nothing, but I will leave it
	gamemode:SetTopBarTeamValuesVisible(TOP_BAR_VISIBLE)

	if USE_CUSTOM_XP_VALUES then
		gamemode:SetUseCustomHeroLevels(true)
		gamemode:SetCustomXPRequiredToReachNextLevel(XP_PER_LEVEL_TABLE)
	end

	gamemode:SetBotThinkingEnabled(USE_STANDARD_DOTA_BOT_THINKING)
	gamemode:SetTowerBackdoorProtectionEnabled(ENABLE_TOWER_BACKDOOR_PROTECTION)

	gamemode:SetFogOfWarDisabled(DISABLE_FOG_OF_WAR_ENTIRELY)
	gamemode:SetGoldSoundDisabled(DISABLE_GOLD_SOUNDS)
	--gamemode:SetRemoveIllusionsOnDeath(REMOVE_ILLUSIONS_ON_DEATH) -- Didnt work last time I tried

	gamemode:SetAlwaysShowPlayerInventory(SHOW_ONLY_PLAYER_INVENTORY)
	--gamemode:SetAlwaysShowPlayerNames(true) -- use this when you need to hide real hero names
	gamemode:SetAnnouncerDisabled(DISABLE_ANNOUNCER)

	if FORCE_PICKED_HERO then -- FORCE_PICKED_HERO must be a string name of an existing hero, or there will be a big fat error
		gamemode:SetCustomGameForceHero(FORCE_PICKED_HERO) -- THIS WILL NOT WORK when "EnablePickRules" is "1" in 'addoninfo.txt' !
	else
		gamemode:SetDraftingHeroPickSelectTimeOverride(HERO_SELECTION_TIME)
		gamemode:SetDraftingBanningTimeOverride(0)
		if ENABLE_BANNING_PHASE then
			gamemode:SetDraftingBanningTimeOverride(BANNING_PHASE_TIME)
			GameRules:SetCustomGameBansPerTeam(5)
		end
	end

	--gamemode:SetFixedRespawnTime(FIXED_RESPAWN_TIME) -- FIXED_RESPAWN_TIME should be float
	gamemode:SetFountainConstantManaRegen(FOUNTAIN_CONSTANT_MANA_REGEN)
	gamemode:SetFountainPercentageHealthRegen(FOUNTAIN_PERCENTAGE_HEALTH_REGEN)
	gamemode:SetFountainPercentageManaRegen(FOUNTAIN_PERCENTAGE_MANA_REGEN)
	gamemode:SetLoseGoldOnDeath(LOSE_GOLD_ON_DEATH)
	gamemode:SetMaximumAttackSpeed(MAXIMUM_ATTACK_SPEED)
	gamemode:SetMinimumAttackSpeed(MINIMUM_ATTACK_SPEED)
	gamemode:SetStashPurchasingDisabled(DISABLE_STASH_PURCHASING)

	if USE_DEFAULT_RUNE_SYSTEM then
		gamemode:SetUseDefaultDOTARuneSpawnLogic(true)
	else
		-- Some runes are broken by Valve, RuneSpawnFilter also didn't work last time I tried
		for rune, spawn in pairs(ENABLED_RUNES) do
			gamemode:SetRuneEnabled(rune, spawn)
		end
		gamemode:SetBountyRuneSpawnInterval(BOUNTY_RUNE_SPAWN_INTERVAL)
		gamemode:SetPowerRuneSpawnInterval(POWER_RUNE_SPAWN_INTERVAL)
	end

	gamemode:SetUnseenFogOfWarEnabled(USE_UNSEEN_FOG_OF_WAR)
	gamemode:SetDaynightCycleDisabled(DISABLE_DAY_NIGHT_CYCLE)
	gamemode:SetKillingSpreeAnnouncerDisabled(DISABLE_KILLING_SPREE_ANNOUNCER)
	gamemode:SetStickyItemDisabled(DISABLE_STICKY_ITEM)
	gamemode:SetPauseEnabled(ENABLE_PAUSING)
	gamemode:SetCustomScanCooldown(CUSTOM_SCAN_COOLDOWN)
	gamemode:SetCustomGlyphCooldown(CUSTOM_GLYPH_COOLDOWN)
	gamemode:DisableHudFlip(FORCE_MINIMAP_ON_THE_LEFT)

	gamemode:SetFreeCourierModeEnabled(true) -- without this, passive GPM doesn't work, Thanks Valve
end

function spawn_game_unit()
	print("[debug] attempting to spawn a unit")
	gamemode = GameRules:GetGameModeEntity()

	local creep_count = get_creep_count()
	local expected_creep_count = creep_count+1

	if expected_creep_count > CU_MAX_BASIC_CREEPS then
		print("[debug] expected creep count currently exceeds max creep allocation. current creep count: " .. get_creep_count() )

		return
	else
		print("[debug] Creep count currently: " .. get_creep_count() .. ". max creep limit constant is: " .. CU_MAX_BASIC_CREEPS)
	end

	local unit_to_spawn = get_sa_unit_name(get_timed_creepname())

	print("[debug] get_sa_unit_name(" .. unit_to_spawn .. ")")

	if gamemode.player_hero then
		local player_hero = gamemode.player_hero
		local player_hero_location = player_hero:GetAbsOrigin()	

		if player_hero_location and unit_to_spawn then
			local spawn_location_origin = get_validated_spawn_location()

			local unit = CreateUnitByName(unit_to_spawn, spawn_location_origin, true, nil, nil, DOTA_TEAM_BADGUYS)
			FindClearSpaceForUnit( unit, spawn_location_origin, true )
			-- Place a unit somewhere not already occupied.

			local unit_health = unit:GetMaxHealth()
			local new_health = unit_health*CU_SPAWNED_UNIT_HEALTH_PCT
			unit:SetMaxHealth( new_health )
			unit:SetBaseMaxHealth( new_health )
			unit:SetAcquisitionRange( CU_ACQ_RANGE )
			unit:SetAttacking( player_hero )
			unit:SetForceAttackTarget( player_hero )
			unit:AddAbility( "sa_creep_tracker" )
			unit:AddAbility( "sa_hostile_ai" )			
			local abil_to_hide = unit:FindAbilityByName( "sa_creep_tracker" )
			abil_to_hide:SetHidden( true )


			for abilitySlot=0,31 do
				local ability_u = unit:GetAbilityByIndex(abilitySlot)
				if ability_u then
					ability_u:SetLevel( 1 )
					print("[debug] unit ability leveled up: " .. ability_u:GetName() )
				end
			end

			-- scaling bounty
			if gamemode.current_countdown then
				local base_bounty = unit:GetGoldBounty()
				local spawn_rate = gamemode.current_countdown
				
				local base_bounty_per_sec = base_bounty / DEFAULT_STARTING_TIMER_VALUE
				local adjusted_bounty = base_bounty_per_sec * spawn_rate 			
				unit:SetMinimumGoldBounty( adjusted_bounty )
				unit:SetMaximumGoldBounty( adjusted_bounty )
			else
			end

		else
		end
	else
	end
end


function spawn_ancient_game_unit()
	print("[debug] attempting to spawn an ancient unit")
	gamemode = GameRules:GetGameModeEntity()

	local ancient_count = get_ancient_count()
	local expected_ancient_count = ancient_count+1

	if expected_ancient_count > CU_MAX_ANCIENTS then
		print("[debug] expected ancient count currently exceeds max ancient allocation. current ancient count: " .. get_ancient_count() )

		return
	else
		print("[debug] ancient count currently: " .. get_ancient_count() .. ". max ancient limit constant is: " .. CU_MAX_ANCIENTS)
	end


	local unit_to_spawn = get_sa_unit_name(5)

	print("[debug] get_sa_unit_name(" .. unit_to_spawn .. ")")

	if gamemode.player_hero then
		local player_hero = gamemode.player_hero
		local player_hero_location = player_hero:GetAbsOrigin()	

		if player_hero_location and unit_to_spawn then
			--local spawn_location_origin_unaudited = resolve_distant_location(player_hero_location)
			local spawn_location_origin = get_validated_spawn_location()

			local unit = CreateUnitByName(unit_to_spawn, spawn_location_origin, true, nil, nil, DOTA_TEAM_NEUTRALS)
			FindClearSpaceForUnit( unit, spawn_location_origin, true )
			-- Place a unit somewhere not already occupied.

			local unit_health = unit:GetMaxHealth()
			local new_health = unit_health*CU_SPAWNED_ANCIENT_HEALTH_PCT
			unit:SetMaxHealth( new_health )
			unit:SetBaseMaxHealth( new_health )
			unit:SetAcquisitionRange( CU_ACQ_RANGE )
			unit:SetAttacking( player_hero )
			unit:SetForceAttackTarget( player_hero )
			unit:AddAbility( "sa_ancient_tracker" )
			unit:AddAbility( "sa_hostile_ai" )			
			local abil_to_hide = unit:FindAbilityByName( "sa_ancient_tracker" )
			abil_to_hide:SetHidden( true )


			for abilitySlot=0,31 do
				local ability_u = unit:GetAbilityByIndex(abilitySlot)
				if ability_u then
					ability_u:SetLevel( 1 )
					print("[debug] unit ability leveled up: " .. ability_u:GetName() )
				end
			end

			if gamemode.bAncientScalingEnabled == true then
				-- ancient scaling bonus start
				local gametime = GameRules:GetDOTATime(false,false)
				local ancient_scaling_start_time = SA_START_SCALING_ANCIENTS
				local seconds_past_scaling_start = gametime - ancient_scaling_start_time
				local mins_past_scaling_start = seconds_past_scaling_start/60
				local health_multipler = SA_ANCIENT_SCALING_PCT_PER_MIN
				local health_multipler_value = mins_past_scaling_start*health_multipler
				local health_multipler_value_f = 1+health_multipler_value
				
				print("[debug][ancients scaling] Increasing spawned ancient health by: " .. health_multipler_value_f )
			
				local unit_health_a = unit:GetMaxHealth()
				local new_health_a = unit_health_a*health_multipler_value_f
				unit:SetMaxHealth( new_health_a )
				unit:SetBaseMaxHealth( new_health_a )
				unit:Heal( new_health_a, unit )

				local min_dmg = unit:GetBaseDamageMin()
				local max_dmg = unit:GetBaseDamageMax()
				local min_dmg_scaled = min_dmg*health_multipler_value_f
				local max_dmg_scaled = min_dmg*health_multipler_value_f
				unit:SetBaseDamageMin( min_dmg_scaled )
				unit:SetBaseDamageMax( max_dmg_scaled )
				local default_scale = unit:GetModelScale()
				local adjusted_scale = default_scale*health_multipler_value_f
				unit:SetModelScale( adjusted_scale )

			else
			end



		else
		end
	else
	end
end



function resolve_distant_location(location)
	local player_location = location
	local spawn_point = player_location + random_offset(roll)
	return spawn_point
end

function get_validated_spawn_location()
	local gamemode = GameRules:GetGameModeEntity()
	local player_hero_vector = gamemode.player_hero:GetAbsOrigin()	

	
	local fresh_spawn_location = generate_unvalidated_spawn_location(player_hero_vector)
	local bspawnvalid = validate_spawn_location(fresh_spawn_location, player_hero_vector)

	if bspawnvalid == true then
		gamemode.last_validated_spawn_location = fresh_spawn_location
		return fresh_spawn_location
	else
		if gamemode.last_validated_spawn_location then
			return gamemode.last_validated_spawn_location
		else
			print("[debug] backup spawn location not found. This should only every occur once per game.")
			return get_validated_spawn_location()
		end
	end
end

function generate_unvalidated_spawn_location(player_location_vector)
	local player_location = player_location_vector
	local spawn_location = player_location + random_offset()
	return spawn_location
end

-- returns a boolean value whether or not the spawn position is worthy of use for gameplay purposes.
function validate_spawn_location(spawn_location_vector, player_location_vector)
	local spawn_location = spawn_location_vector
	local player_location = player_location_vector

	local nearby_tree_radius = SA_SPAWN_VALIDATATION_TREE_RADIUS
	local max_walk_distance = CU_MIN_SPAWN_DISTANCE*SA_SPAWN_MAX_WALK_DISTANCE_MULTIPLIER
	local path_distance = GridNav:FindPathLength( spawn_location, player_location )

	if GridNav:IsNearbyTree( spawn_location, nearby_tree_radius, true ) == false and
		GridNav:CanFindPath( spawn_location, player_location ) == true and
		path_distance <= max_walk_distance and
		GridNav:IsTraversable( spawn_location ) == true and
		GridNav:IsBlocked( spawn_location ) == false then
		return true
	else
		print("[debug][gridnav] spawn point failed validation")
		return false
	end
end

function random_offset()
	local offset_value = CU_MIN_SPAWN_DISTANCE
	-- since we want to spawn enemies out of visual range at the N, NE, E, SE, S, SW, W, NW locations
	local rint = RandomInt(1,8)
	if rint then
		if rint == 1 then
			-- attempt to spawn at the N position relative to player

			local offset = Vector( 0, offset_value, 0 )
			return offset
		elseif rint == 2 then
			-- attempt to spawn at the NE position relative to player
			local offset = Vector( offset_value, offset_value, 0 )
			return offset

		elseif rint == 3 then
			-- attempt to spawn at the E position relative to player
			local offset = Vector( offset_value, 0, 0 )
			return offset

		elseif rint == 4 then
			-- attempt to spawn at the SE position relative to player
			local offset = Vector( offset_value, -offset_value, 0 )
			return offset

		elseif rint == 5 then
			-- attempt to spawn at the S position relative to player
			local offset = Vector( 0, -offset_value, 0 )
			return offset

		elseif rint == 6 then
			-- attempt to spawn at the SW position relative to player
			local offset = Vector( -offset_value, -offset_value, 0 )
			return offset

		elseif rint == 7 then
			-- attempt to spawn at the W position relative to player
			local offset = Vector( -offset_value, 0, 0 )
			return offset

		elseif rint == 8 then
			-- attempt to spawn at the NW position relative to player
			local offset = Vector( -offset_value, offset_value, 0 )
			return offset

        else
		end
	else
	end
end


function get_next_wave_timer()
	local gamemode = GameRules:GetGameModeEntity()
	local countdown_increment = DEFAULT_COUNTDOWN_INCREMENT_VALUE
	local min_countdown_increment = MINIMUM_COUNTDOWN_INCREMENT_VALUE

	if gamemode.current_countdown == nil then
		gamemode.current_countdown = DEFAULT_STARTING_TIMER_VALUE
		print("[debug] current_countdown initalized for: " .. gamemode.current_countdown)
		return gamemode.current_countdown
	else
		local current_countdown = gamemode.current_countdown
		local desired_countdown = current_countdown - countdown_increment
		if desired_countdown > min_countdown_increment then
			print("[debug] gamemode.current_countdown: " .. gamemode.current_countdown)
			gamemode.current_countdown = desired_countdown
			return gamemode.current_countdown
		else
			print("[debug] gamemode.current_countdown: " .. min_countdown_increment)
			return min_countdown_increment
		end 
	end
end

function get_next_ancient_wave_timer()
	local gamemode = GameRules:GetGameModeEntity()
	local countdown_increment = DEFAULT_ANCIENT_COUNTDOWN_INCREMENT_VALUE
	local min_countdown_increment = MINIMUM_ANCIENT_COUNTDOWN_INCREMENT_VALUE

	if gamemode.current_countdown_ancient == nil then
		gamemode.current_countdown_ancient = DEFAULT_ANCIENT_STARTING_TIMER_VALUE
		print("[debug] current_countdown_ancient initalized for: " .. gamemode.current_countdown_ancient)
		return gamemode.current_countdown_ancient
	else
		local current_countdown = gamemode.current_countdown_ancient
		local desired_countdown = current_countdown - countdown_increment
		if desired_countdown > min_countdown_increment then
			print("[debug] gamemode.current_countdown_ancient: " .. gamemode.current_countdown_ancient)
			gamemode.current_countdown_ancient = desired_countdown
			return gamemode.current_countdown_ancient
		else
			print("[debug] gamemode.current_countdown_ancient: " .. min_countdown_increment)
			return min_countdown_increment
		end 
	end
end


function get_sa_unit_name(int) -- 1 creep, 2 neutral small, 3 neutral medium, 4 neutral large, 5 ancient, 6 boss/roshan
	local type_f = int
	if type_f == 1 then

		local ranged_chance = CU_RANGED_CREEP_SPAWN_CHANCE
		local flag_chance = CU_FLAG_CREEP_SPAWN_CHANCE
		local cata_chance = CU_CATA_CREEP_SPAWN_CHANCE		

		local roll_ranged = RandomInt(0, ranged_chance)
		local roll_flag = RandomInt(0, flag_chance)
		local roll_cata = RandomInt(0, cata_chance)

		local roll_type = RandomInt(0, 100)
		print("[debug] roll_type: " .. roll_type)

		if roll_type <= roll_ranged then 
			-- select from ranged creep
			return get_appropriate_ranged_creep()
		elseif roll_type <= roll_flag then 
			-- select from flagbearer creep
			return get_appropriate_flagbearer_creep()
		elseif roll_type <= roll_cata then 
			-- select from cata creep
			return get_appropriate_cat_creep()
		else 
			-- return a melee creep!
			return get_appropriate_melee_creep()
		end
	elseif type_f == 2 then
		return get_appropriate_small_neutral()		

	elseif type_f == 3 then
		return get_appropriate_medium_neutral()		

	elseif type_f == 4 then
		return get_appropriate_large_neutral()		

	elseif type_f == 5 then
		return get_appropriate_ancient_neutral()		
	else
	end
end


function increment_creep_counter()
	local gamemode = GameRules:GetGameModeEntity()

	if gamemode.creep_counter then
		gamemode.creep_counter = gamemode.creep_counter+1
	else
		gamemode.creep_counter = 1
	end
end

function decrement_creep_counter()
	local gamemode = GameRules:GetGameModeEntity()

	if gamemode.creep_counter then
		gamemode.creep_counter = gamemode.creep_counter-1
		return gamemode.creep_counter
	else
		gamemode.creep_counter = 0
		return gamemode.creep_counter
	end
end

function get_creep_count()
	local gamemode = GameRules:GetGameModeEntity()

	if gamemode.creep_counter then
		return gamemode.creep_counter
	else
		print("[debug] get_creep_count() has failed to detect gamemode.creep_counter, setting to 0")
		gamemode.creep_counter = 0
		return gamemode.creep_counter
	end
end

function get_ancient_count()
	local gamemode = GameRules:GetGameModeEntity()

	if gamemode.ancient_counter then
		return gamemode.ancient_counter
	else
		print("[debug] get_ancient_count() has failed to detect gamemode.ancient_counter, setting to 0")
		gamemode.ancient_counter = 0
		return gamemode.ancient_counter
	end
end


function increment_ancient_counter()
	local gamemode = GameRules:GetGameModeEntity()

	if gamemode.ancient_counter then
		gamemode.ancient_counter = gamemode.ancient_counter+1
	else
		gamemode.ancient_counter = 1
	end
end

function decrement_ancient_counter()
	local gamemode = GameRules:GetGameModeEntity()

	if gamemode.ancient_counter then
		gamemode.ancient_counter = gamemode.ancient_counter-1
		return gamemode.ancient_counter
	else
		gamemode.ancient_counter = 0
		return gamemode.ancient_counter
	end
end


function get_appropriate_ranged_creep()
	local gametime = GameRules:GetDOTATime(false,false)
	if gametime >= CU_START_MEGA_CREEPS then
		return "npc_dota_creep_badguys_ranged_upgraded_mega"
	elseif gametime >= CU_START_UPGRADED_CREEPS then
		return "npc_dota_creep_badguys_ranged_upgraded"
	else
		return "npc_dota_creep_badguys_ranged"
	end
end

function get_appropriate_flagbearer_creep()
	local gametime = GameRules:GetDOTATime(false,false)
	if gametime >= CU_START_MEGA_CREEPS then
		return "npc_dota_creep_badguys_flagbearer_upgraded_mega"
	elseif gametime >= CU_START_UPGRADED_CREEPS then
		return "npc_dota_creep_badguys_flagbearer_upgraded"
	else
		return "npc_dota_creep_badguys_flagbearer"
	end
end

function get_appropriate_cat_creep()
	local gametime = GameRules:GetDOTATime(false,false)
	if gametime >= CU_START_MEGA_CREEPS then
		return "npc_dota_badguys_siege_upgraded_mega"
	elseif gametime >= CU_START_UPGRADED_CREEPS then
		return "npc_dota_badguys_siege_upgraded"
	else
		return "npc_dota_badguys_siege"
	end
end

function get_appropriate_melee_creep()
	local gametime = GameRules:GetDOTATime(false,false)
	if gametime >= CU_START_MEGA_CREEPS then
		return "npc_dota_creep_badguys_melee_upgraded_mega"
	elseif gametime >= CU_START_UPGRADED_CREEPS then
		return "npc_dota_creep_badguys_melee_upgraded"
	else
		return "npc_dota_creep_badguys_melee"
	end
end

function get_appropriate_small_neutral()
	-- There are 6 types small neutral spawns
	-- kobold camp, Hill Troll camp, Hill Troll + kobold camp, Voul Assassin camp, ghost camp, harpy camp
	local camp_roll = RandomInt(1, 6)
	if camp_roll == 1 then
		-- Kobold camp
		-- 3x kobold, 1x tunneler, 1x taskmaster
		-------------------------------------
		--"npc_dota_neutral_kobold"
		--"npc_dota_neutral_kobold_tunneler"
		--"npc_dota_neutral_kobold_taskmaster"

		local camp_specific_roll = RandomInt(1,5)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_kobold"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_kobold"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_kobold"
		elseif camp_specific_roll == 4 then
			return "npc_dota_neutral_kobold_tunneler"
		elseif camp_specific_roll == 5 then
			return "npc_dota_neutral_kobold_taskmaster"
		else
		end

	elseif camp_roll == 2 then
		-- small - Hill Troll camp
		--2x berseker, 1x priest
		--------------------------------------
		--"npc_dota_neutral_forest_troll_berserker"	
		--"npc_dota_neutral_forest_troll_high_priest"	
		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_forest_troll_berserker"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_forest_troll_berserker"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_forest_troll_high_priest"
		else
		end

	elseif camp_roll == 3 then
		-- Hill troll + kobold camp
		-- small - Hill Troll + kobol camp
		-- 2x berseker, 1x taskmaster
		---------------------------------------
		--"npc_dota_neutral_forest_troll_berserker"	
		--"npc_dota_neutral_kobold_taskmaster"
		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_forest_troll_berserker"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_forest_troll_berserker"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_kobold_taskmaster"
		else
		end

	elseif camp_roll == 4 then
		-- Voul assassin camp
		-- small - Voul Assassin camp
		-- 3x Voul Assassin
		--------------------------------------
		--"npc_dota_neutral_gnoll_assassin"	
		return "npc_dota_neutral_gnoll_assassin"

	elseif camp_roll == 5 then
		-- small - ghost camp
		-- 2x fel beast(grey ghost allegegly) 1x ghost
		---------------------------------------
		--"npc_dota_neutral_fel_beast"
		--"npc_dota_neutral_ghost"	
		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_fel_beast"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_fel_beast"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_ghost"
		else
		end

	elseif camp_roll == 6 then
		-- small - harpy camp
		-- 2x harpy scout 1x harpy stormcrafter
		---------------------------------------
		--"npc_dota_neutral_harpy_scout"	
		--"npc_dota_neutral_harpy_storm"	
		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_harpy_scout"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_harpy_scout"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_harpy_storm"
		else
		end

	else
	end
end

function get_appropriate_medium_neutral()

	-- There are 5 types medium neutral spawns
	-- Centaur camp, wolf camp, Satyr camp, Ogre camp, Golem camp
	local camp_roll = RandomInt(1, 5)
	if camp_roll == 1 then
		--# Medium - Centaur camp
		--# 1x centaur courser 1x centaur conquerer
		--"npc_dota_neutral_centaur_outrunner"
		--"npc_dota_neutral_centaur_khan"
		local camp_specific_roll = RandomInt(1,2)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_centaur_outrunner"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_centaur_khan"
		else
		end

	elseif camp_roll == 2 then
		--# Medium - wolf camp
		--# 2x giant wolf 1x alpha wolf
		--"npc_dota_neutral_giant_wolf"
		--"npc_dota_neutral_alpha_wolf"
		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_giant_wolf"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_giant_wolf"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_alpha_wolf"
		else
		end

	elseif camp_roll == 3 then
		--# Medium - Satyr camp
		--# 2x Satyr banisher 2x Satyr Mindstealer
		--#-------------------------------------
		--"npc_dota_neutral_satyr_trickster"	
		--"npc_dota_neutral_satyr_soulstealer"
		local camp_specific_roll = RandomInt(1,2)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_satyr_trickster"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_satyr_soulstealer"
		else
		end

	elseif camp_roll == 4 then
		--# Medium - Ogre camp
		--# 2x Ogre Brusier 1x Ogre Magic 
		--#-------------------------------------
		--"npc_dota_neutral_ogre_mauler"
		--"npc_dota_neutral_ogre_magi"
		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_ogre_mauler"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_ogre_mauler"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_ogre_magi"
		else
		end


	elseif camp_roll == 5 then
		--#-------------------------------------
		--# Medium - Golem camp
		--# 2x Mud golem
		--#-------------------------------------
		--"npc_dota_neutral_mud_golem"
		--	"npc_dota_neutral_mud_golem_split"
		local camp_specific_roll = RandomInt(1,2)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_mud_golem"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_mud_golem"
		else
		end
	else
	end


end

function get_appropriate_large_neutral()
	local camp_roll = RandomInt(1, 5)
	if camp_roll == 1 then
		--#-------------------------------------
		--# Large - Centaur camp
		--# 2x Centaur Courser 1x Centaur Conquerer
		--#-------------------------------------
		--"npc_dota_neutral_centaur_outrunner"
		--"npc_dota_neutral_centaur_khan"

		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_centaur_outrunner"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_centaur_outrunner"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_centaur_khan"
		else
		end

	elseif camp_roll == 2 then
		--#-------------------------------------
		--# Large - Satyr camp
		--# 1x Satyr Banisher 1x Satyr Mindstealer 1x Satyr Tormentor
		--#-------------------------------------
		--"npc_dota_neutral_satyr_trickster"	
		--"npc_dota_neutral_satyr_soulstealer"
		--"npc_dota_neutral_satyr_hellcaller"

		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_satyr_trickster"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_satyr_soulstealer"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_satyr_hellcaller"
		else
		end

	elseif camp_roll == 3 then
		--#-------------------------------------
		--# Large - Wildwing camp
		--# 2x Wildwing 1x Wildwing ripper
		--#-------------------------------------
		--"npc_dota_neutral_wildkin"
		--"npc_dota_neutral_enraged_wildkin"
		local camp_specific_roll = RandomInt(1,2)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_wildkin"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_enraged_wildkin"
		else
		end

	elseif camp_roll == 4 then
		--#-------------------------------------
		--# Large - Troll camp
		--# 2x Hill Troll 1x Dark troll summoner +3 spawned Skeleton warrior
		--#-------------------------------------
		--"npc_dota_neutral_dark_troll_warlord"		Summoner
		--"npc_dota_neutral_dark_troll"	
		--"npc_dota_dark_troll_warlord_skeleton_warrior"

		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_dark_troll_warlord"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_dark_troll"
		elseif camp_specific_roll == 3 then
			return "npc_dota_dark_troll_warlord_skeleton_warrior"
		else
		end

	elseif camp_roll == 5 then
		--#-------------------------------------
		--# Large - Warpine camp
		--# 2x Warpine raider
		--#-------------------------------------
		--"npc_dota_neutral_warpine_raider"
		return "npc_dota_neutral_warpine_raider"
	else
	end
end

function get_appropriate_ancient_neutral()

	local camp_roll = RandomInt(1, 4)
	if camp_roll == 1 then
		--#-------------------------------------
		--# Ancient - Dragon camp
		--# 2x Ancient black drake 1x Ancient black dragon
		--#-------------------------------------
		--"npc_dota_neutral_black_drake"	
		--"npc_dota_neutral_black_dragon"	
		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_black_drake"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_black_drake"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_black_dragon"
		else
		end

	elseif camp_roll == 2 then
		return	"npc_dota_neutral_granite_golem"

	elseif camp_roll == 3 then
		--#-------------------------------------
		--# Ancient - Thunderhide camp
		--# 2x Ancient rumblehide 1x Ancient thunderhide
		--#-------------------------------------
		--"npc_dota_neutral_big_thunder_lizard"
		--"npc_dota_neutral_small_thunder_lizard"
		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_big_thunder_lizard"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_big_thunder_lizard"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_small_thunder_lizard"
		else
		end

	elseif camp_roll == 4 then
		--#-------------------------------------
		--# Ancient - Frostbitten camp
		--# 2x Ancient frostbitten golem  1x Ancient ice shaman
		--#-------------------------------------
		--"npc_dota_neutral_ice_shaman"
		--"npc_dota_neutral_frostbitten_golem"
		local camp_specific_roll = RandomInt(1,3)
		if camp_specific_roll == 1 then
			return "npc_dota_neutral_frostbitten_golem"
		elseif camp_specific_roll == 2 then
			return "npc_dota_neutral_frostbitten_golem"
		elseif camp_specific_roll == 3 then
			return "npc_dota_neutral_ice_shaman"
		else
		end
	else
	end
end

function attack_hero(event)
	local caster = event.caster
	local ability = event.ability
	local gamemode = GameRules:GetGameModeEntity()

	if gamemode then
		local player_hero = gamemode.player_hero
		caster:MoveToTargetToAttack( player_hero )
	else
	end

end

function get_timed_creepname()
	local gametime = GameRules:GetDOTATime(false,false)
	--CU_START_MEDIUM_NEUTRALS = 6*60
	--CU_START_HARD_NEUTRALS = 10*60
	local neutral_chance = CU_NEUTRAL_CHANCE_PCT
	local neutraldice = RandomInt( 0, 100 )
	
	if neutraldice <= neutral_chance then
		if gametime >= CU_START_HARD_NEUTRALS then
			return 4
		elseif gametime >= CU_START_MEDIUM_NEUTRALS then
			return 3
		else
			return 2
		end
	else
		return 1
	end	 
end

