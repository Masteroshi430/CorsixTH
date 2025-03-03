--[[ Copyright (c) 2009 Peter "Corsix" Cawley

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. --]]

corsixth.require("dialogs.place_objects")

class "UIEditRoom" (UIPlaceObjects)

---@type UIEditRoom
local UIEditRoom = _G["UIEditRoom"]

function UIEditRoom:UIEditRoom(ui, room_type)

  -- NB: UIEditRoom:onCursorWorldPositionChange is called by the UIPlaceObjects
  -- constructor, hence the initialisation of required fields prior to the call.
  self.UIPlaceObjects(self, ui)

  local app = ui.app
  local blue_red_swap = self.anims.Alt32_BlueRedSwap
  -- Set alt palette on wall blueprint to make it red
  self.anims:setAnimationGhostPalette(124, app.gfx:loadGhost("QData", "Ghost1.dat", 6), blue_red_swap)
  -- Set on door and window blueprints too
  self.anims:setAnimationGhostPalette(126, app.gfx:loadGhost("QData", "Ghost1.dat", 6), blue_red_swap)
  self.anims:setAnimationGhostPalette(130, app.gfx:loadGhost("QData", "Ghost1.dat", 6), blue_red_swap)
  self.cell_outline = TheApp.gfx:loadSpriteTable("Bitmap", "aux_ui", true)
  if not room_type.room_info then
    self.blueprint_rect = {
      x = 1,
      y = 1,
      w = 0,
      h = 0,
    }
    if room_type.swing_doors then
      self.blueprint_door = {anim = {}, old_anim = {}, old_flags = {}}
    else
      self.blueprint_door = {}
    end
    self.phase = "walls" --> "door" --> "windows" --> "clear_area" --> "objects" --> "closed"
    self.room_type = room_type
    self.title_text = room_type.name
    self.desc_text = _S.place_objects_window.drag_blueprint
  else
    self.phase = "objects"
    self.room_type = room_type.room_info
    self.title_text = room_type.room_info.name
    self.room = room_type
    self.desc_text = _S.place_objects_window.confirm_or_buy_objects
    self.paid = true
    self.blueprint_rect = {
      x = room_type.x,
      y = room_type.y,
      w = room_type.width,
      h = room_type.height,
    }
    if room_type.room_info.swing_doors then
      self.blueprint_door = {anim = {}, old_anim = {}, old_flags = {}}
    else
      self.blueprint_door = {}
    end
    self.ui:setWorldHitTest(self.room)
    self.pickup_button:enable(true)
    self.purchase_button:enable(true)
    self:checkEnableConfirm()
  end

  self.blueprint_wall_anims = {}
  self.blueprint_window = {}

  self.mouse_down_x = false
  self.mouse_down_y = false
  self.mouse_cell_x = 0
  self.mouse_cell_y = 0

  self:registerKeyHandlers()
end

function UIEditRoom:registerKeyHandlers()
  self:addKeyHandler("global_confirm", self.confirm) -- UIPlaceObjects does not need this
  self:addKeyHandler("global_confirm_alt", self.confirm)
end

function UIEditRoom:close(...)
  if self.phase == "objects" and self.confirm_button.enabled then
    if not self.closed_cleanly then
      self:confirm(true)
    end
  else
    while self.phase ~= "walls" do
      self:cancel()
    end
  end
  for k, obj in pairs(self.blueprint_wall_anims) do
    if obj.setTile then
      obj:setTile(nil)
    else
      for _, anim in pairs(obj) do
        anim:setTile(nil)
      end
    end
    self.blueprint_wall_anims[k] = nil
  end
  self.phase = "closed"
  -- No longer editing a room
  self.ui.edit_room = false
  self:setBlueprintRect(1, 1, 0, 0)
  self.ui:tutorialStep(3, {4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}, 1) -- not all of these links may be needed, but to be safe...
  return UIPlaceObjects.close(self, ...)
end

--[[ Called when building/editing of the room is about to stop because another
     dialog is being opened. If the room is in the objects phase and all
     required objects have been placed it will be completed. Otherwise
     it is cancelled instead.
--]]
function UIEditRoom:verifyOrAbortRoom()
  if self.phase == "objects" and self.confirm_button.enabled then
    -- The room can be finished
    self:close()
  else
    -- The room will have to be cancelled
    self:abortRoom()
  end
end

function UIEditRoom:abortRoom()
  if self.paid then
    -- Return half the cost.
    local progress = self.ui.hospital.research.research_progress
    local cost = math.floor(progress[self.room.room_info].build_cost/2)
    -- TODO: Return also the cost for additional objects.

    -- Decrease the hospital value by the whole room build cost
    local valueChange = progress[self.room.room_info].build_cost
    for obj, num in pairs(self.room.room_info.objects_needed) do
      -- Get how much this item costs.
      local obj_cost = self.ui.hospital:getObjectBuildCost(obj)
      cost = cost - math.floor(obj_cost)/2
      valueChange = valueChange - num * obj_cost
    end
    self.ui.hospital:receiveMoney(cost, _S.transactions.sell_object, valueChange)
  end
  -- Close the dialog
  self:close()
  -- Finally remove the room from the world (close() needs the reference)
  if self.room then
    self.world.rooms[self.room.id] = nil
  end
end

function UIEditRoom:cancel()
  if self.confirm_dialog_open then
    -- Don't do anything as long as the confirm dialog is open.
    return
  end
  if self.phase == "walls" then
    if self.paid then
      -- While the confirmation window is open, don't allow the player to click the confirm button.
      self.confirm_button:enable(false)
      self.confirm_dialog_open = true
      -- Ask if the user really wish to sell this room
      self.ui:addWindow(UIConfirmDialog(self.ui, false,
        _S.confirmation.delete_room,
        --[[persistable:delete_room_confirm_dialog]]function()
          self:abortRoom()
        end,
        --[[persistable:delete_room_confirm_dialog_cancel]]function()
          self.confirm_button:enable(true)
          self.confirm_dialog_open = nil
        end
      ))
    else
      self:abortRoom()
    end
    self.ui:setCursor(self.ui.default_cursor)
  elseif self.phase == "objects" then
    self:stopPickupItems()
    self:returnToDoorPhase()
    self.world:resetSideObjects()
  else
    if self.phase == "clear_area" then
      self.ui:setDefaultCursor(nil)
      self.check_for_clear_area_timer = nil
      self.humanoids_to_watch = nil
    end
    self.phase = "walls"
    self:returnToWallPhase()
  end
end

