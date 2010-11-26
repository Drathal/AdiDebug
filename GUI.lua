--[[
AdiDebug - Adirelle's debug self.
Copyright 2010 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local addonName = ...
local AdiDebugGUI = CreateFrame("Frame", "AdiDebugGUI", UIParent)
AdiDebugGUI:Hide()

local AdiDebug = AdiDebug

local ALPHA_DELAY = 0.25

-- ----------------------------------------------------------------------------
-- Scroll bar and message handling
-- ----------------------------------------------------------------------------

function AdiDebugGUI:UpdateScrollBar()
	if self.safetyLock then return end
	local numMessages, displayed = self.Messages:GetNumMessages(), self.Messages:GetNumLinesDisplayed()
	local newMax = max(0, numMessages - displayed)
	local scrollBar = self.ScrollBar
	if newMax > 0 then
		self.safetyLock = true
		if newMax ~= select(2, scrollBar:GetMinMaxValues()) then
			scrollBar:SetMinMaxValues(0, newMax)
		end
		local offset = max(0, newMax - self.Messages:GetCurrentScroll())
		if offset ~=scrollBar:GetValue() then
			scrollBar:SetValue(offset)
		end
		self.safetyLock = false
		if not scrollBar:IsShown() then
			scrollBar:Show()
		end
	elseif scrollBar:IsShown() then
		scrollBar:Hide()
	end
end

function AdiDebugGUI:SetVerticalScroll(value)
	if self.safetyLock then return end
	local _, maxVal = self.ScrollBar:GetMinMaxValues()
	local offset = maxVal - value
	if self.Messages:GetCurrentScroll() ~= offset then
		self.safetyLock = true
		self.Messages:SetScrollOffset(offset)
		self.safetyLock = false
	end
end

local id = 0
local categoryIds = setmetatable({}, {__index = function(t,k)
	id = id + 1
	t[k] = id
	return id
end})

function AdiDebugGUI:GetCategoryId(streamId, category)
	return categoryIds[strjoin('/', streamId, category)]
end

function AdiDebugGUI:AddMessage(category, timestamp, text)
	if not self.db.profile.categories[self.currentStreamId][category] then
		return
	end
	if timestamp ~= self.currentTimestamp then
		self.Messages:AddMessage(strjoin("", "----- ", date("%X", timestamp), strsub(format("%.3f", timestamp % 1), 2)), 0.6, 0.6, 0.6)
		self.currentTimestamp = timestamp
	end
	local r, g, b = unpack(self.db.profile.categoryColors[self.currentStreamId][category])
	self.Messages:AddMessage(text, r, g, b, self:GetCategoryId(self.currentStreamId, category))
end

function AdiDebugGUI:RefreshMessages()
	self.Messages:Clear()
	self.currentTimestamp = nil
	if self.currentStreamId then
		for i, category, now, text in AdiDebug:IterateMessages(self.currentStreamId) do
			self:AddMessage(category, now, text)
		end
	end
	self:UpdateScrollBar()
end

function AdiDebugGUI:SelectStream(streamId)
	if not AdiDebug:HasStream(streamId) then return end
	self.db.profile.streamId = streamId
	if streamId == self.currentStreamId then return end
	self.currentStreamId = streamId
	self.Selector.Text:SetText(streamId or "")
	self:RefreshMessages()
	return true
end

-- ----------------------------------------------------------------------------
-- Selector menu handling
-- ----------------------------------------------------------------------------

local streamEntryMeta = { __index = {
	checked = function(button)
		return AdiDebugGUI.currentStreamId and button.value == AdiDebugGUI.currentStreamId
	end,
	func = function(button)
		AdiDebugGUI:SelectStream(button.value)
	end,
}}

local categoryEntryMeta = { __index = {
	isNotRadio = true,
	keepShownOnClick = true,
	hasColorSwatch = true,
	checked = function(button)
		return AdiDebugGUI.db.profile.categories[button.arg1][button.value]
	end,
	func = function(button, streamId, _, checked)
		AdiDebugGUI.db.profile.categories[button.arg1][button.value] = checked
		if streamId == AdiDebugGUI.currentStreamId then
			AdiDebugGUI:RefreshMessages()
		end
	end,
}}

local function SetAllCategories(streamId, shown)
	local db = AdiDebugGUI.db.profile.categories[streamId]
	db[streamId] = shown
	for category in AdiDebug:IterateCategories(streamId) do
		db[category] = shown
	end
	if streamId == AdiDebugGUI.currentStreamId then
		AdiDebugGUI:RefreshMessages()
	end
end

local selectAllEntryMeta = { __index = {
	text = "Select all",
	notCheckable = true,
	__order = 10,
	func = function(button) SetAllCategories(button.value, true) end,
}}

local unselectAllEntryMeta = { __index = {
	text = "Unselect all",
	notCheckable = true,
	__order = 20,
	func = function(button) SetAllCategories(button.value, false) end,
}}

local closeEntry = {
	text = "Close menu",
	notCheckable = true,
	__order = 30,
}

local function SortEntries(a, b) -- a < b
	local orderA = a.__order or 0
	local orderB = b.__order or 0
	if orderA == orderB then
		return a.text < b.text
	else
		return orderA < orderB
	end
end

function AdiDebugGUI:AddMenuStreamEntry(streamId)
	local entry = setmetatable({
		text = streamId,
		value = streamId,
		__categories = {}
	}, streamEntryMeta)
	self.menuStreamEntries[streamId] = entry
	tinsert(self.menuList, entry)
	table.sort(self.menuList, SortEntries)
	self:AddMenuCategoryEntry(streamId, streamId)
end

function AdiDebugGUI:AddMenuCategoryEntry(streamId, category)
	local streamEntry = self.menuStreamEntries[streamId]
	local entry = setmetatable({
		text = category,
		value = category,
		arg1 = streamId,
		swatchFunc = function() AdiDebugGUI:SetCategoryColor(streamId, category, ColorPickerFrame:GetColorRGB()) end,
		cancelFunc = function(values) AdiDebugGUI:SetCategoryColor(streamId, category, values.r, values.g, values.b) end,
	}, categoryEntryMeta)
	entry.r, entry.g, entry.b = unpack(self.db.profile.categoryColors[streamId][category])
	if category == streamId then
		entry.__order = -10
	end
	streamEntry.__categories[category] = entry

	if not streamEntry.menuList then
		streamEntry.menuList = {
			setmetatable({ value = streamId }, selectAllEntryMeta),
			setmetatable({ value = streamId }, unselectAllEntryMeta),
			closeEntry,
		}
	end

	local menu = streamEntry
	while #(menu.menuList) > 25 do
		if not menu.__subMenu then
			menu.__subMenu = {
				text = "...",
				notCheckable = true,
				hasArrow = true,
				order = 5,
				menuList = { closeEntry }
			}
			tinsert(menu.menuList, menu.__subMenu)
			table.sort(menu.menuList, SortEntries)
		end
		menu = menu.__subMenu
	end
	tinsert(menu.menuList, entry)
	table.sort(menu.menuList, SortEntries)

	if not streamEntry.hasArrow and #streamEntry.menuList > 4 then
		streamEntry.hasArrow = true
	end
end

function AdiDebugGUI:SetCategoryColor(streamId, category, r, g, b)
	if not AdiDebug:HasStream(streamId) then return end
	local entry = self.menuStreamEntries[streamId].__categories[category]
	local c = self.db.profile.categoryColors[streamId][category]
	c[1], c[2], c[3] = r, g, b
	entry.r, entry.g, entry.b = r, g, b
	if streamId == self.currentStreamId then
		self.Messages:UpdateColorByID(self:GetCategoryId(streamId, category), r, g, b)
	end
end

-- ----------------------------------------------------------------------------
-- AdiDebug callback handlers
-- ----------------------------------------------------------------------------

function AdiDebugGUI:AdiDebug_NewStream(event, streamId)
	self:AddMenuStreamEntry(streamId)
	if not self.currentStreamId and streamId == self.db.profile.streamId then
		self:SelectStream(streamId)
	end
end

function AdiDebugGUI:AdiDebug_NewCategory(event, streamId, category)
	self:AddMenuCategoryEntry(streamId, category)
end

function AdiDebugGUI:AdiDebug_NewMessage(event, streamId, category, now, text)
	if streamId == self.currentStreamId then
		self:AddMessage(category, now, text)
		self:UpdateScrollBar()
	end
end

-- ----------------------------------------------------------------------------
-- Script handlers
-- ----------------------------------------------------------------------------

function AdiDebugGUI:OnMouseDown()
	if not self.movingOrSizing and IsModifierKeyDown() then
		local x, y = GetCursorPosition()
		local scale = self:GetEffectiveScale()
		local left, bottom, width, height = self:GetRect()
		x, y = (x / scale) - left, (y / scale) - bottom
		local horiz = (x < 16) and "LEFT" or (x > width - 16) and "RIGHT"
		local vert = (y < 16) and "BOTTOM" or (y > height - 16) and "TOP"
		if horiz or vert then
			self:StartSizing(strjoin("", vert or "", horiz or ""))
		else
			self:StartMoving()
		end
		self.movingOrSizing = true
	end
end

function AdiDebugGUI:OnMouseUp()
	if self.movingOrSizing then
		self.movingOrSizing = nil
		self:StopMovingOrSizing()
		self.db.profile.width, self.db.profile.height = self:GetSize()
		local _
		_, _, self.db.profile.point, self.db.profile.xOffset, self.db.profile.yOffset = self:GetPoint()
	end
end

function AdiDebugGUI:OnShow()
	self.db.profile.shown = true
	self:UpdateScrollBar()
end

function AdiDebugGUI:OnHide()
	self.db.profile.shown = false
end

-- ----------------------------------------------------------------------------
-- Frame/table tooltips
-- ----------------------------------------------------------------------------

local getters = {
	-- UIObject
	"GetObjectType",
	-- Region
	"GetParent", "IsProtected", "GetRect",
	-- VisibleRegion
	"GetAlpha", "IsShown", "IsVisible",
	-- Frame
	"GetFrameStrata",	"GetFrameLevel", "GetScale", "GetID", "GetNumChildren", "GetNumRegions",
  "GetPropagateKeyboardInput", "IsClampedToScreen", "IsJoystickEnabled", "IsKeyboardEnabled", "IsMouseEnabled",
	"IsMouseWheelEnabled", "IsMovable", "IsResizable", "IsToplevel", "IsUserPlaced",
	"GetBackdrop", "GetBackdropBorderColor", "GetBackdropColor",
	-- Button
	"GetButtonState",	"GetMotionScriptsWhileDisabled", "GetTextHeight", "GetTextWidth", "IsEnabled",
	"GetDisabledTexture", "GetDisabledFontObject", "GetFontString", "GetHighlightFontObject", "GetHighlightTexture",
	"GetNormalFontObject", "GetNormalTexture", "GetPushedTextOffset", "GetPushedTexture",
	-- CheckButton
	"GetChecked",
	-- ScrollFrame
	"GetHorizontalScroll", "GetHorizontalScrollRange","GetVerticalScroll", "GetVerticalScrollRange", "GetScrollChild",
	-- Slider
	"GetMinMaxValues", "GetOrientation", "GetThumbTexture", "GetValue", "GetValueStep",
	-- StatusBar
	"GetRotatesTexture", "GetStatusBarColor", "GetStatusBarTexture",
	-- FontInstance
	"GetFontObject", "GetJustifyH", "GetJustifyV", "GetShadowColor", "GetShadowOffset", "GetSpacing", "GetTextColor",
	-- FontString
	"GetFieldSize", "GetIndentedWordWrap", "GetText", "GetStringWidth", "GetStringHeight", "IsTruncated",
	"CanNonSpaceWrap", "CanWordWrap",
	-- Texture
	"GetBlendMode", "GetNonBlocking", "GetTexture", "GetHorizTile", "GetVertTile", "IsDesaturated",	"GetTexCoord", "GetVertexColor",
	-- GameTooltip
	"GetOwner", "GetUnit", "GetSpell", "GetItem", "IsEquippedItem",
}

local t = {}
local function Format(...)
	local n = max(1, select('#', ...))
	for i = 1, n do
		t[i] = AdiDebug:PrettyFormat(select(i, ...), true, 30)
	end
	return table.concat(t, ", ", 1, n)
end

local bools = {}
local function ShowUIObjectTooltip(obj)
	-- We're doing duck typing there
	local haveBools = false
	for i, getter in ipairs(getters) do
		if type(obj[getter]) == "function" then
			local label = strmatch(getter, "^Is(%w+)$") or strmatch(getter, "^(Can%w+)$")
			if label then
				haveBools = true
				if obj[getter](obj) then
					tinsert(bools, label)
				end
			else
				GameTooltip:AddDoubleLine(strmatch(getter, "^Get(%w+)$") or getter, Format(obj[getter](obj)), nil, nil, nil, 1, 1, 1)
			end
		end
	end
	if haveBools then
		if #bools > 0 then
			GameTooltip:AddDoubleLine("Flags", table.concat(bools, ", "), nil, nil, nil, 1, 1, 1)
			wipe(bools)
		else
			GameTooltip:AddDoubleLine("Flags", "-", nil, nil, nil, 1, 1, 1)
		end
	end
end

local function ShowTableTooltip(value)
	local mt = getmetatable(value)
	setmetatable(value, nil)
	GameTooltip:AddDoubleLine("Metatable", AdiDebug:PrettyFormat(mt, true), nil, nil, nil, 1, 1, 1)
	local n = 0
	for k, v in pairs(value) do
		if n == 0 then
			GameTooltip:AddLine("Content:")
		end
		if n < 10 then
			GameTooltip:AddDoubleLine(AdiDebug:PrettyFormat(k, true, 30), AdiDebug:PrettyFormat(v, true, 30), 1, 1, 1, 1, 1, 1)
		end
		n = n + 1
	end
	if n > 10 then
		GameTooltip:AddLine(format("|cffaaaaaa%d more entries...|r", n-10))
	end
	setmetatable(value, mt)
end

-- ----------------------------------------------------------------------------
-- Widget script handlers
-- ----------------------------------------------------------------------------

local function Messages_OnHyperlinkClick(self, data, link)
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
	GameTooltip:ClearLines()
	local t, tableType = AdiDebug:GetTableHyperlinkTable(link)
	if t then
		GameTooltip:AddDoubleLine(link, tableType)
		if tableType == "table" then
			ShowTableTooltip(t)
		else
			ShowUIObjectTooltip(t)
		end
	else
		GameTooltip:SetHyperlink(link)
	end
	GameTooltip:Show()
end

local function Messages_OnHyperlinkEnter(self, data, link)
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
	GameTooltip:ClearLines()
	GameTooltip:AddLine(link)
	local _, tableType = AdiDebug:GetTableHyperlinkTable(link)
	local linkType, linkData = strsplit(':', data, 2)
	GameTooltip:AddDoubleLine("Link type", tableType or linkType)
	GameTooltip:AddDoubleLine("Link data", linkData)
	GameTooltip:AddLine("|cffaaaaaaClick for more details.|r")
	GameTooltip:Show()
end

local function Messages_OnMouseWheel(self, delta)
	local num, displayed = self:GetNumMessages(), self:GetNumLinesDisplayed()
	local step = IsShiftKeyDown() and num or IsControlKeyDown() and displayed or 1
	local current = self:GetCurrentScroll()
	local newOffset = min(max(0, current + step * delta), num - displayed)
	if newOffset ~= current then
		self:SetScrollOffset(newOffset)
		AdiDebugGUI:UpdateScrollBar()
	end
end

local function Background_GetSettings()
	local settings = AdiDebugGUI.db.profile
	if settings.autoFadeOut then
		return AdiDebugGUI.movingOrSizing or AdiDebugGUI:IsMouseOver(), settings.opacity, 0.95
	else
		return true, 0.1, settings.opacity
	end
end

local function Background_OnUpdate(self, elapsed)
	local alpha, newAlpha = self:GetAlpha()
	local goMax, minAlpha, maxAlpha = Background_GetSettings()
	if goMax then
		newAlpha = min(maxAlpha, alpha + (maxAlpha - minAlpha) * elapsed / ALPHA_DELAY)
	else
		newAlpha = max(minAlpha, alpha - (maxAlpha - minAlpha) * elapsed / ALPHA_DELAY)
	end
	if newAlpha ~= alpha then
		self:SetAlpha(newAlpha)
	end
end

local function Background_OnShow(self)
	local goMax, minAlpha, maxAlpha = Background_GetSettings()
	self:SetAlpha(goMax and maxAlpha or minAlpha)
end

local function ShowTooltipText(self)
	GameTooltip:ClearLines()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.tooltipText)
	GameTooltip:Show()
end

-- ----------------------------------------------------------------------------
-- GUI initialization
-- ----------------------------------------------------------------------------

AdiDebugGUI:SetScript('OnShow', function(self)

	self:SetSize(self.db.profile.width, self.db.profile.height)
	self:SetPoint(self.db.profile.point, self.db.profile.xOffset, self.db.profile.yOffset)
	self:SetClampedToScreen(true)
	self:SetClampRectInsets(4,-4,-4,4)
	self:SetMovable(true)
	self:SetResizable(true)
	self:SetFrameStrata("FULLSCREEN_DIALOG")
	self:SetToplevel(true)
	self:SetMinResize(300, 120)
	self:EnableMouse(true)
	self:SetScript('OnMouseDown', self.OnMouseDown)
	self:SetScript('OnMouseUp', self.OnMouseUp)
	self:SetScript('OnShow', self.OnShow)
	self:SetScript('OnHide', self.OnHide)

	----- Background -----

	local background = CreateFrame("Frame", nil, self)
	background:SetAllPoints(self)
	background:SetBackdrop({
		bgFile = [[Interface\Addons\AdiDebug\media\white16x16]], tile = true, tileSize = 16,
		edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	background:SetBackdropColor(0,0,0,0.9)
	background:SetBackdropBorderColor(1,1,1,1)
	background:SetScript('OnUpdate', Background_OnUpdate)
	background:SetScript('OnShow', Background_OnShow)
	Background_OnShow(background)

	local function AttachTooltip(target, text)
		target.tooltipText = text
		target:SetScript('OnEnter', ShowTooltipText)
		target:SetScript('OnLeave', GameTooltip_Hide)
	end

	----- Close button -----

	local closeButton = CreateFrame("Button", nil, background, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT")
	closeButton:SetScript('OnClick', function() self:Hide() end)
	AttachTooltip(closeButton, "Hide")

	----- Stream selector -----

	local menuFrame = CreateFrame("Frame", "AdiDebugDropdownMenu", nil, "UIDropDownMenuTemplate")
	self.menuList = { closeEntry }
	self.menuStreamEntries = {}

	local selector = CreateFrame("Button", "AdiDebugDropdown", background, "UIDropDownMenuTemplate")
	selector:SetPoint("TOPLEFT", -12, -4)
	selector:SetWidth(145)
	selector.Text = AdiDebugDropdownText
	AttachTooltip(selector, "Debugging stream\nSelect the debugging stream to watch.")
	self.Selector = selector

	AdiDebugDropdownButton:SetScript('OnClick', function()
		return EasyMenu(self.menuList, menuFrame, "AdiDebugDropdown", 16, 8, "MENU")
	end)

	----- Message area -----

	local messages = CreateFrame("ScrollingMessageFrame", nil, self)
	messages:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -28)
	messages:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -24, 8)
	messages:SetFading(false)
	messages:SetJustifyH("LEFT")
	messages:SetMaxLines(550)
	messages:SetFontObject(ChatFontNormal)
	messages:SetShadowOffset(1, -1)
	messages:SetShadowColor(0, 0, 0, 1)
	messages:Raise()
	messages:SetIndentedWordWrap(true)
	messages:SetHyperlinksEnabled(true)
	messages:EnableMouseWheel(true)
	local UpdateScrollBar = function() self:UpdateScrollBar() end
	messages:SetScript('OnMessageScrollChanged', UpdateScrollBar)
	messages:SetScript('OnSizeChanged', UpdateScrollBar)
	messages:SetScript('OnHyperlinkClick', Messages_OnHyperlinkClick)
	messages:SetScript('OnHyperlinkEnter', Messages_OnHyperlinkEnter)
	messages:SetScript('OnHyperlinkLeave', GameTooltip_Hide)
	messages:SetScript('OnLeave', GameTooltip_Hide)
	messages:SetScript('OnMouseWheel', Messages_OnMouseWheel)
	self.Messages = messages

	----- Scroll bar -----

	local scrollBar = CreateFrame("Slider", nil, background, "UIPanelScrollBarTemplate")
	scrollBar:Hide()
	scrollBar:SetPoint("TOPRIGHT", self, "TOPRIGHT", -8, -44)
	scrollBar:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -8, 24)
	scrollBar:SetValueStep(1)
	scrollBar.scrollStep = 3
	scrollBar:GetParent().SetVerticalScroll = function(_, value) self:SetVerticalScroll(value) end
	self.ScrollBar = scrollBar

	----- Auto fade button -----

	local autoFadeButton = CreateFrame("CheckButton", nil, background, "UICheckButtonTemplate")
	autoFadeButton:RegisterForClicks("anyup")
	autoFadeButton:SetSize(24, 24)
	autoFadeButton:SetPoint("TOPRIGHT", -32, -4)
	autoFadeButton:SetScript('OnClick', function(button) self.db.profile.autoFadeOut = not not button:GetChecked() end)
	autoFadeButton:SetChecked(self.db.profile.autoFadeOut)
	AttachTooltip(autoFadeButton, "Auto fade out\nAutomatically fade out the self when the mouse cursor is not hovering it.")

	----- Opacity slider -----

	local opacitySlider = CreateFrame("Slider", nil, background)
	opacitySlider:SetSize(80, 16)
	opacitySlider:EnableMouse(true)
	opacitySlider:SetOrientation("HORIZONTAL")
	opacitySlider:SetBackdrop({
		bgFile = [[Interface\Buttons\UI-SliderBar-Background]], tile = true, tileSize = 8,
		edgeFile = [[Interface\Buttons\UI-SliderBar-Border]], edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 }
	})
	opacitySlider:SetThumbTexture([[Interface\Buttons\UI-SliderBar-Button-Horizontal]])
	opacitySlider:SetPoint("TOPRIGHT", -64, -8)
	opacitySlider:SetValueStep(0.05)
	opacitySlider:SetMinMaxValues(0.1, 0.95)
	opacitySlider:SetValue(self.db.profile.opacity)
	opacitySlider:SetScript('OnValueChanged', function(_, value) self.db.profile.opacity = value end)
	AttachTooltip(opacitySlider, "Frame opacity\nAdjust the self opacity.\nThis is the lowest opacity if auto fading is enabled else it is the self opacity.")

	-- Register callbacks
	AdiDebug.RegisterCallback(self, "AdiDebug_NewStream")
	AdiDebug.RegisterCallback(self, "AdiDebug_NewCategory")
	AdiDebug.RegisterCallback(self, "AdiDebug_NewMessage")

	-- Fetch existing streams and categories
	for streamId in AdiDebug:IterateStreams() do
		self:AdiDebug_NewStream('Initialize', streamId)
		for category in AdiDebug:IterateCategories(streamId) do
			self:AdiDebug_NewCategory('Initialize', streamId, category)
		end
	end

end)

