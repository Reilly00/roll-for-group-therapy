RollFor = RollFor or {}
local m = RollFor
m.base64 = { encode = m.encode_base64, decode = m.decode_base64 }

---@diagnostic disable-next-line: undefined-global
local lib_stub = LibStub
local version = m.get_addon_version()

local M = {}

function M.import_encoded_softres_data() end


local getn = m.getn
local info = m.pretty_print
local hl = m.colors.highlight
local RollSlashCommand = m.Types.RollSlashCommand

local function clear_data()
  M.softres_gui.clear()
  M.name_matcher.clear( true )
  M.softres.clear( true )
  M.minimap_button.set_icon( M.minimap_button.ColorType.White )
  M.winner_tracker.clear()
end

local function update_minimap_icon()
  local result = M.softres_check.check_softres( true )

  if result == M.softres_check.ResultType.NoItemsFound then
    M.minimap_button.set_icon( M.minimap_button.ColorType.White )
  elseif result == M.softres_check.ResultType.SomeoneIsNotSoftRessing then
    M.minimap_button.set_icon( M.minimap_button.ColorType.Orange )
  elseif result == M.softres_check.ResultType.FoundOutdatedData then
    M.minimap_button.set_icon( M.minimap_button.ColorType.Red )
  else
    M.minimap_button.set_icon( M.minimap_button.ColorType.Green )
  end
end

local function on_softres_status_changed()
  update_minimap_icon()
end

local function trade_complete_callback( recipient_name, items_given, items_received )
  for i = 1, getn( items_given ) do
    local item = items_given[ i ]
    if item then
      local item_id = M.item_utils.get_item_id( item.link )
      local item_name = item_id and M.dropped_loot.get_dropped_item_name( item_id )

      if item_id and item_name then
        M.loot_award_callback.on_loot_awarded( item_id, item.link, recipient_name )
      end
    end
  end

  for i = 1, getn( items_received ) do
    local item = items_received[ i ]

    if item then
      local item_id = M.item_utils.get_item_id( item.link )

      if item_id and M.awarded_loot.has_item_been_awarded( recipient_name, item_id ) then
        M.unaward_item( recipient_name, item_id, item.link )
      end
    end
  end
end

