local cocos = geode.cocos2d
local gd = geode.gd

local getBrowserLayerAncestor = require("./getBrowserLayerAncestor")

local ListLayerUtils = require("./ListLayerUtils")
local isEditMode = ListLayerUtils.isEditMode
local getListIndex = ListLayerUtils.getListIndex
local moveListToIndex = ListLayerUtils.moveListToIndex
local openSetIndexPopup = ListLayerUtils.openSetIndexPopup
local setPendingListLayerOpen = ListLayerUtils.setPendingListLayerOpen
local usePendingManagerOwnedList = ListLayerUtils.usePendingManagerOwnedList

local Constants = require("./Constants")
local NodeIds = Constants.NodeIds
local Sprites = Constants.Sprites

local EDIT_ACTION_BUTTON_SIZE = 36
local EDIT_ACTION_BUTTON_SCALE = 0.75
local EDIT_ACTION_ICON_SCALE = 0.76
local BUTTON_SPACING = 28
local BUTTON_GROUP_OFFSET_X = -8
local BOTTOM_MIDDLE_ANCHOR = { x = 0.5, y = 0 }

local function setSquareButtonSpriteSize(buttonSprite: ButtonSprite)
	local size = { width = EDIT_ACTION_BUTTON_SIZE, height = EDIT_ACTION_BUTTON_SIZE }
	local center = { x = EDIT_ACTION_BUTTON_SIZE * 0.5, y = EDIT_ACTION_BUTTON_SIZE * 0.5 }

	buttonSprite.m_width = EDIT_ACTION_BUTTON_SIZE
	buttonSprite.m_minWidth = EDIT_ACTION_BUTTON_SIZE
	buttonSprite.m_height = EDIT_ACTION_BUTTON_SIZE
	buttonSprite:setContentSize(size)

	local bgSprite = buttonSprite.m_BGSprite
	if bgSprite then
		bgSprite:setPreferredSize(size)
		bgSprite:setContentSize(size)
		bgSprite:setPosition(center)
	end

	local subSprite = buttonSprite.m_subSprite
	if subSprite then
		subSprite:setPosition(center)
	end
end

local function createEditActionButton(
	id: string,
	frame: string,
	bgImage: string,
	callback: (CCObject) -> ()
): CCMenuItemSpriteExtra
	local icon = cocos.CCSprite.createWithSpriteFrameName(frame) :: CCSprite
	local buttonSprite = gd.ButtonSprite.create(
		"",
		EDIT_ACTION_BUTTON_SIZE,
		true,
		"bigFont.fnt",
		bgImage,
		EDIT_ACTION_BUTTON_SIZE,
		1
	) :: ButtonSprite

	buttonSprite:setString("")
	if buttonSprite.m_label then
		buttonSprite.m_label:setVisible(false)
	end

	setSquareButtonSpriteSize(buttonSprite)
	icon:setScale(EDIT_ACTION_ICON_SCALE)
	icon:setPosition({ x = EDIT_ACTION_BUTTON_SIZE * 0.5, y = EDIT_ACTION_BUTTON_SIZE * 0.5 })
	buttonSprite:addChild(icon, 1)
	buttonSprite.m_subSprite = icon
	buttonSprite:updateSpriteOffset({ x = 0, y = 0 })
	setSquareButtonSpriteSize(buttonSprite)

	local button = cocos.CCMenuItemSpriteExtra.create(buttonSprite, callback)
	if button then
		button:setID(id)
		button:setScale(EDIT_ACTION_BUTTON_SCALE)
		button.m_baseScale = EDIT_ACTION_BUTTON_SCALE
		button:setSizeMult(1.2)
	end

	return button :: CCMenuItemSpriteExtra
end

local function removeButton(root: CCNode, id: string)
	local button = root:getChildByIDRecursive(id) :: CCMenuItemSpriteExtra?
	if not button then
		return
	end

	button:setEnabled(false)
	button:setVisible(false)
	button:removeFromParentAndCleanup(true)
end

local function removeEditActionButtons(root: CCNode)
	removeButton(root, NodeIds.SetIndexButton)
	removeButton(root, NodeIds.MoveDownButton)
	removeButton(root, NodeIds.MoveUpButton)
end

local function setEditActionButtonsVisible(menu: CCMenu, visible: boolean)
	local children = menu:getChildren()
	if not children then
		return
	end

	for index = 0, children:count() - 1 do
		local button = children:objectAtIndex(index) :: CCMenuItemSpriteExtra?
		if button then
			local id = button:getID()
			if id == NodeIds.SetIndexButton or id == NodeIds.MoveDownButton or id == NodeIds.MoveUpButton then
				button:setVisible(visible)
				button:setEnabled(visible)
			end
		end
	end
