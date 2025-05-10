
RollFor = RollFor or {}
local m = RollFor

if m.SrPlusGui then return end

local M = {}
local hl = m.colors.hl

local UIParent = UIParent
local ChatFontNormal = ChatFontNormal

local frame_backdrop = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true,
  tileSize = 32,
  edgeSize = 32,
  insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

local control_backdrop = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true,
  tileSize = 16,
  edgeSize = 16,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

local function create_frame(api, on_import, on_clear, on_cancel, on_dirty)
  local frame = m.create_backdrop_frame(api(), "Frame", "RollForSrPlusImportFrame", UIParent)
  frame:Hide()
  frame:SetWidth(565)
  frame:SetHeight(300)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop(frame_backdrop)
  frame:SetBackdropColor(0, 0, 0, 1)
  frame:SetMinResize(400, 200)
  frame:SetToplevel(true)

  local backdrop = m.create_backdrop_frame(api(), "Frame", nil, frame)
  backdrop:SetBackdrop(control_backdrop)
  backdrop:SetBackdropColor(0, 0, 0)
  backdrop:SetBackdropBorderColor(0.4, 0.4, 0.4)
  backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 17, -18)
  backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -17, 43)

  local scroll_frame = api().CreateFrame("ScrollFrame", nil, backdrop, "UIPanelScrollFrameTemplate")
  scroll_frame:SetPoint("TOPLEFT", 5, -6)
  scroll_frame:SetPoint("BOTTOMRIGHT", -28, 6)
  scroll_frame:EnableMouse(true)

  local scroll_child = api().CreateFrame("Frame", nil, scroll_frame)
  scroll_frame:SetScrollChild(scroll_child)
  scroll_child:SetHeight(2)
  scroll_child:SetWidth(2)

  local editbox = api().CreateFrame("EditBox", nil, scroll_child)
  editbox:SetPoint("TOPLEFT", 0, 0)
  editbox:SetHeight(50)
  editbox:SetWidth(50)
  editbox:SetMultiLine(true)
  editbox:SetTextInsets(5, 5, 3, 3)
  editbox:EnableMouse(true)
  editbox:SetAutoFocus(false)
  editbox:SetFontObject(ChatFontNormal)
  frame.editbox = editbox

  editbox:SetScript("OnEscapePressed", function() editbox:ClearFocus() end)
  scroll_frame:SetScript("OnMouseUp", function() editbox:SetFocus() end)

  local function fix_size()
    scroll_child:SetHeight(scroll_frame:GetHeight())
    scroll_child:SetWidth(scroll_frame:GetWidth())
    editbox:SetWidth(scroll_frame:GetWidth())
  end

  scroll_frame:SetScript("OnShow", fix_size)
  scroll_frame:SetScript("OnSizeChanged", fix_size)

  local cancel_button = api().CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  cancel_button:SetScript("OnClick", function()
    frame:Hide()
    editbox:SetText(on_cancel() or "")
  end)
  cancel_button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -27, 17)
  cancel_button:SetHeight(20)
  cancel_button:SetWidth(80)
  cancel_button:SetText("Close")

  local clear_button = api().CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  clear_button:SetScript("OnClick", function()
    editbox:SetText("")
    cancel_button:SetText("Close")
    on_clear()
  end)
  clear_button:SetPoint("RIGHT", cancel_button, "LEFT", -10, 0)
  clear_button:SetHeight(20)
  clear_button:SetWidth(80)
  clear_button:SetText("Clear")

  local import_button = api().CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.import_button = import_button
  import_button:SetScript("OnClick", function()
    on_import(function() frame:Hide() end)
  end)
  import_button:SetPoint("RIGHT", clear_button, "LEFT", -10, 0)
  import_button:SetHeight(20)
  import_button:SetWidth(100)
  import_button:SetText("Import!")

  editbox:SetScript("OnTextChanged", function()
    scroll_frame:UpdateScrollChildRect()
    on_dirty(import_button, clear_button, cancel_button)
  end)

  frame:SetScript("OnShow", function()
    cancel_button:SetText("Close")
    on_dirty(import_button, clear_button, cancel_button)
  end)

  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 22)
  label:SetTextColor(1, 1, 1, 1)
  label:SetText(m.colors.blue("RollFor") .. "      SR+ Data Import")

  table.insert(UISpecialFrames, "RollForSrPlusImportFrame")
  return frame
end

function M.new(api, import_encoded_srplus_data)
  local srplus_data
  local edit_box_text
  local dirty = false
  local frame

  local function on_import(close_window_fn)
    import_encoded_srplus_data(edit_box_text)
    srplus_data = edit_box_text
    close_window_fn()
  end

  local function on_clear()
    edit_box_text = nil
    srplus_data = nil
    dirty = false
    if frame then
      frame.editbox:SetText("")
      frame.editbox:SetFocus()
    end
  end

  local function on_cancel()
    edit_box_text = srplus_data
    dirty = false
    return srplus_data
  end

  local function on_dirty(import_button, clear_button, cancel_button)
    local text = frame.editbox:GetText()
    if text == "" then text = nil end
    if edit_box_text ~= text then
      dirty = true
      edit_box_text = text
    end
    cancel_button:SetText(dirty and "Cancel" or "Close")
    if dirty then
      import_button:Enable()
      clear_button:Enable()
      return
    end
    if text == nil then
      clear_button:Disable()
    else
      clear_button:Enable()
    end
    import_button:Disable()
  end

  local function toggle()
    if not frame then frame = create_frame(api, on_import, on_clear, on_cancel, on_dirty) end
    if frame:IsVisible() then
      frame:Hide()
    else
      dirty = false
      frame.editbox:SetText(srplus_data or "")
      frame:Show()
      if not srplus_data or srplus_data == "" then
        frame.editbox:SetFocus()
      end
    end
  end

  return {
    toggle = toggle
  }
end

m.SrPlusGui = M
return M