local function create_components()
  ---@type AceTimer
  M.ace_timer = lib_stub( "AceTimer-3.0" )

  local db = m.Db.new( M.char_db )

  ---@type EventBus
  M.config_event_bus = m.EventBus.new()

  ---@type Config
  M.config = m.Config.new( db( "config" ), M.config_event_bus )

  local classic = M.config.classic_look()
  local popup_bottom_margin, popup_bottom_button_margin = classic and 37 or 24, classic and 14 or 7
  local popup_side_margin = classic and 50 or 35
  local popup_builder_factory = classic and m.PopupBuilder.classic or m.PopupBuilder.modern

  ---@type fun(): PopupBuilder
  ---@param bottom_margin number?
  ---@param side_margin number?
  local function popup_builder( bottom_margin, side_margin )
    return popup_builder_factory( m.FrameBuilder, bottom_margin or popup_bottom_margin, popup_bottom_button_margin, side_margin or popup_side_margin )
  end

  ---@type UiReloadPopup
  M.ui_reload_popup = m.UiReloadPopup.new( popup_builder( classic and 37 or 27 ), M.config )

  M.api = function() return m.api end

  ---@type PlayerInfo
  M.player_info = m.PlayerInfo.new( M.api() )

  ---@type GroupRoster
  M.group_roster = m.GroupRoster.new( M.api(), M.player_info )

  M.chat_api = m.ChatApi.new()

  ---@type Chat
  M.chat = m.Chat.new( M.chat_api, M.group_roster, M.player_info )

  ---@alias GroupAwareSoftResFn fun ( softres: SoftRes ): GroupAwareSoftRes
  ---@type GroupAwareSoftResFn
  M.present_softres = function( softres ) return m.SoftResPresentPlayersDecorator.new( M.group_roster, softres ) end
  ---@type GroupAwareSoftResFn
  M.absent_softres = function( softres ) return m.SoftResAbsentPlayersDecorator.new( M.group_roster, softres ) end

  ---@type ItemUtils
  M.item_utils = m.ItemUtils

  ---@type TooltipReader
  M.tooltip_reader = m.TooltipReader.new( M.api() )

  -- TODO: Add type.
  M.version_broadcast = m.VersionBroadcast.new( db( "version_broadcast" ), M.player_info, version.str )

  ---@type AwardedLoot
  M.awarded_loot = m.AwardedLoot.new( db( "awarded_loot" ) )

  -- TODO: Add type.
  M.softres_db = db( "softres" )

  -- TODO: Add type.
  M.unfiltered_softres = m.SoftRes.new( M.softres_db )

  -- TODO: Add type.
  M.name_matcher = m.NameManualMatcher.new(
    db( "name_matcher" ), M.api,
    M.absent_softres( M.unfiltered_softres ),
    m.NameAutoMatcher.new( M.group_roster, M.unfiltered_softres, 0.57, 0.4 ),
    on_softres_status_changed
  )

  ---@type SoftRes
  M.matched_name_softres = m.SoftResMatchedNameDecorator.new( M.name_matcher, M.unfiltered_softres )

  ---@type SoftRes
  M.awarded_loot_softres = m.SoftResAwardedLootDecorator.new( M.awarded_loot, M.matched_name_softres )

  ---@type GroupAwareSoftRes
  M.softres = M.present_softres( M.awarded_loot_softres )

  ---@type DroppedLoot
  M.dropped_loot = m.DroppedLoot.new( db( "dropped_loot" ) )
  M.softres_check = m.SoftResCheck.new( M.matched_name_softres, M.group_roster, M.name_matcher, M.ace_timer,
    M.absent_softres, db( "softres_check" ) )

  ---@type WinnerTracker
  M.winner_tracker = m.WinnerTracker.new( db( "winner_tracker" ) )

  ---@type LootFacade
  M.loot_facade = m.LootFacade.new( m.EventFrame.new( m.api ), m.api )

  -- TODO: Add type.
  ---@diagnostic disable-next-line: unused-local, unused-function
  local function get_dummy_items()
    ---@diagnostic disable-next-line: unused-function
    local function item_link( name, id, quality )
      local color = m.api.ITEM_QUALITY_COLORS[ quality ].hex or "|cffffffff"
      return string.format( "%s|Hitem:%s::::::::20:257::::::|h[%s]|h|r", color, id or "3299", name )
    end

    -- local ids = { 17204, 16961, 18842, 16961, 16961, 18842, 16865, 16961, 17109, 16961, 18466, 11980, 12820, 3676 }
    local ids = { 17109, 17109, 17109, 3676 }
    local result = {}
    ---@type MakeDroppedItemFn
    local make_dropped_item = m.ItemUtils.make_dropped_item
    local boe = m.ItemUtils.BindType.BindOnEquip

    ---@diagnostic disable-next-line: unused-local
    for i, item_id in ipairs( ids ) do
      local name, tooltip_link, quality, texture

      if m.vanilla then
        name, tooltip_link, quality, _, _, _, _, _, texture = m.api.GetItemInfo( item_id )
      else
        name, tooltip_link, quality, _, _, _, _, _, _, texture = m.api.GetItemInfo( item_id )
      end

      local link = item_link( name, item_id, quality )
      local item = make_dropped_item( item_id, name, link, tooltip_link, quality, 1, texture, boe )

      table.insert( result, item )
    end

    table.sort( result, function( a, b ) return a.quality > b.quality end )

    return result
  end

  -- Enable this for testing in game. It will replace dropped items with the above.
  local mock_items = false

  ---@type LootList
  M.raw_loot_list = m.LootList.new( M.loot_facade, M.item_utils, M.tooltip_reader, mock_items and get_dummy_items or nil )

  ---@type SoftResLootList
  M.loot_list = m.SoftResLootListDecorator.new( M.raw_loot_list, M.softres )

  ---@type MasterLootCandidates
  M.master_loot_candidates = m.MasterLootCandidates.new( M.api(), M.group_roster, M.raw_loot_list ) -- remove group_roster for testing (dummy candidates)

  ---@type MasterLootCandidateSelectionFrame
  M.player_selection_frame = m.MasterLootCandidateSelectionFrame.new( m.FrameBuilder, M.config )

  local rolling_popup_db = db( "rolling_popup" )

  ---@type RollingPopupContentTransformer
  local rolling_popup_content_transformer = m.RollingPopupContentTransformer.new( M.config )

  ---@type RollingPopup
  M.rolling_popup = m.RollingPopup.new(
    popup_builder(),
    rolling_popup_content_transformer,
    rolling_popup_db,
    M.config
  )

  ---@type LootFrameSkin
  local skin = M.config.classic_look() and m.OgLootFrameSkin.new( m.FrameBuilder ) or m.ModernLootFrameSkin.new( m.FrameBuilder )

  ---@type LootFrame
  M.loot_frame = m.LootFrame.new(
    skin,
    db( "loot_frame" ),
    M.config
  )

  ---@type LootAwardPopup
  M.loot_award_popup = m.LootAwardPopup.new(
    popup_builder( classic and 38 or 30, classic and 65 or 55 ),
    M.config,
    M.rolling_popup
  )

  ---@type RollController
  M.roll_controller = m.RollController.new(
    M.master_loot_candidates,
    M.softres,
    M.loot_list,
    M.config,
    M.rolling_popup,
    M.loot_award_popup,
    M.player_selection_frame
  )

  ---@type LootAwardCallback
  M.loot_award_callback = m.LootAwardCallback.new( M.awarded_loot, M.roll_controller, M.winner_tracker, M.group_roster )

  ---@type MasterLoot
  M.master_loot = m.MasterLoot.new(
    M.master_loot_candidates,
    M.loot_award_callback,
    M.loot_list,
    M.roll_controller
  )

  ---@type AutoLoot
  M.auto_loot = m.AutoLoot.new( M.loot_list, M.api, db( "auto_loot" ), M.config, M.player_info )

  ---@type DroppedLootAnnounce
  M.dropped_loot_announce = m.DroppedLootAnnounce.new(
    M.loot_list,
    M.chat,
    M.dropped_loot,
    M.softres,
    M.winner_tracker,
    M.player_info,
    M.auto_loot,
    M.config
  )

  -- TODO: Add type.
  M.softres_gui = m.SoftResGui.new( M.api, M.import_encoded_softres_data, M.softres_check, M.softres, clear_data, M.dropped_loot_announce.reset )

  -- TODO: Add type.
  M.trade_tracker = m.TradeTracker.new( M.ace_timer, M.chat, trade_complete_callback )

  -- TODO: Add type.
  M.usage_printer = m.UsagePrinter.new( M.chat )

  -- TODO: Add type.
  M.minimap_button = m.MinimapButton.new( M.api, db( "minimap_button" ), M.softres_gui.toggle, M.softres_check, M.config )

  -- TODO: Add type.
  M.master_loot_warning = m.MasterLootWarning.new( M.api, M.config, m.BossList.zones, M.player_info )

  -- TODO: Add type.
  M.new_group_event = m.NewGroupEvent.new( M.group_roster )

  -- TODO: Add type.
  M.auto_group_loot = m.AutoGroupLoot.new( M.loot_list, M.config, m.BossList.zones, M.player_info )

  -- TODO: Add type.
  M.auto_master_loot = m.AutoMasterLoot.new( M.config, m.BossList.zones, M.player_info )

  -- TODO: Add type.
  M.softres_roll_gui_data = m.SoftResRollGuiData.new( M.softres, M.group_roster )

  -- TODO: Add type.
  M.tie_roll_gui_data = m.TieRollGuiData.new( M.group_roster )

  -- TODO: Add type.
  M.welcome_popup = m.WelcomePopup.new( m.FrameBuilder, M.ace_timer, db( "welcome_popup" ) )

  -- TODO: Add type.
  M.roll_for_ad = m.RollForAd.new( M.player_info )

  ---@type RollingStrategyFactory
  M.rolling_strategy_factory = m.RollingStrategyFactory.new(
    M.group_roster,
    M.loot_list,
    M.master_loot_candidates,
    M.chat,
    M.ace_timer,
    M.winner_tracker,
    M.config,
    M.softres,
    M.player_info
  )

  ---@type RollingLogic
  M.rolling_logic = m.RollingLogic.new(
    M.chat,
    M.ace_timer,
    M.roll_controller,
    M.rolling_strategy_factory,
    M.master_loot_candidates,
    M.winner_tracker,
    M.config
  )

  M.loot_controller = m.LootController.new(
    M.player_info,
    M.loot_facade,
    M.loot_list,
    M.loot_frame,
    M.roll_controller,
    M.softres,
    M.rolling_logic,
    M.chat
  )

  ---@type ArgsParser
  M.args_parser = m.ArgsParser.new( m.ItemUtils, M.config )

  -- TODO: Add type.
  M.roll_result_announcer = m.RollResultAnnouncer.new( M.chat, M.roll_controller, M.softres, M.config )

  M.loot_facade_listener = m.LootFacadeListener.new(
    M.loot_facade,
    M.auto_loot,
    M.dropped_loot_announce,
    M.master_loot,
    M.auto_group_loot,
    M.roll_controller,
    M.player_info
  )

  M.sandbox = m.Sandbox.new()
  M.srplus_gui = m.SrPlusGui.new(M.api, M.import_encoded_softres_data)