function UIEditRoom:confirm(force)
  -- double check if confirm is allowed (for being called e.g. by hotkey)
  if not force and not self.confirm_button.enabled then
    return
  end
  self:stopPickupItems()

  if self.phase == "walls" then
    self.mouse_down_x = false
    self.mouse_down_y = false
    self.move_rect_x = false
    self.move_rect_y = false
    self.phase = "door"
    self:enterDoorPhase()
  elseif self.phase == "door" then
    self.phase = "windows"
    self:enterWindowsPhase()
  elseif self.phase == "windows" then
    self.phase = "clear_area"
    self:clearArea()
  elseif self.phase == "clear_area" then
    self.ui:setDefaultCursor(nil)
    self.phase = "objects"
    self:finishRoom()
    self.world:resetSideObjects()
    self:enterObjectsPhase()
  else
    -- Pay for room (subtract cost of needed objects, which were already paid for)
    if not self.paid then
      local progress = self.ui.hospital.research.research_progress
      local cost = progress[self.room.room_info].build_cost
      for obj, num in pairs(self.room.room_info.objects_needed) do
        -- Get how much this item costs.
        local obj_cost = self.ui.hospital:getObjectBuildCost(obj)
        cost = cost - num * obj_cost
      end
      self.ui.hospital:spendMoney(cost, _S.transactions.build_room .. ": " .. self.title_text, cost)
      self.paid = true
    end

    self.world:markRoomAsBuilt(self.room)
    self.closed_cleanly = true
    -- If information dialogs are disabled, go ahead.
    if self.ui:getWindow(UIInformation) then
      self.ui:tutorialStep(3, 15, 16)
    else
      self.ui:tutorialStep(3, 15, "next")
    end
    self:close()
  end
end

local function isHumanoidObscuringArea(humanoid, x1, x2, y1, y2)
  if humanoid.tile_x then
    if x1 <= humanoid.tile_x and humanoid.tile_x <= x2 and
        y1 <= humanoid.tile_y and humanoid.tile_y <= y2 then
      if (x1 == humanoid.tile_x or x2 == humanoid.tile_x) or
          (y1 == humanoid.tile_y or y2 == humanoid.tile_y) then
        -- Humanoid not in the rectangle, but might be walking into it
        local action = humanoid:getCurrentAction()
        if action.name ~= "walk" then
          return false
        end
        if action.path_x then -- in a (rare) special case, path_x is nil (see action_walk_start)
          local next_x = action.path_x[action.path_index]
          local next_y = action.path_y[action.path_index]
          if x1 >= next_x or next_x >= x2 or y1 >= next_y or next_y >= y2 then
            return false
          end
        end
      end
      return true
    end
  end
  return false
end

function UIEditRoom:clearArea()
  self.confirm_button:enable(false)
  local rect = self.blueprint_rect
  local world = self.ui.app.world
  world:clearCaches() -- To invalidate idle tiles in case we need to move people
  local humanoids_to_watch = setmetatable({}, {__mode = "k"})
  do
    local x1 = rect.x - 1
    local x2 = rect.x + rect.w
    local y1 = rect.y - 1
    local y2 = rect.y + rect.h
    for _, entity in ipairs(world.entities) do
      if class.is(entity, Humanoid) and
          isHumanoidObscuringArea(entity, x1, x2, y1, y2) then
        humanoids_to_watch[entity] = true

        -- Try to make the humanoid leave the area
        local current_action = entity:getCurrentAction()
        local meander = entity.action_queue[2]
        if meander and meander.name == "meander" then
          -- Interrupt the idle or walk, which will cause a new meander target
          -- to be chosen, which will be outside the blueprint rectangle
          meander.can_idle = false
          local on_interrupt = current_action.on_interrupt
          if on_interrupt then
            current_action.on_interrupt = nil
            on_interrupt(current_action, entity)
          end
        elseif current_action.name == "seek_room" or (meander and meander.name == "seek_room") then
          -- Make sure that the humanoid doesn't stand idle waiting within the blueprint
          if current_action.name == "seek_room" then
            entity:queueAction(MeanderAction():setCount(1):setMustHappen(true), 0)
          else
            meander.done_walk = false
          end
        else
          -- Look for a queue action and re-arrange the people in it, which
          -- should cause anyone queueing within the blueprint to move
          for _, action in ipairs(entity.action_queue) do
            if action.name == "queue" then
              for _, humanoid in ipairs(action.queue) do
                local callbacks = action.queue.callbacks[humanoid]
                if callbacks then
                  callbacks:onChangeQueuePosition(humanoid)
                end
              end
              break
            end
          end
          -- TODO: Consider any other actions which might be causing the
          -- humanoid to be staying within the rectangle for a long time.
        end
      end
    end
  end

  if next(humanoids_to_watch) == nil then
    -- No humanoids within the area, so continue with the room placement
    self:confirm(true)
    return
  end

  self.check_for_clear_area_timer = 10
  self.humanoids_to_watch = humanoids_to_watch
  self.ui:setCursor(self.ui.waiting_cursor)
end

function UIEditRoom:onTick()
  UIFurnishCorridor.onTick(self)
  if self.check_for_clear_area_timer then
    self.check_for_clear_area_timer = self.check_for_clear_area_timer - 1
    if self.check_for_clear_area_timer == 0 then
      local rect = self.blueprint_rect
      local x1 = rect.x - 1
      local x2 = rect.x + rect.w
      local y1 = rect.y - 1
      local y2 = rect.y + rect.h
      for humanoid in pairs(self.humanoids_to_watch) do
        -- The person might be dying (this check should probably be moved into
        -- isHumanoidObscuringArea, but I don't want to change too much right
        -- before a release).
        if humanoid:getCurrentAction().name == "die" then
          if not humanoid.hospital then
            self.humanoids_to_watch[humanoid] = nil
          end
        elseif not isHumanoidObscuringArea(humanoid, x1, x2, y1, y2) then
          self.humanoids_to_watch[humanoid] = nil
        end
      end
      if next(self.humanoids_to_watch) then
        self.check_for_clear_area_timer = 10
      else
        self.check_for_clear_area_timer = nil
        self.humanoids_to_watch = nil
        self:confirm(true)
      end
    end
  end
end