-- ----------------------------------------------------------------------------
-- Addon initialization
-- ----------------------------------------------------------------------------

AdiDebugGUI:SetScript('OnEvent', function(self, event, name)
	if event == 'ADDON_LOADED' and name == addonName then
		self:UnregisterEvent('ADDON_LOADED')
		self:SetScript('OnEvent', nil)

		self.db = AdiDebug.db:RegisterNamespace("GUI", {
			profile = {
				point = "TOPLEFT",
				xOffset = 16,
				yOffset = -200,
				width = 640,
				height = 400,
				categories = { ['*'] = { ['*'] = true } },
				categoryColors = { ['*'] = { ['*'] = { 1, 1, 1 } } },
				autoFadeOut = false,
				opacity = 0.95,
				shown = false,
			}
		}, true)

		if self.db.profile.shown then
			self:Show()
		end
	end
end)
AdiDebugGUI:RegisterEvent('ADDON_LOADED')

-- ----------------------------------------------------------------------------
-- Chat Command
-- ----------------------------------------------------------------------------

SLASH_ADIDEBUG1 = "/ad"
SLASH_ADIDEBUG2 = "/adidebug"
function SlashCmdList.ADIDEBUG(arg)
	if strtrim(arg) == "" then
		arg = nil
	end
	if not arg and AdiDebugGUI:IsShown() then
		AdiDebugGUI:Hide()
		return
	end
	AdiDebugGUI:Show()
	if arg then
		arg = strlower(arg)
		for streamId in AdiDebug:IterateStreams() do
			if strlower(streamId) == arg then
				AdiDebugGUI:SelectStream(streamId)
			end
		end
	end
end