end

local function subscribe_for_component_events()
  M.config.subscribe( "show_ml_warning", function( enabled )
    if enabled then
      M.master_loot_warning.on_player_target_changed()
    else
      M.master_loot_warning.hide()
    end
  end )

  M.new_group_event.subscribe( function()
    M.awarded_loot.clear()
    M.dropped_loot.clear()
  end )

  M.config_event_bus.subscribe( "config_change_requires_ui_reload", function()
    M.ui_reload_popup.show()
  end )
end

function M.import_softres_data( softres_data )
  M.unfiltered_softres.import( softres_data )
  M.name_matcher.auto_match()
end

function M.import_encoded_softres_data(data, data_loaded_callback)
  local sr = m.SoftRes
  local softres_data = sr.decode(data)

  if not softres_data and data and string.len(data) > 0 then
    info("Could not load soft-res data!", m.colors.red)
    return
  elseif not softres_data then
    M.minimap_button.set_icon(M.minimap_button.ColorType.White)
    return
  end
  
  -- ✅ Check if this is an SR+ manual export (restore mode)
  local is_srplus_restore = softres_data.metadata and softres_data.metadata.id == "srplus-manual-export"
  
  if is_srplus_restore then
    info("Restoring SR+ history from export...", m.colors.yellow)
    
    -- ✅ RESTORE MODE: Replace existing data entirely
    M.db.total_sr_weeks = softres_data.metadata.total_sr_weeks or 0
    M.db.sr_history = {}
    M.db.imported_sheet_ids = M.db.imported_sheet_ids or {}
    
    -- ✅ Rebuild SR+ history from the exported counts
    for _, entry in ipairs(softres_data.softreserves or {}) do
      local player = entry.name
      local items = entry.items or {}
      
      M.db.sr_history[player] = {}
      
      for _, item in ipairs(items) do
        if item.id and item.count then
          M.db.sr_history[player][item.id] = item.count
        end
      end
    end
    
    info("SR+ history restored successfully!")
    
  else
    -- ✅ NORMAL IMPORT MODE: Add new week
    
    -- Set total weeks from metadata if available
    if softres_data.metadata and softres_data.metadata.total_sr_weeks then
      M.db.total_sr_weeks = softres_data.metadata.total_sr_weeks
    end

    -- ✅ Make sure storage exists
    M.db.sr_history = M.db.sr_history or {}
    M.db.imported_sheet_ids = M.db.imported_sheet_ids or {}

    -- ✅ Check if this sheet has already been imported
    local metadata_id = softres_data.metadata and softres_data.metadata.id
    if metadata_id and M.db.imported_sheet_ids[metadata_id] then
      info("This RaidRes sheet has already been imported. Skipping duplicate.", m.colors.orange)
      return
    end

    -- ✅ Store the ID so it won't be processed again
    if metadata_id then
      M.db.imported_sheet_ids[metadata_id] = true
    end
    
    -- ✅ Increment total SR import weeks
    M.db.total_sr_weeks = (M.db.total_sr_weeks or 0) + 1

    -- ✅ SR+ tracking logic for new imports
    if softres_data.softreserves then
      for _, entry in ipairs(softres_data.softreserves) do
        local player = entry.name
        local items = entry.items or {}

        -- Convert list to map for fast lookup
        local current_items = {}
        for _, item in ipairs(items) do
          if item.id then
            current_items[item.id] = true
          end
        end

        -- Ensure player's history table exists
        M.db.sr_history[player] = M.db.sr_history[player] or {}

        -- Reset streaks for any previously tracked items that aren't reserved this week
        for item_id, count in pairs(M.db.sr_history[player]) do
          if not current_items[item_id] then
            M.db.sr_history[player][item_id] = 0
          end
        end

        -- Update/add streaks for this week's items
        for item_id, _ in pairs(current_items) do
          if M.db.sr_history[player][item_id] == nil or M.db.sr_history[player][item_id] == 0 then
            M.db.sr_history[player][item_id] = 1
          else
            M.db.sr_history[player][item_id] = M.db.sr_history[player][item_id] + 1
          end
        end
      end
    end
    
    info("Soft-res data loaded successfully!")
  end

  -- 🚀 Import the softres data for the UI
  M.import_softres_data(softres_data)
  
  if data_loaded_callback then data_loaded_callback(softres_data) end
  update_minimap_icon()