function UIEditRoom:finishRoom()
  local room_type = self.room_type
  local wall_type = self.ui.app.walls[room_type.wall_type]
  local world = self.ui.app.world
  local map = self.ui.app.map.th
  local rect = self.blueprint_rect
  local door, door2
  -- Add the transparency flag if it is set.
  local flag = 0
  if self.ui.transparent_walls then
    flag = 1024
  end
  local function check_external_window(x, y, layer)
    -- If a wall is built which is normal to an external window, then said
    -- window needs to be removed, otherwise it looks odd (see issue #59).
    local block = map:getCell(x, y, layer)
    local dir = world:getWallDirFromBlockId(block)
    local tiles = self.ui.app.walls.external[world:getWallSetFromBlockId(block)]
    if dir == "north_window_1" then
      if x ~= rect.x then
        map:setCell(x, y, layer, flag + tiles.north)
        if map:getCell(x + 1, y, layer) ~= 0 then
          map:setCell(x + 1, y, layer, flag + tiles.north)
        end
      end
    elseif dir == "north_window_2" then
      if x == rect.x then
        if map:getCell(x - 1, y, layer) ~= 0 then
          map:setCell(x - 1, y, layer, flag + tiles.north)
        end
        map:setCell(x, y, layer, flag + tiles.north)
      end
    elseif dir == "west_window_1" then
      if y == rect.y then
        map:setCell(x, y, layer, flag + tiles.west)
        if map:getCell(x, y - 1, layer) ~= 0 then
          map:setCell(x, y - 1, layer, flag + tiles.west)
        end
      end
    elseif dir == "west_window_2" then
      if y ~= rect.y then
        if map:getCell(x, y + 1, layer) ~= 0 then
          map:setCell(x, y + 1, layer, flag + tiles.west)
        end
        map:setCell(x, y, layer, flag + tiles.west)
      end
    end
  end
  for x, obj in pairs(self.blueprint_wall_anims) do
    for y, anim in pairs(obj) do
      if x == rect.x and y == rect.y then
        local _, east, north = map:getCell(x, y)
        if world:getWallIdFromBlockId(east) == "external" then
          check_external_window(x, y, 2)
        elseif world:getWallSetFromBlockId(east) == "window_tiles" then
          map:setCell(x, y, 2, flag + wall_type.window_tiles.north)
        else
          map:setCell(x, y, 2, flag + wall_type.inside_tiles.north)
        end
        if world:getWallIdFromBlockId(north) == "external" then
          check_external_window(x, y, 3)
        elseif world:getWallSetFromBlockId(north) == "window_tiles" then
          map:setCell(x, y, 3, flag + wall_type.window_tiles.west)
        else
          map:setCell(x, y, 3, flag + wall_type.inside_tiles.west)
        end
      else
        repeat
          local tiles = "outside_tiles"
          local tag = anim:getTag()
          if tag == "nothing" or tag == "swing_slave" then
            tiles = "swing_outside_tiles"
          end
          local dir = (anim:getFlag() % 2 == 1) and "west" or "north"
          local layer = dir == "north" and 2 or 3
          if world:getWallIdFromBlockId(map:getCell(x, y, layer)) == "external" then
            if layer == 2 then
              if (x == rect.x or x == rect.x + rect.w - 1) and (y == rect.y or y == rect.y + rect.h) then
                check_external_window(x, y, 2)
              end
            else
              if (x == rect.x or x == rect.x + rect.w) and (y == rect.y or y == rect.y + rect.h - 1) then
                check_external_window(x, y, 3)
              end
            end
            break
          end
          local existing = world:getWallSetFromBlockId(map:getCell(x, y, layer))
          if rect.x <= x and x < rect.x + rect.w and rect.y <= y and y < rect.y + rect.h then
            if tag == "nothing" or tag == "swing_slave" then
              tiles = "swing_inside_tiles"
            else
              tiles = "inside_tiles"
            end
          elseif existing then
            break
          end
          if tag == "window" or existing == "window_tiles" then
            tiles = "window_tiles"
          end
          local suffixes = {"_left", "_right"}
          local num = dir == "north" and 1 or 0
          if tag == "door" then
            door = world:newObject("door", x, y, dir)
          elseif tag == "swing_master" then
            door = world:newObject("swing_door_right", x, y, dir)
          elseif tag == "swing_slave" then
            door2 = world:newObject("swing_door_left", x, y, dir)
            map:setCell(x, y, layer, flag + wall_type[tiles][dir .. suffixes[2 - num]])
          elseif tag == "nothing" then
            map:setCell(x, y, layer, flag + wall_type[tiles][dir .. suffixes[num + 1]])
          else
            map:setCell(x, y, layer, flag + wall_type[tiles][dir])
          end
        until true
      end
      anim:setTile(nil)
    end
    self.blueprint_wall_anims[x] = nil
  end
  -- If there is already a room, e.g. it is being moved, don't make a new one.
  if self.room then
    self.room:initRoom(rect.x, rect.y, rect.w, rect.h, door, door2)
  else
    self.room = self.world:newRoom(rect.x, rect.y, rect.w, rect.h, room_type, door, door2)
  end
end

function UIEditRoom:purchaseItems()
  self.visible = false
  self.place_objects = false
  self:stopPickupItems()

  local cfg_objects = self.world.map.level_config.objects
  local research = self.ui.hospital.research

  local object_list = {} -- transform set to list
  for i, o in ipairs(self.room.room_info.objects_additional) do
    -- Don't show the object if it hasn't been researched yet.
    local object = TheApp.objects[o]
    local avail = cfg_objects[object.thob].AvailableForLevel
    if avail == 1 and (not research.research_progress[object] or
        research.research_progress[object].discovered) then
      -- look up current quantity
      local cur_qty = 0
      for _, p in ipairs(self.objects) do
        if p.object.id == o then
          cur_qty = p.qty
        end
      end

      -- look up minimum quantity (required objects list)
      local min_qty = self.room.room_info.objects_needed[o] or 0

      -- subtract number of objects in room from minimum quantity
      for obj, _ in pairs(self.room.objects) do
        if min_qty == 0 then break end
        if obj.object_type.id == o then
          min_qty = min_qty - 1
        end
      end
      object_list[i] = { object = TheApp.objects[o], qty = cur_qty, min_qty = min_qty }
    end
  end

  self.ui:addWindow(UIFurnishCorridor(self.ui, object_list, self))
end

-- callback for item pick up button
function UIEditRoom:pickupItems()
  if self.in_pickup_mode then
    self:stopPickupItems()
  else
    self.in_pickup_mode = true
    self.ui:setCursor(self.ui.grab_cursor)
    self.place_objects = false
    self.active_index = 0
    self.object_cell_x = nil
    self.object_cell_y = nil
    self:clearBlueprint()
  end
end

function UIEditRoom:stopPickupItems()
  if self.in_pickup_mode then
    self.in_pickup_mode = false
    self.ui:setCursor(self.ui.default_cursor)
    self.pickup_button:setToggleState(false)
  end
end

function UIEditRoom:returnToWallPhase(early)
  self.ui:tutorialStep(3, {9, 10, 11, 12}, 4)
  if not early then
    self.desc_text = _S.place_objects_window.drag_blueprint
    self.confirm_button:enable(true)
    for k, obj in pairs(self.blueprint_wall_anims) do
      for _, anim in pairs(obj) do
        anim:setTile(nil)
      end
      self.blueprint_wall_anims[k] = nil
    end
  end
  local rect = self.blueprint_rect
  local x, y, w, h = rect.x, rect.y, rect.w, rect.h
  self:setBlueprintRect(1, 1, 0, 0)
  self:setBlueprintRect(x, y, w, h)
  if self.room_type.swing_doors then
    self.blueprint_door = {anim = {}, old_anim = {}, old_flags = {}}
  else
    self.blueprint_door = {}
  end
end

-- Remove walls
function UIEditRoom:_remove_wall_line(x, y, step_x, step_y, n_steps, layer, neigh_x, neigh_y, world)
  local map = world.map.th
  for _ = 1, n_steps do
    local existing = map:getCell(x, y, layer)
    -- Possibly add transparency.
    local flag = 0
    if world.ui.transparent_walls then
      flag = 1024
    end
    if world:getWallIdFromBlockId(existing) ~= "external" then
      local neighbour = world:getRoom(x + neigh_x, y + neigh_y)
      if neighbour then
        if neigh_x ~= 0 or neigh_y ~= 0 then
          local set = world:getWallSetFromBlockId(existing)
          local dir = world:getWallDirFromBlockId(existing)
          if set == "inside_tiles" then
            set = "outside_tiles"
          end
          map:setCell(x, y, layer, flag + world.wall_types[neighbour.room_info.wall_type][set][dir])
        end
      else
        map:setCell(x, y, layer, flag)
      end
    end
    x = x + step_x
    y = y + step_y
  end
end

function UIEditRoom:removeRoom(save_objects, room, world)
  -- Remove any placed objects (add them to list again) when save_objects is true
  for x = room.x, room.x + room.width - 1 do
    for y = room.y, room.y + room.height - 1 do
      while true do
        -- get litter then any other object
        local obj = world:getObject(x, y, 'litter') or world:getObject(x, y)
        -- but we need to ignore doors
        if not obj or obj == room.door or class.is(obj, SwingDoor) then
          break
        end
        if obj.object_type.id == "litter" then -- Silently remove litter from the world.
          obj:remove()
        else
          if save_objects then
            local obj_state = obj:getState()
            world:destroyEntity(obj)
            if not obj.master then
              self:addObjects({{
                object = TheApp.objects[obj.object_type.id],
                state = obj_state,
                qty = 1
              }})
            end
          else
            -- just destroy it
            world:destroyEntity(obj)
          end
        end
      end
    end
  end

  -- now doors
  world:destroyEntity(room.door)
  if room.door2 then
    world:destroyEntity(room.door2)
  end

  if save_objects then
    -- backup list of objects
    self.objects_backup = {}
    for k, o in pairs(self.objects) do
      self.objects_backup[k] = { object = o.object, qty = o.qty, state = o.state }
    end

    UIPlaceObjects.removeAllObjects(self, true)
  end

  self:_remove_wall_line(room.x, room.y, 0, 1, room.height, 3, -1,  0, world)
  self:_remove_wall_line(room.x, room.y, 1, 0, room.width , 2,  0, -1, world)
  self:_remove_wall_line(room.x + room.width, room.y , 0, 1, room.height, 3, 0, 0, world)
  self:_remove_wall_line(room.x, room.y + room.height, 1, 0, room.width , 2, 0, 0, world)

  -- Reset floor tiles and flags
  world.map.th:unmarkRoom(room.x, room.y, room.width, room.height)
end

function UIEditRoom:returnToDoorPhase()
  self.ui:tutorialStep(3, {13, 14, 15}, 9)
  local room = self.room
  room.built = false
  if room.door and room.door.queue then
    room.door.queue:rerouteAllPatients(room.room_info.id)
  end

  self.purchase_button:enable(false)
  self.pickup_button:enable(false)

  self:removeRoom(true, room, self.world)

  -- Re-create blueprint
  local rect = self.blueprint_rect
  local old_w, old_h = rect.w, rect.h
  rect.w = 0
  rect.h = 0
  self:setBlueprintRect(rect.x, rect.y, old_w, old_h)

  -- We've gone all the way back to wall phase, so step forward to door phase
  self.phase = "door"
  self:enterDoorPhase()
end

function UIEditRoom:screenToWall(x, y)
  local cellx, celly = self.ui:ScreenToWorld(x, y)
  cellx = math.floor(cellx)
  celly = math.floor(celly)
  local rect = self.blueprint_rect

  if cellx == rect.x or cellx == rect.x - 1 or cellx == rect.x + rect.w or cellx == rect.x + rect.w - 1 or
     celly == rect.y or celly == rect.y - 1 or celly == rect.y + rect.h or
     celly == rect.y + rect.h - 1 then -- luacheck: ignore 542
  else
    return
  end

  -- NB: Doors and windows cannot be placed on corner tiles, hence walls of corner tiles
  -- are never returned, and the nearest non-corner wall is returned instead. If they
  -- could be placed on corner tiles, then you would have to consider the interaction of
  -- wall shadows with windows and doors, amongst other things.
  -- Swing doors are allowed to be adjacent everywhere except the top corner.
  local modifier = 0
  local swinging = false
  if self.room_type.swing_doors and self.phase == "door" then
    modifier = 1
    swinging = true
  end
  if cellx == rect.x and celly == rect.y then
    -- top corner
    local x_, _ = self.ui:WorldToScreen(cellx, celly)
    if x >= x_ then
      -- correctly reflects (at least origin version) of TH.
      -- Swing doors in top corner to the east, actually skip another tile
      if swinging then
        return cellx + 2 + modifier, celly, "north"
      else
        return cellx + 1 + modifier, celly, "north"
      end
    else
      return cellx, celly + 1 + modifier, "west"
    end
  elseif cellx == rect.x + rect.w - 1 and celly == rect.y + rect.h - 1 then
    -- bottom corner
    local x_, _ = self.ui:WorldToScreen(cellx, celly)
    if x >= x_ then
      return cellx, celly - 1, "east"
    else
      return cellx - 1, celly, "south"
    end
  elseif cellx == rect.x and celly == rect.y + rect.h - 1 then
    -- left corner
    local _, y_ = self.ui:WorldToScreen(cellx, celly)
    if y >= y_ + 16 then
      if swinging and cellx <= rect.x + 2 then
        return cellx + 1 + modifier, celly, "south"
      else
        return cellx + 1, celly, "south"
      end
    else
      return cellx, celly - 1, "west"
    end
  elseif cellx == rect.x + rect.w - 1 and celly == rect.y then
    -- right corner
    local _, y_ = self.ui:WorldToScreen(cellx, celly)
    if y >= y_ + 16 then
      if swinging and celly <= rect.y + 2 then
        return cellx, celly + 1 + modifier, "east"
      else
        return cellx, celly + 1, "east"
      end
    else
      return cellx - 1, celly, "north"
    end
  elseif (cellx == rect.x - 1 or cellx == rect.x) and rect.y <= celly and celly < rect.y + rect.h then
    -- west edge
    if celly == rect.y then
      celly = rect.y + 1
    elseif celly == rect.y + rect.h - 1 then
      celly = rect.y + rect.h - 2
    end
    if swinging and celly <= rect.y + 1 then
      celly = celly + 1
    end
    return rect.x, celly, "west"
  elseif (celly == rect.y - 1 or celly == rect.y) and rect.x <= cellx and cellx < rect.x + rect.w then
    -- north edge
    -- correctly reflects (at least origin version) of TH.
    -- Swing doors in top corner to the east, actually skip another tile
    if swinging and cellx <= rect.x + 2 then
      cellx = rect.x + 3
    elseif cellx == rect.x then
      cellx = rect.x + 1 + modifier
    elseif cellx == rect.x + rect.w - 1 then
      cellx = rect.x + rect.w - 2
    end
    return cellx, rect.y, "north"
  elseif (cellx == rect.x + rect.w or cellx == rect.x + rect.w - 1) and
      rect.y <= celly and celly < rect.y + rect.h then
      -- east edge
    if swinging and celly <= rect.y + 1 then
      celly = rect.y + 2
    elseif celly == rect.y then
      celly = rect.y + 1
    elseif celly == rect.y + rect.h - 1 then
      celly = rect.y + rect.h - 2
    end
    return rect.x + rect.w - 1, celly, "east"
  elseif (celly == rect.y + rect.h or celly == rect.y + rect.h - 1) and
      rect.x <= cellx and cellx < rect.x + rect.w then
    -- south edge
    if swinging and cellx <= rect.x + 1 then
      cellx = rect.x + 2
    elseif cellx == rect.x then
      cellx = rect.x + 1
    elseif cellx == rect.x + rect.w - 1 then
      cellx = rect.x + rect.w - 2
    end
    return cellx, rect.y + rect.h - 1, "south"
  end
end

-- Function to check if the tiles adjacent to the room are still reachable from each other.
-- NB: the passable flags of the room have to be set to false already before calling this function
function UIEditRoom:checkReachability()
  local map = self.ui.app.map.th
  local world = self.ui.app.world

  local rect = self.blueprint_rect
  local prev_x, prev_y
  local x, y = rect.x, rect.y - 1
  local flags = {}

  local function check(flag)
    if map:getCellFlags(x, y, flags).passable and flags[flag] then
      if prev_x and not world:getPathDistance(prev_x, prev_y, x, y) then
        return false
      end
      prev_x, prev_y = x, y
    end
    return true
  end

  while x < rect.x + rect.w do
    if not check("travelSouth") then return false end
    x = x + 1
  end
  y = y + 1
  while y < rect.y + rect.h do
    if not check("travelWest") then return false end
    y = y + 1
  end
  x = x - 1
  while x >= rect.x do
    if not check("travelNorth") then return false end
    x = x - 1
  end
  y = y - 1
  while y >= rect.y do
    if not check("travelEast") then return false end
    y = y - 1
  end

  return true
end

function UIEditRoom:enterDoorPhase()
  self.ui:tutorialStep(3, 8, 9)
  -- make tiles impassable
  for y = self.blueprint_rect.y, self.blueprint_rect.y + self.blueprint_rect.h - 1 do
    for x = self.blueprint_rect.x, self.blueprint_rect.x + self.blueprint_rect.w - 1 do
      self.ui.app.map:setCellFlags(x, y, {passable = false})
    end
  end

  -- check if all adjacent tiles of the rooms are still connected
  if not self:checkReachability() then
    if self.ui.app.config.allow_blocking_off_areas then
      print("Blocking off areas is allowed with room " .. self.blueprint_rect.x .. ", " .. self.blueprint_rect.y .. ".")
    else
      -- undo passable flags and go back to walls phase
      self.phase = "walls"
      self:returnToWallPhase(true)
      self.ui:playSound("wrong2.wav")
      self.ui.adviser:say(_A.room_forbidden_non_reachable_parts)
      return
    end
  end

  self.desc_text = _S.place_objects_window.place_door
  self.confirm_button:enable(false) -- Confirmation is via placing door

  -- Change the floor tiles to opaque blue
  local map = self.ui.app.map.th
  for y = self.blueprint_rect.y, self.blueprint_rect.y + self.blueprint_rect.h - 1 do
    for x = self.blueprint_rect.x, self.blueprint_rect.x + self.blueprint_rect.w - 1 do
      map:setCell(x, y, 4, 24)
    end
  end

  -- Re-organise wall anims to index by x and y
  local walls = {}
  for _, wall in ipairs(self.blueprint_wall_anims) do
    local _, x, y = wall:getTile()
    if not walls[x] then
      walls[x] = {}
    end
    walls[x][y] = wall
  end
  self.blueprint_wall_anims = walls
end

function UIEditRoom:enterWindowsPhase()
  self.ui:tutorialStep(3, {9, 10}, 11)
  self.desc_text = _S.place_objects_window.place_windows
  self.confirm_button:enable(true)
end

function UIEditRoom:enterObjectsPhase()
  self.ui:setCursor(self.ui.default_cursor)
  self.ui:tutorialStep(3, {11, 12}, 13)
  self.ui:setWorldHitTest(self.room)
  local confirm = self:checkEnableConfirm()
  if #self.room.room_info.objects_additional == 0 and confirm then
    self:confirm(true)
    return
  end
  self.desc_text = _S.place_objects_window.confirm_or_buy_objects
  if #self.room.room_info.objects_additional > 0 then
    self.purchase_button:enable(true)
  end
  self.pickup_button:enable(true)

  if self.objects_backup then
    self:addObjects(self.objects_backup, true)
  else
    local room_objects = self.room.room_info.objects_needed
    if TheApp.config.enable_avg_contents then
      room_objects = self:computeAverageContents()
    end
    local object_list = {} -- transform set to list
    for o, num in pairs(room_objects) do
      if num > 0 then
        object_list[#object_list + 1] = { object = TheApp.objects[o], qty = num }
      end
    end
    self:addObjects(object_list, true)
  end
end

-- Decide contents of the new room based on average content of previous built rooms
-- of the same type.
function UIEditRoom:computeAverageContents()
  local average_objects = {} -- what does the average room of this type contain?
  local room_count = 0
  for _, room in pairs(self.world.rooms) do
    if room and room.built and not room.crashed and
        room.hospital == self.ui.hospital and room.room_info == self.room_type then
      room_count = room_count + 1
      for obj, _ in pairs(room.objects) do
        average_objects[obj.object_type.id] = (average_objects[obj.object_type.id] or 0) + 1
      end
    end
  end
  -- Ensure room contents is within the boundaries of objects_needed and objects_additional.
  local objects_needed = self.room.room_info.objects_needed
  local additional_objects = {} -- Reversed mapping
  for _, obj in pairs(self.room.room_info.objects_additional) do
    additional_objects[obj] = 1
  end
  for id, count in pairs(average_objects) do
    count = math.floor(count / room_count + 0.5)
    if additional_objects[id] == nil and objects_needed[id] == nil then
      count = 0
    end
    average_objects[id] = count
  end
  for id, count in pairs(objects_needed) do
    if (average_objects[id] or 0) < count then
      average_objects[id] = count
    end
  end
  return average_objects
end

function UIEditRoom:draw(canvas, ...)
  if self.world.user_actions_allowed then
    local ui = self.ui
    local x, y = ui:WorldToScreen(self.mouse_cell_x, self.mouse_cell_y)
    local zoom = self.ui.zoom_factor
    if canvas:scale(zoom) then
      x = math.floor(x / zoom)
      y = math.floor(y / zoom)
    end
    self.cell_outline:draw(canvas, 2, x - 32, y)
    canvas:scale(1)
  end

  UIPlaceObjects.draw(self, canvas, ...)
end

function UIEditRoom:onMouseDown(button, x, y)
  if self.world.user_actions_allowed and not self.confirm_dialog_open then
    if button == "left" then
      if self.phase == "walls" then
        if 0 <= x and x < self.width and 0 <= y and y < self.height then -- luacheck: ignore 542
        else
          local mouse_x, mouse_y = self.ui:ScreenToWorld(self.x + x, self.y + y)
          self.mouse_down_x = math.floor(mouse_x)
          self.mouse_down_y = math.floor(mouse_y)
          if self.move_rect then
            self.move_rect_x = self.mouse_down_x - self.blueprint_rect.x
            self.move_rect_y = self.mouse_down_y - self.blueprint_rect.y
          elseif not self.resize_rect then
            self:setBlueprintRect(self.mouse_down_x, self.mouse_down_y, 1, 1)
          end
        end
      elseif self.phase == "door" then
        if self.blueprint_door.valid then
          self.ui:playSound("buildclk.wav")
          self:confirm(true)
        else
          self.ui:tutorialStep(3, 9, 10)
        end
      elseif self.phase == "windows" then
        self:placeWindowBlueprint()
      end
    end
  end
  return UIPlaceObjects.onMouseDown(self, button, x, y) or true
end

function UIEditRoom:onMouseUp(button, x, y)
  if self.mouse_down_x then
    self.mouse_down_x = false
    self.mouse_down_y = false
  end

  if self.move_rect_x then
    self.move_rect_x = false
    self.move_rect_y = false
  end

  return UIPlaceObjects.onMouseUp(self, button, x, y)
end

function UIEditRoom:onMouseMove(x, y, ...)
  if self.in_pickup_mode then
    self.ui:setCursor(self.ui.app.gfx:loadMainCursor("grab"))
  end
end

function UIEditRoom:setBlueprintRect(x, y, w, h)
  local rect = self.blueprint_rect
  local map = self.ui.app.map
  if x < 1 then x = 1 end
  if y < 1 then y = 1 end
  if x + w > map.width  then w = map.width  - x end
  if y + h > map.height then h = map.height - y end

  if rect.x == x and rect.y == y and rect.w == w and rect.h == h then
    -- Nothing to do
    return
  end

  local too_small = w < self.room_type.minimum_size or h < self.room_type.minimum_size
  local player_id = self.ui.hospital:getPlayerIndex()

  -- Entire update of floor tiles and wall animations done in C to replace
  -- several hundred calls into C with just a single call. The price for this
  -- is reduced flexibility. See l_map_updateblueprint in th_lua.cpp for code.
  local is_valid = map.th:updateRoomBlueprint(rect.x, rect.y, rect.w, rect.h,
    x, y, w, h, player_id, self.blueprint_wall_anims, self.anims, too_small)

  -- NB: due to the unflexibility, tutorial step "too small AND invalid position" (3.7)
  --     is currently unusable, as it's not possible to determine if the position would
  --     have been invalid even if it weren't too small.
  if self.phase ~= "closed" then
    if too_small then
      self.ui:tutorialStep(3, {4, 5, 8}, 6)
    elseif not is_valid then
      self.ui:tutorialStep(3, {4, 6, 8}, 5)
    else
      self.ui:tutorialStep(3, {4, 5, 6}, 8)
    end
  end

  self.confirm_button:enable(is_valid)

  rect.x = x
  rect.y = y
  rect.w = w
  rect.h = h
end

--25 north wall, west
--26 north wall, east
--27 east wall, south
--28 east wall, north
--29 south wall, west
--30 south wall, east
--31 west wall, south
--32 west wall, north
-- single door blue print values matching TH
local door_floor_blueprint_markers = {
  north = 26,
  east = 27,
  south = 30,
  west = 31
}

local window_floor_blueprint_markers = {
  north = 33,
  east = 34,
  south = 35,
  west = 36,
}

--! Check walls for having room for the door
--!param x (int) X tile position of the door.
--!param y (int) Y tile position of the door.
--!param wall (string) Name of the wall (either 'north' or 'west').
--!param has_swingdoor (boolean) Whether the room has a normal door (false) or a swing door (true) as entrance.
--!return (int) bit flags indicating invalid tile position using 1 based power of 2 as this works with ipairs
--!  values returned are the enumeration of
--!  4 = centre door in swing door or for single door the value can just be non-zero but uses the same bit of code
--!  2 (door section closer to top of screen) - smaller x or y
--!  8 (door section closer to bottom of screen) - larger x or y
local function checkDoorWalls(x, y, wall, has_swingdoor)
  local th = TheApp.map.th

  local dx, dy, wall_num
  if wall == "west" then
    wall_num = 3
    dx = 0
    dy = 1
  else
    wall_num = 2
    dx = 1
    dy = 0
  end
  local invalid_tile = 0
  if th:getCell(x, y, wall_num) % 0x100 ~= 0 then
    invalid_tile = 4
  end

  -- If it is a swing door there are two more locations to check.
  if has_swingdoor then
    if th:getCell(x - dx, y - dy, wall_num) % 0x100 ~= 0 then
      invalid_tile = invalid_tile + 2
    end
    if th:getCell(x + dx, y + dy, wall_num) % 0x100 ~= 0 then
      invalid_tile = invalid_tile + 8
    end
  end
  return invalid_tile
end

--! Check whether the given tile can function as a door entry/exit tile.
--!param xpos (int) X position of the tile.
--!param ypos (int) Y position of the tile.
--!param player_id (int) Player id owning the hospital.
--!param world - reference to world object instance
--!return (boolean) whether the tile is considered to be valid.
local function validDoorTile(xpos, ypos, player_id, world)
  local th = TheApp.map.th
  local tile_flags = th:getCellFlags(xpos, ypos)
  -- check own it
  if tile_flags.owner ~= player_id then return false end
  -- any object will cause it to be blocked (ignore litter)
  if tile_flags.thob ~= 0 and tile_flags.thob ~= 62 then return false end
  -- check if its passable that no object footprint blocks it
  if tile_flags.passable then return world:isTileExclusivelyPassable(xpos, ypos, 1) end
  return true
end

--! Calculate position offsets and door blueprint wall values
--! param x (int) doors blueprint x value
--! param y (int) doors blueprint y value
--! param wall (string) original wall orientation
--! return x (int) updated x value
--! return y (int) updated y value
--! return x_mod (int) offset value to apply to tile count to determine relative position
--! return y_mod (int) offset value to apply to tile count to determine relatitve position
--! return wall (string) wall orientation style (only 2 styles)
local function doorWallOffsetCalculations(x, y, wall)
  local x_mod
  local y_mod
  if wall == "south" then
    y = y + 1
    wall = "north"
    x_mod = 2
  elseif wall == "east" then
    x = x + 1
    wall = "west"
    y_mod = 2
  elseif wall == "north" then
    x_mod = 2
  else
    y_mod = 2
  end
  return x, y, x_mod, y_mod, wall
end

function UIEditRoom:setDoorBlueprint(orig_x, orig_y, orig_wall)
  local x, y, x_mod, y_mod, wall = doorWallOffsetCalculations(orig_x, orig_y, orig_wall)
  local map = TheApp.map.th

  if self.blueprint_door.anim then
    if self.room_type.swing_doors then
      if self.blueprint_door.anim[1] then
        -- retrieve the old door position details to reset the blue print
        local oldx, oldy
        local _, _, oldx_mod, oldy_mod, _ = doorWallOffsetCalculations(self.blueprint_door.floor_x,
          self.blueprint_door.floor_y, self.blueprint_door.wall)
        -- If we're dealing with swing doors the anim variable is actually a table with three
        -- identical "doors".
        for i, anim in ipairs(self.blueprint_door.anim) do
          anim:setAnimation(self.anims, self.blueprint_door.old_anim[i],
            self.blueprint_door.old_flags[i])
          anim:setTag(nil)
          self.blueprint_door.anim[i] = nil
          oldx = oldx_mod and self.blueprint_door.floor_x + (i - oldx_mod) or self.blueprint_door.floor_x
          oldy = oldy_mod and self.blueprint_door.floor_y + (i - oldy_mod) or self.blueprint_door.floor_y
          map:setCell(oldx, oldy, 4, 24)
        end
      end
    else
      self.blueprint_door.anim:setAnimation(self.anims, self.blueprint_door.old_anim,
        self.blueprint_door.old_flags)
      self.blueprint_door.anim:setTag(nil)
      self.blueprint_door.anim = nil
      map:setCell(self.blueprint_door.floor_x, self.blueprint_door.floor_y, 4, 24)
    end
  end
  self.blueprint_door.x = x
  self.blueprint_door.y = y
  self.blueprint_door.wall = wall
  self.blueprint_door.floor_x = orig_x
  self.blueprint_door.floor_y = orig_y
  self.blueprint_door.valid = false
  if not wall then
    return
  end
  local anim = self.blueprint_wall_anims[x][y]
  if self.room_type.swing_doors then
    anim = {}
    local types = {"swing_slave", "swing_master", "nothing"}
    for i = 1, 3 do
      local x1 = x_mod and (x + (i - x_mod)) or x
      local y1 = y_mod and (y + (i - y_mod)) or y
      anim[i] = self.blueprint_wall_anims[x1][y1]
      if anim[i] ~= self.blueprint_door.anim[i] then
        self.blueprint_door.anim[i] = anim[i]
        self.blueprint_door.anim[i]:setTag(types[i])
        self.blueprint_door.old_anim[i] = anim[i]:getAnimation()
        self.blueprint_door.old_flags[i] = anim[i]:getFlag()
      end
    end
  else
    if anim ~= self.blueprint_door.anim then
      self.blueprint_door.anim = anim
      self.blueprint_door.anim:setTag("door")
      self.blueprint_door.old_anim = anim:getAnimation()
      self.blueprint_door.old_flags = anim:getFlag()
    end
  end

  local flags
  local x2, y2 = x, y
  if wall == "west" then
    flags = 1
    x2 = x2 - 1
  else--if wall == "north" then
    flags = 0
    y2 = y2 - 1
  end
  local world = self.ui.app.world
  -- invalid_tile used to select the individual blueprint that is blocked
  local invalid_tile = checkDoorWalls(x, y, wall, self.room_type.swing_doors)
  -- Ensure that the door isn't being built on top of an object
  local player_id = self.ui.hospital:getPlayerIndex()
  if not validDoorTile(x, y, player_id, world) or
      not validDoorTile(x2, y2, player_id, world) then
    invalid_tile = bitOr(invalid_tile, 4)
  end
  -- If we're making swing doors two more tiles need to be checked.
  if self.room_type.swing_doors then
    local dx = x_mod and 1 or 0
    local dy = y_mod and 1 or 0
    if not validDoorTile(x + dx, y + dy, player_id, world) or
        not validDoorTile(x2 + dx, y2 + dy, player_id, world) then
      invalid_tile = bitOr(invalid_tile, 8)
    end
    if not validDoorTile(x - dx, y - dy, player_id, world) or
        not validDoorTile(x2 - dx, y2 - dy, player_id, world) then
      invalid_tile = bitOr(invalid_tile, 2)
    end
  end

  self.blueprint_door.valid = (invalid_tile == 0)

  if self.room_type.swing_doors then
    for i, animation in ipairs(anim) do
      -- calculation here to flag blocked blueprint tiles on swing doors for each door tile
      animation:setAnimation(self.anims, 126, flags + (hasBit(invalid_tile, i) and 1 or 0) * 16)
    end
  else
    anim:setAnimation(self.anims, 126, flags + (invalid_tile ~= 0 and 1 or 0) * 16)
  end
  if self.room_type.swing_doors then
    flags = door_floor_blueprint_markers[orig_wall]
    local dirfix = orig_wall == "east"
    flags = dirfix and flags + 1 or flags
    for i = 1, 3 do
      local x1 = x_mod and orig_x + i - x_mod or orig_x
      local y1 = y_mod and orig_y + i - y_mod or orig_y
      if (i == 2) then
        map:setCell(x1, y1, 4, 24)
      else
        if dirfix then
          map:setCell(x1, y1, 4, i < 2 and flags or flags - 1)
        else
          map:setCell(x1, y1, 4, i > 2 and flags or flags - 1)
        end
      end
    end
  else
    map:setCell(self.blueprint_door.floor_x, self.blueprint_door.floor_y, 4,
      door_floor_blueprint_markers[orig_wall])
  end
end

function UIEditRoom:placeWindowBlueprint()
  if self.blueprint_window.anim and self.blueprint_window.valid then
    self.blueprint_window = {}
    self.ui:playSound("buildclk.wav")
  elseif self.blueprint_window.anim and not self.blueprint_window.valid then
    self.ui:tutorialStep(3, 11, 12)
  end
end

function UIEditRoom:setWindowBlueprint(orig_x, orig_y, orig_wall)
  local x = orig_x
  local y = orig_y
  local wall = orig_wall

  if wall == "south" then
    y = y + 1
    wall = "north"
  elseif wall == "east" then
    x = x + 1
    wall = "west"
  end

  local map = self.ui.app.map.th
  local world = self.ui.app.world

  if self.blueprint_window.anim then
    self.blueprint_window.anim:setAnimation(self.anims, self.blueprint_window.old_anim,
      self.blueprint_window.old_flags)
      self.blueprint_window.anim:setTag(nil)
    self.blueprint_window.anim = nil
    map:setCell(self.blueprint_window.floor_x, self.blueprint_window.floor_y, 4, 24)
  end

  local anim = x and self.blueprint_wall_anims[x][y]
  if anim and anim:getTag() then
    x, y, wall = nil, nil, nil
    orig_x, orig_y, orig_wall = nil, nil, nil
  end

  self.blueprint_window.x = x
  self.blueprint_window.y = y
  self.blueprint_window.wall = wall
  self.blueprint_window.floor_x = orig_x
  self.blueprint_window.floor_y = orig_y
  self.blueprint_window.valid = false
  if not wall then
    return
  end

  if anim ~= self.blueprint_window.anim then
    self.blueprint_window.anim = anim
    self.blueprint_window.anim:setTag("window")
    self.blueprint_window.old_anim = anim:getAnimation()
    self.blueprint_window.old_flags = anim:getFlag()
  end
  self.blueprint_window.valid = true
  local flags
  if wall == "west" then
    flags = 1
    if world:getWallIdFromBlockId(map:getCell(x, y, 3)) then
      self.blueprint_window.valid = false
      flags = flags + 16
    end
  else--if wall == "north" then
    flags = 0
    if world:getWallIdFromBlockId(map:getCell(x, y, 2)) then
      self.blueprint_window.valid = false
      flags = flags + 16
    end
  end
  anim:setAnimation(self.anims, 130, flags)
  if self.blueprint_window.valid then
    map:setCell(self.blueprint_window.floor_x, self.blueprint_window.floor_y, 4,
      window_floor_blueprint_markers[orig_wall])
  end
end

function UIEditRoom:onCursorWorldPositionChange(x, y)
  local repaint = UIPlaceObjects.onCursorWorldPositionChange(self, x, y)

  local ui = self.ui

  -- Is the game paused?
  if not self.world.user_actions_allowed or self.confirm_dialog_open then
    ui:setCursor(ui.default_cursor)
    return
  end
  local wx, wy = ui:ScreenToWorld(self.x + x, self.y + y)
  wx = math.floor(wx)
  wy = math.floor(wy)

  if self.phase == "walls" then
    local rect = self.blueprint_rect
    if not self.mouse_down_x then
      if wx > rect.x and wx < rect.x + rect.w - 1 and wy > rect.y and wy < rect.y + rect.h - 1 then
        -- inside blueprint, non-border -> move blueprint
        ui:setCursor(ui.app.gfx:loadMainCursor("move_room"))
        self.move_rect = true
        self.resize_rect = false
      elseif wx < rect.x or wx >= rect.x + rect.w or wy < rect.y or wy >= rect.y + rect.h then
        -- outside blueprint
        ui:setCursor(ui.app.gfx:loadMainCursor("resize_room"))
        self.move_rect = false
        self.resize_rect = false
      else
        -- inside blueprint, at border -> resize blueprint
        self.move_rect = false
        self.resize_rect = {
          n = (wy == rect.y),
          s = (wy == rect.y + rect.h - 1) and (wy ~= rect.y),
          w = (wx == rect.x),
          e = (wx == rect.x + rect.w - 1) and (wx ~= rect.x),
        }

        if (self.resize_rect.w or self.resize_rect.e) and (self.resize_rect.n or self.resize_rect.s) then
          ui:setCursor(ui.app.gfx:loadMainCursor("nswe_arrow"))
        elseif self.resize_rect.w or self.resize_rect.e then
          ui:setCursor(ui.app.gfx:loadMainCursor("we_arrow"))
        else
          ui:setCursor(ui.app.gfx:loadMainCursor("ns_arrow"))
        end
      end
    end
  else
    if self.phase ~= "clear_area" and self.phase ~= "objects" then
      ui:setCursor(ui.app.gfx:loadMainCursor("resize_room"))
    end
    local cell_x, cell_y, wall = self:screenToWall(self.x + x, self.y + y)
    if self.phase == "door" then
      self:setDoorBlueprint(cell_x, cell_y, wall)
    elseif self.phase == "windows" then
      self:setWindowBlueprint(cell_x, cell_y, wall)
    end
  end

  if self.mouse_down_x and self.move_rect then
    local rect = self.blueprint_rect
    self:setBlueprintRect(wx - self.move_rect_x, wy - self.move_rect_y, rect.w, rect.h)
  elseif self.mouse_down_x and self.resize_rect then
    local rect = self.blueprint_rect
    local x1, y1, x2, y2 = rect.x, rect.y, rect.x + rect.w - 1, rect.y + rect.h - 1
    if self.resize_rect.w then
      x1 = wx
    elseif self.resize_rect.e then
      x2 = wx
    end
    if self.resize_rect.n then
      y1 = wy
    elseif self.resize_rect.s then
      y2 = wy
    end

    if x1 > x2 then
      x1, x2 = x2, x1
      self.resize_rect.w, self.resize_rect.e = self.resize_rect.e, self.resize_rect.w
    end
    if y1 > y2 then
      y1, y2 = y2, y1
      self.resize_rect.n, self.resize_rect.s = self.resize_rect.s, self.resize_rect.n
    end
    self:setBlueprintRect(x1, y1, x2 - x1 + 1, y2 - y1 + 1)
  elseif self.mouse_down_x then
    local x1, x2 = self.mouse_down_x, wx
    local y1, y2 = self.mouse_down_y, wy
    if x1 > x2 then x1, x2 = x2, x1 end
    if y1 > y2 then y1, y2 = y2, y1 end
    self:setBlueprintRect(x1, y1, x2 - x1 + 1, y2 - y1 + 1)
  end

  if wx ~= self.mouse_cell_x or wy ~= self.mouse_cell_y then
    repaint = true
  end
  self.mouse_cell_x = wx
  self.mouse_cell_y = wy

  return repaint
end

-- checks if all required objects are placed, and enables/disables the confirm button accordingly.
-- also returns the new state of the confirm button
function UIEditRoom:checkEnableConfirm()
  local needed = {} -- copy list of required objects
  for k, v in pairs(self.room.room_info.objects_needed) do
    needed[k] = v
  end

  -- subtract existing objects from the required numbers
  for o in pairs(self.room.objects) do
    local id = o.object_type.id
    if needed[id] then
      needed[id] = needed[id] - 1
      if needed[id] == 0 then
        needed[id] = nil
      end
    end
  end

  -- disable if there are not fulfilled requirements
  local confirm = not next(needed)

  if confirm then
    self.ui:tutorialStep(3, {13, 14}, 15)
  else
    self.ui:tutorialStep(3, {14, 15}, 13)
  end

  self.confirm_button:enable(confirm)
  return confirm
end

function UIEditRoom:placeObject()
  local obj = UIPlaceObjects.placeObject(self, true)
  if obj then
    self:checkEnableConfirm()
  end
end

function UIEditRoom:afterLoad(old, new)
  if old < 171 then
    self.wall_types = TheApp.walls
    self:initWallTypes()
  end
  if old < 172 then
    self.wall_types = nil
    self.wall_id_by_block_id = nil
    self.wall_set_by_block_id = nil
    self.wall_dir_by_block_id = nil
  end

  UIPlaceObjects.afterLoad(self, old, new)
  self:registerKeyHandlers()
end