end

local function getEditActionButton(menu: CCMenu, id: string): CCMenuItemSpriteExtra?
	local children = menu:getChildren()
	if not children then
		return nil
	end

	for index = 0, children:count() - 1 do
		local button = children:objectAtIndex(index) :: CCMenuItemSpriteExtra?
		if button and button:getID() == id then
			return button
		end
	end

	return nil
end

local function upsertEditActionButton(
	menu: CCMenu,
	id: string,
	frame: string,
	bgImage: string,
	position: CCPoint,
	callback: (CCObject) -> ()
): (CCMenuItemSpriteExtra, boolean)
	local existingButton = getEditActionButton(menu, id)
	local created = false
	if not existingButton then
		local newButton = createEditActionButton(id, frame, bgImage, callback)
		menu:addChild(newButton)
		created = true
		existingButton = newButton
	else
		existingButton:setTarget(callback)
	end

	local button = existingButton :: CCMenuItemSpriteExtra
	button:setPosition(position)
	button:setVisible(true)
	button:setEnabled(true)
	return button, created
end

local function updateCellEditControls(cell: LevelListCell)
	local list = cell.m_levelList
	local layer = getBrowserLayerAncestor(cell)
	if not list or not layer then
		local viewButton = cell:getChildByIDRecursive(NodeIds.ViewButton) :: CCMenuItemSpriteExtra?
		if not viewButton then
			return
		end

		viewButton:setVisible(true)
		viewButton:setEnabled(true)

		local menu = cell:getChildByIDRecursive(NodeIds.MainMenu) :: CCMenu?
		if menu then
			removeEditActionButtons(menu)
		end
		return
	end

	local menu = cell:getChildByIDRecursive(NodeIds.MainMenu) :: CCMenu?
	local viewButton = if menu then menu:getChildByID(NodeIds.ViewButton) :: CCMenuItemSpriteExtra? else nil
	if not menu or not viewButton then
		return
	end

	local editMode = isEditMode(layer)
	viewButton:setVisible(not editMode)
	viewButton:setEnabled(not editMode)

	if not editMode then
		setEditActionButtonsVisible(menu, false)
		return
	end

	-- rob put the list author in this menu for some reason 😭
	local viewPosition = viewButton:getPosition()
	local position = { x = viewPosition.x + BUTTON_GROUP_OFFSET_X, y = 0 }
	local index = getListIndex(layer, list) or 0
	local count = layer.m_levels and layer.m_levels:count() or 0

	local setIndexButton, setIndexButtonCreated = upsertEditActionButton(
		menu,
		NodeIds.SetIndexButton,
		Sprites.SetIndexButton,
		Sprites.GreyButton,
		{ x = position.x + BUTTON_SPACING, y = position.y },
		function()
			openSetIndexPopup(layer, list)
		end
	)
	local downButton, downButtonCreated = upsertEditActionButton(
		menu,
		NodeIds.MoveDownButton,
		Sprites.DownButton,
		Sprites.RedButton,
		position,
		function()
			moveListToIndex(layer, list, index + 1)
		end
	)
	local upButton, upButtonCreated = upsertEditActionButton(
		menu,
		NodeIds.MoveUpButton,
		Sprites.UpButton,
		Sprites.GreenButton,
		{ x = position.x - BUTTON_SPACING, y = position.y },
		function()
			moveListToIndex(layer, list, index - 1)
		end
	)

	if setIndexButtonCreated then
		menu:insertAfter(setIndexButton, viewButton)
	end
	setIndexButton:setEnabled(count > 1)

	if downButtonCreated then
		menu:insertAfter(downButton, setIndexButton)
	end
	downButton:setEnabled(index < count - 1)

	if upButtonCreated then
		menu:insertAfter(upButton, downButton)
	end
	upButton:setEnabled(index > 0)
end

local function updateVisibleCells(layer: LevelBrowserLayer)
	local listLayer = layer.m_list
	local listView = listLayer and listLayer.m_listView
	local tableView = listView and listView.m_tableView
	local cells = tableView and tableView.m_cellArray
	if not cells then
		return
	end

	for index = 0, cells:count() - 1 do
		local cell = cells:objectAtIndex(index) :: LevelListCell?
		if cell and cell.m_levelList then
			updateCellEditControls(cell)
		end
	end
end