end

local function on_roll_command( roll_slash_command )
  return function( args )
    if M.rolling_logic.is_rolling() then
      M.chat.info( "Rolling is in progress." )
      return
    end

    if string.find( args, "^debug" ) then
      m.DebugBuffer.on_command( args )
      return
    end

    if string.find( args, "^config" ) then
      M.config.on_command( args )
      return
    end

    if args == "versioncheck guild" then
      M.version_broadcast.guild_version_request()
      return
    end

    if not M.api().IsInGroup() then
      M.chat.info( "Not in a group." )
      return
    end

    if args == "versioncheck" then
      M.version_broadcast.group_version_request()
      return
    end

    local item, count, seconds, message = M.args_parser.parse( args )

    if not item then
      M.usage_printer.print_usage( roll_slash_command )
      return
    end

    local strategy_type = m.Types.slash_command_to_strategy_type( roll_slash_command )

    if not strategy_type then
      info( string.format( "Unsupported command: %s", hl( roll_slash_command and roll_slash_command.slash_command or "?" ) ) )
      return
    end

    if M.softres.is_item_hardressed( item.id ) then
      M.roll_controller.preview( item, count )
      return
    end

    M.roll_controller.start( strategy_type, item, count, seconds, message )
  end
end

local function on_show_sorted_rolls_command( args )
  if M.rolling_logic.is_rolling() then
    info( "Rolling is in progress." )
    return
  end

  if args then
    for limit in string.gmatch( args, "(%d+)" ) do
      M.rolling_logic.show_sorted_rolls( tonumber( limit ) )
      return
    end
  end

  M.rolling_logic.show_sorted_rolls( 5 )
end

local function is_rolling_check( f )
  ---@diagnostic disable-next-line: unused-vararg
  return function( ... )
    if not M.rolling_logic.is_rolling() then
      M.chat.info( "Rolling not in progress." )
      return
    end

    f( unpack( arg ) )
  end
end

local function in_group_check( f )
  return m.in_group_check( M.api(), M.chat, f )
end

local function setup_storage()
  -- Reset old AceDB configuration. I don't give a fuck :)
  if RollForDb and RollForDb.global and RollForDb.global.version then
    RollForDb = nil
  end

  RollForDb = RollForDb or {}
  RollForCharDb = RollForCharDb or {}

  M.db = RollForDb
  M.char_db = RollForCharDb

  if not M.db.version then
    M.db.version = version.str
  end
  
  
  -- Initialize SR+ history tracking if not already present
  M.db.sr_history = M.db.sr_history or {}
end

local function on_softres_command( args )
  if args == "init" then
    clear_data()
  end

  M.softres_gui.toggle()
end

local function on_roll( player_name, roll, min, max )
  local player = M.group_roster.find_player( player_name )

  if not player then
    m.err( string.format( "Player %s could not be found.", hl( player_name ) ) )
    return
  end

  M.rolling_logic.on_roll( player, roll, min, max )
end

local function on_loot_method_changed()
  M.master_loot_warning.on_party_loot_method_changed()
end