local function setupEditModeButton(button: CCMenuItemSpriteExtra, layer: LevelBrowserLayer)
	button:setID(NodeIds.ReorderButton)
	button:setScale(1)
	button.m_baseScale = 1
	button:setSizeMult(1.35)
	button:setTarget(function()
		local fields = geode.fields(layer)
		fields.reorderListsEditMode = not fields.reorderListsEditMode

		updateVisibleCells(layer)
	end)
end

local function ensureActionMenuLayout(menu: CCMenu)
	if menu:getLayout() then
		return
	end

	local layout = geode.ColumnLayout.create()
	if not layout then
		return
	end

	layout:ignoreInvisibleChildren(true)
	layout:setAxisAlignment(geode.AxisAlignment.Start)
	menu:setPositionY(0)
	menu:setAnchorPoint(BOTTOM_MIDDLE_ANCHOR)
	menu:setLayout(layout, true, true)
end

local function addEditModeButton(layer: LevelBrowserLayer)
	local menu = (layer:getChildByID(NodeIds.CreatedListsMenu) or layer:getChildByID(NodeIds.SavedListsMenu)) :: CCMenu?
	if not menu then
		return
	end

	ensureActionMenuLayout(menu)

	local existingButton = menu:getChildByID(NodeIds.ReorderButton) :: CCMenuItemSpriteExtra?
	if existingButton then
		setupEditModeButton(existingButton, layer)
		menu:updateLayout(true)
		return
	end

	local sprite = cocos.CCSprite.createWithSpriteFrameName(Sprites.EditButton)
	if not sprite then
		return
	end

	local button = cocos.CCMenuItemSpriteExtra.create(sprite, function() end)
	if not button then
		return
	end

	setupEditModeButton(button, layer)
	menu:addChild(button)
	menu:updateLayout(true)
end

geode.hook("geode.gd.SetIDPopup:onClose/1", {
	before = function(popup: SetIDPopup, _sender: CCObject)
		local fields = geode.fields(popup)
		if not fields.reorderListsPopup then
			return
		end

		local layer = fields.reorderListsLayer :: LevelBrowserLayer?
		local list = fields.reorderListsList :: GJLevelList?
		if not layer or not list then
			return nil
		end

		local value = popup.m_value
		if popup.m_inputNode then
			local inputValue = tonumber(popup.m_inputNode:getString())
			if inputValue then
				value = inputValue
			end
		end

		moveListToIndex(layer, list, value - 1)

		return
	end,
})

geode.hook("geode.gd.LevelBrowserLayer:init/1", {
	after = function(layer: LevelBrowserLayer, search: GJSearchObject)
		local searchType = search.m_searchType
		if searchType ~= gd.SearchType.MyLists and searchType ~= gd.SearchType.FavouriteLists then
			return
		end

		local pendingReopenEditState = ListLayerUtils.usePendingReopenEditState()
		local fields = geode.fields(layer)
		fields.reorderListsBrowser = true
		fields.reorderListsSearchType = searchType
		fields.reorderListsEditMode = pendingReopenEditState ~= nil
			and pendingReopenEditState.searchType == searchType
			and pendingReopenEditState.editMode == true

		local ok, err = pcall(function()
			addEditModeButton(layer)
			updateVisibleCells(layer)

			layer:scheduleOnce(function()
				updateVisibleCells(layer)
			end, 0)
		end)
		if not ok then
			print(`failed to add edit mode button: {err}`)
		end

		return
	end,
})

geode.hook("geode.gd.LevelBrowserLayer:setupLevelBrowser/1", {
	after = function(layer: LevelBrowserLayer, _objects: CCArray)
		if geode.fields(layer).reorderListsBrowser ~= true then
			return
		end

		local ok, err = pcall(function()
			updateVisibleCells(layer)
		end)

		if not ok then
			print(`failed to update visible cells: {err}`)
		end

		return
	end,
})

geode.hook("geode.gd.LevelListCell:onClick/1", {
	before = function(cell: LevelListCell, _sender: CCObject)
		local layer = getBrowserLayerAncestor(cell)
		local list = cell.m_levelList
		if not layer or not list then
			return
		end

		setPendingListLayerOpen(layer, list)
		return
	end,
})

geode.hook("geode.gd.LevelListLayer:init/1", {
	before = function(_layer: LevelListLayer, list: GJLevelList)
		local managerList = usePendingManagerOwnedList(list)
		if managerList then
			return { args = { managerList } }
		end

		return
	end,
})

geode.hook("geode.gd.LevelListCell:loadFromList/1", {
	after = function(cell: LevelListCell, _list: GJLevelList)
		local ok, err = pcall(function()
			updateCellEditControls(cell)
		end)

		if not ok then
			print(`failed to update list cell: {err}`)
		end

		return
	end,
})