local function on_master_looter_changed( player_name )
  if M.player_info.get_name() == player_name and m.is_master_loot() then
    M.ace_timer.ScheduleTimer( M, M.config.print_raid_roll_settings, 0.1 )
  end
end

function M.on_chat_msg_system( message )
  for player_name, roll, min, max in string.gmatch( message, "([^%s]+) rolls (%d+) %((%d+)%-(%d+)%)" ) do
    on_roll( player_name, tonumber( roll ), tonumber( min ), tonumber( max ) )
    return
  end

  if string.find( message, "^Looting changed to" ) then
    on_loot_method_changed()
    return
  end

  for player_name in string.gmatch( message, "(.-) is now the loot master%." ) do
    on_master_looter_changed( player_name )
    return
  end
end

-- TODO: this can now be replaced by mocking LootList
---@diagnostic disable-next-line: unused-local, unused-function
local function simulate_loot_dropped( args )
  ---@diagnostic disable-next-line: unused-function
  local function mock_table_function( name, values )
    M.api()[ name ] = function( key )
      local value = values[ key ]

      if type( value ) == "function" then
        return value()
      else
        return value
      end
    end
  end

  ---@diagnostic disable-next-line: unused-function
  local function make_loot_slot_info( count, quality )
    local result = {}

    for i = 1, count do
      table.insert( result, function()
        if i == count then
          m.api = m.real_api
          m.real_api = nil
        end

        return nil, nil, nil, quality or 4
      end )
    end

    return result
  end

  local item_links = M.item_utils.parse_all_links( args )

  if m.real_api then
    info( "Mocking in progress." )
    return
  end

  m.real_api = m.api
  m.api = m.clone( m.api )
  M.api()[ "GetNumLootItems" ] = function() return getn( item_links ) end
  M.api()[ "UnitName" ] = function() return tostring( m.lua.time() ) end
  M.api()[ "GetLootThreshold" ] = function() return 4 end
  mock_table_function( "GetLootSlotLink", item_links )
  mock_table_function( "GetLootSlotInfo", make_loot_slot_info( getn( item_links ), 4 ) )

  M.dropped_loot_announce.on_loot_opened()
end

local function show_how_to_roll()
  M.chat.announce( "How to roll:" )
  local ms = M.config.ms_roll_threshold() ~= 100 and string.format( " (%s)", M.config.ms_roll_threshold() or "100" ) or ""

  local sr = M.softres.get_all_rollers()
  local sr_count = getn( sr )

  M.chat.announce( string.format( "For main-spec%s, type: /roll%s", sr_count > 0 and " and soft-res" or "", ms ) )
  M.chat.announce( string.format( "For off-spec, type: /roll %s", M.config.os_roll_threshold() ) )

  if M.config.tmog_rolling_enabled() then
    M.chat.announce( string.format( "For transmog, type: /roll %s", M.config.tmog_roll_threshold() ) )
  end
end

local function on_reset_dropped_loot_announce_command()
  M.dropped_loot_announce.reset()
end

local function setup_slash_commands()
  -- Roll For commands
  SLASH_RF1 = RollSlashCommand.NormalRoll
  M.api().SlashCmdList[ "RF" ] = on_roll_command( RollSlashCommand.NormalRoll )
  SLASH_ARF1 = RollSlashCommand.NoSoftResRoll
  M.api().SlashCmdList[ "ARF" ] = in_group_check( on_roll_command( RollSlashCommand.NoSoftResRoll ) )
  SLASH_RR1 = RollSlashCommand.RaidRoll
  M.api().SlashCmdList[ "RR" ] = in_group_check( on_roll_command( RollSlashCommand.RaidRoll ) )
  SLASH_IRR1 = RollSlashCommand.InstaRaidRoll
  M.api().SlashCmdList[ "IRR" ] = in_group_check( on_roll_command( RollSlashCommand.InstaRaidRoll ) )
  SLASH_HTR1 = "/htr"
  M.api().SlashCmdList[ "HTR" ] = in_group_check( show_how_to_roll )
  SLASH_CR1 = "/cr"
  M.api().SlashCmdList[ "CR" ] = is_rolling_check( M.roll_controller.cancel_rolling )
  SLASH_FR1 = "/fr"
  M.api().SlashCmdList[ "FR" ] = is_rolling_check( M.roll_controller.finish_rolling_early )
  SLASH_SSR1 = "/ssr"
  M.api().SlashCmdList[ "SSR" ] = on_show_sorted_rolls_command
  SLASH_RFR1 = "/rfr"
  M.api().SlashCmdList[ "RFR" ] = on_reset_dropped_loot_announce_command

  -- Soft Res commands
  SLASH_SR1 = "/sr"
  M.api().SlashCmdList[ "SR" ] = on_softres_command
  SLASH_SRS1 = "/srs"
  M.api().SlashCmdList[ "SRS" ] = M.softres_check.show_softres
  SLASH_SRC1 = "/src"
  M.api().SlashCmdList[ "SRC" ] = M.softres_check.check_softres
  SLASH_SRO1 = "/sro"
  M.api().SlashCmdList[ "SRO" ] = M.name_matcher.manual_match

  SLASH_RFT1 = "/rft"
  M.api().SlashCmdList[ "RFT" ] = M.sandbox.run

  SLASH_DROPPED1 = "/DROPPED"
  M.api().SlashCmdList[ "DROPPED" ] = simulate_loot_dropped
  
  -- Shows the current SR+ history table
SLASH_SRPLUS1 = "/srplus"
M.api().SlashCmdList["SRPLUS"] = function()
  local total_weeks = M.db.total_sr_weeks or 0
  m.pretty_print(string.format("== SR+ History (across %d week%s) ==", total_weeks, total_weeks == 1 and "" or "s"))

  for player, items in pairs(M.db.sr_history or {}) do
    local to_remove = {}

    -- Mark all items with 0 count for removal
    for item_id, count in pairs(items) do
      if count == 0 then
        table.insert(to_remove, item_id)
      end
    end

    -- Remove them from the table
    for _, item_id in ipairs(to_remove) do
      items[item_id] = nil
    end

    -- If player still has valid SRs, print them
    if next(items) then
      m.pretty_print(string.format("== %s ==", player))

      for item_id, count in pairs(items) do
        local name = GetItemInfo(item_id) or ("Item ID " .. item_id)
        local bonus = math.max(0, (count - 1) * 10)
        local week_str = count == 1 and "1 week" or string.format("%d weeks", count)
        local doubled = (count > total_weeks) and "D" or ""

        m.pretty_print(string.format("  %s: %s (+%d%s)", name, week_str, bonus, doubled))
      end
    end
  end

  m.pretty_print(string.format("== End of SR+ History (Total tracked weeks: %d) ==", total_weeks))
end

SLASH_DELETESR1 = "/srdelete"
M.api().SlashCmdList["DELETESR"] = function(msg)
  local player = string.gsub(msg or "", "^%s*(.-)%s*$", "%1") -- trim whitespace
  if player == "" then
    m.pretty_print("⚠️ Please specify a player name: /srdelete PlayerName", m.colors.orange)
    return
  end

  local history = M.db.sr_history or {}

  if not history[player] then
    m.pretty_print("❌ No SR+ history found for player: " .. player, m.colors.red)
    return
  end

  local deleted = {}
  for item_id, count in pairs(history[player]) do
    local name = GetItemInfo(item_id) or ("Item ID " .. item_id)
    local bonus = math.max(0, (count - 1) * 10)
    table.insert(deleted, string.format("  %s (%d weeks, +%d)", name, count, bonus))
  end

  history[player] = nil

  m.pretty_print("✅ Deleted SR+ history for player: " .. player)
  for _, line in ipairs(deleted) do
    m.pretty_print(line)
  end
end

SLASH_RESETSRPLUS1 = "/resetsrplus"
M.api().SlashCmdList["RESETSRPLUS"] = function()
  M.db.sr_history = {}
  M.db.imported_sheet_ids = {}
  M.db.total_sr_weeks = 0
  m.pretty_print("SR+ history and imported sheet IDs wiped.")
end

SLASH_EXPORTSRPLUS1 = "/exportsrplus"
M.api().SlashCmdList["EXPORTSRPLUS"] = function()
  local sr_data = {
  metadata = {
    id = "srplus-manual-export",
    total_sr_weeks = M.db.total_sr_weeks or 0
  },
  softreserves = {}
}

  local skipped = 0

  -- Safe count function
  local function count_array_entries(t)
    local count = 0
    for _, _ in ipairs(t) do count = count + 1 end
    return count
  end

  for player, items in pairs(M.db.sr_history or {}) do
    local sr_entry = { name = player, items = {} }

    for item_id, count in pairs(items) do
      table.insert(sr_entry.items, { id = item_id, count = count })
    end

    -- Try encoding the single entry to catch format issues
    local ok, err = pcall(function() return lib_stub("Json-0.1.2").encode(sr_entry) end)
    if ok then
      table.insert(sr_data.softreserves, sr_entry)
    else
      skipped = skipped + 1
      m.pretty_print(string.format("❌ Skipping player '%s' due to encode error: %s", tostring(player), tostring(err)), m.colors.red)
    end
  end

  local num_exported = count_array_entries(sr_data.softreserves)

  local json = lib_stub("Json-0.1.2")
  local success, encoded_json = pcall(json.encode, sr_data)
  if not success then
    m.pretty_print("❌ Failed to encode SR+ data! Try cleaning invalid values first.", m.colors.red)
    return
  end

  local base64 = m.base64.encode(encoded_json)
  m.pretty_print(string.format("✅ Exported SR+ data (%d players, %d skipped):", num_exported, skipped))
  m.pretty_print(base64)
end

SLASH_CLEANSRPLUS1 = "/cleansrplus"
M.api().SlashCmdList["CLEANSRPLUS"] = function()
  local cleaned = 0
  for player, items in pairs(M.db.sr_history or {}) do
    for item_id, count in pairs(items) do
      local id_num = tonumber(item_id)
      local count_num = tonumber(count)

      if not id_num or not count_num then
        M.db.sr_history[player][item_id] = nil
        cleaned = cleaned + 1
      end
    end
  end

  m.pretty_print(string.format("🧼 Cleaned %d invalid SR+ entries.", cleaned))
end

SLASH_IMPORTSRPLUS1 = "/importsrplus"
M.api().SlashCmdList["IMPORTSRPLUS"] = function()
  M.srplus_gui.toggle()
end

end

function M.on_player_login()
  setup_storage()
  create_components()
  subscribe_for_component_events()
  setup_slash_commands()

  info( string.format( "Loaded (%s).", hl( string.format( "v%s", version.str ) ) ) )

  M.version_broadcast.broadcast()
  M.import_encoded_softres_data( M.softres_db.data )
  M.softres_gui.load( M.softres_db.data )

  if M.welcome_popup.should_show() then
    M.welcome_popup.show()
  end

  ---@diagnostic disable-next-line: undefined-global
  LootFrame:UnregisterAllEvents()
  ---@diagnostic disable-next-line: undefined-global
  if pfLootFrame then pfLootFrame:UnregisterAllEvents() end
end

---@diagnostic disable-next-line: unused-local, unused-function
local function on_party_message( message, player )
  for name, roll in string.gmatch( message, "(%a+) rolls (%d+)" ) do
    on_roll( name, tonumber( roll ), 1, 100 )
  end
  for name, roll in string.gmatch( message, "(%a+) rolls os (%d+)" ) do
    on_roll( name, tonumber( roll ), 1, 99 )
  end
end

function M.unaward_item( player_name, item_id, item_link )
  M.awarded_loot.unaward( player_name, item_id )
  info( string.format( "%s returned %s.", hl( player_name ), item_link ) )
end

function M.on_group_changed()
  M.name_matcher.auto_match()
  update_minimap_icon()
end

function M.on_chat_msg_addon( name, message )
  if name ~= "RollFor" or not message then return end

  for ver in string.gmatch( message, "VERSION::(.*)" ) do
    M.version_broadcast.on_version( ver )
    return
  end

  for channel, requesting_player_name in string.gmatch( message, "VERSION_REQUEST::(.-)::(.*)" ) do
    M.version_broadcast.on_version_request( channel, requesting_player_name )
    return
  end

  for requesting_player_name, channel, their_name, their_class, their_version in string.gmatch( message, "VERSION_RESPONSE::(.-)::(.-)::(.-)::(.-)::(.*)" ) do
    M.version_broadcast.on_version_response( requesting_player_name, channel, their_name, their_class, their_version )
    return
  end
end

m.EventHandler.handle_events( M )
return M