local gd = geode.gd
local cocos2d = geode.cocos2d

type PendingListLayerOpen = {
	searchType: number,
	listID: number,
	localID: number,
}

local pendingReopenEditState: { searchType: number, editMode: boolean }? = nil
local pendingListLayerOpen: PendingListLayerOpen? = nil

local function isEditMode(layer: LevelBrowserLayer): boolean
	return geode.fields(layer).reorderListsEditMode == true
end

local function getListIndex(layer: LevelBrowserLayer, list: GJLevelList): number?
	local levels = layer.m_levels
	if not levels then
		return nil
	end

	local index = levels:indexOfObject(list)
	if index >= 0 and index < levels:count() then
		return index
	end

	for fallbackIndex = 0, levels:count() - 1 do
		local otherList = levels:objectAtIndex(fallbackIndex) :: GJLevelList?
		if
			otherList
			and (
				(list.m_M_ID ~= 0 and otherList.m_M_ID == list.m_M_ID)
				or (list.m_listID ~= 0 and otherList.m_listID == list.m_listID)
			)
		then
			return fallbackIndex
		end
	end

	return nil
end

local function listMatchesPending(list: GJLevelList, pending: PendingListLayerOpen): boolean
	if pending.localID ~= 0 and list.m_M_ID == pending.localID then
		return true
	end

	return pending.listID ~= 0 and list.m_listID == pending.listID
end

local function getManagerOwnedList(pending: PendingListLayerOpen): GJLevelList?
	if pending.searchType == gd.SearchType.MyLists then
		local localLevelManager = gd.LocalLevelManager.sharedState()
		if not localLevelManager then
			return nil
		end

		local lists = localLevelManager.m_localLists
		if lists then
			for index = 0, lists:count() - 1 do
				local list = lists:objectAtIndex(index) :: GJLevelList?
				if list and listMatchesPending(list, pending) then
					return list
				end
			end
		end

		return nil
	end

	if pending.searchType == gd.SearchType.FavouriteLists and pending.listID ~= 0 then
		local gameLevelManager = gd.GameLevelManager.sharedState()
		if not gameLevelManager then
			return nil
		end

		return gameLevelManager:getSavedLevelList(pending.listID)
	end

	return nil
end

local function persistListOrder(layer: LevelBrowserLayer)
	local fields = geode.fields(layer)
	if fields.reorderListsSearchType == gd.SearchType.MyLists then
		local localLevelManager = gd.LocalLevelManager.sharedState()
		if localLevelManager then
			localLevelManager:reorderLists()
			localLevelManager:updateListOrder()
		end

		return
	end

	local gameLevelManager = gd.GameLevelManager.sharedState()
	local levels = layer.m_levels
	if not gameLevelManager or not levels then
		return
	end

	for index = 0, levels:count() - 1 do
		local list = levels:objectAtIndex(index) :: GJLevelList?
		if list then
			local savedList = gameLevelManager:getSavedLevelList(list.m_listID) or list
			savedList.m_listOrder = list.m_listOrder
			gameLevelManager:updateSavedLevelList(savedList)
		end
	end
end

local function refreshBrowser(layer: LevelBrowserLayer)
	local search = layer.m_searchObject
	if search then
		layer:loadPage(search)
		return
	end

	layer:reloadAllObjects()
end

local function getFreshSearchObject(search: GJSearchObject): GJSearchObject?
	local pageObject = search:getPageObject(search.m_page)
	if pageObject then
		return pageObject
	end

	local keyObject = gd.GJSearchObject.createFromKey(search:getKey())
	if keyObject then
		return keyObject
	end

	return gd.GJSearchObject.create(search.m_searchType)
end

local function reopenBrowserSoon(layer: LevelBrowserLayer)
	local search = layer.m_searchObject
	local fields = geode.fields(layer)
	if not search or type(fields.reorderListsSearchType) ~= "number" then
		refreshBrowser(layer)
		return
	end

	local searchType = fields.reorderListsSearchType
	pendingReopenEditState = {
		searchType = searchType,
		editMode = isEditMode(layer),
	}

	layer:scheduleOnce(function()
		local freshSearch = getFreshSearchObject(search)
		if not freshSearch then
			pendingReopenEditState = nil
			refreshBrowser(layer)
			return
		end

		local scene = gd.LevelBrowserLayer.scene(freshSearch)
		local director = cocos2d.CCDirector.sharedDirector()
		if scene and director then
			director:replaceScene(scene)
			return
		end

		pendingReopenEditState = nil
		refreshBrowser(layer)
	end, 0)
end

local function moveListToIndex(layer: LevelBrowserLayer, list: GJLevelList, targetIndex: number)
	local levels = layer.m_levels
	local currentIndex = getListIndex(layer, list)
	if not levels or not currentIndex then
		return
	end

	local count = levels:count()
	targetIndex = math.clamp(targetIndex, 0, count - 1)
	if targetIndex == currentIndex then
		return
	end

	local orderedLists = {}
	for index = 0, count - 1 do
		orderedLists[index + 1] = levels:objectAtIndex(index) :: GJLevelList?
	end

	for index = 1, count do
		if not orderedLists[index] then
			return
		end
	end

	local movedList = table.remove(orderedLists, currentIndex + 1)
	table.insert(orderedLists, targetIndex + 1, movedList)

	for index = 1, count do
		orderedLists[index].m_listOrder = count - index
	end

	persistListOrder(layer)
	reopenBrowserSoon(layer)
end

local function openSetIndexPopup(layer: LevelBrowserLayer, list: GJLevelList)
	local levels = layer.m_levels
	local currentIndex = getListIndex(layer, list)
	if not levels or not currentIndex then
		return
	end

	local count = levels:count()
	local popup = gd.SetIDPopup.create(currentIndex + 1, 1, count, "Set Index", "Set", true, 1, count, false, false)
	if not popup then
		return
	end

	local fields = geode.fields(popup)
	fields.reorderListsPopup = true
	fields.reorderListsLayer = layer
	fields.reorderListsList = list
	popup:show()
end

local function usePendingReopenEditState(): { searchType: number, editMode: boolean }?
	local state = pendingReopenEditState
	pendingReopenEditState = nil
	return state
end

local function setPendingListLayerOpen(layer: LevelBrowserLayer, list: GJLevelList)
	local searchType = geode.fields(layer).reorderListsSearchType
	if type(searchType) ~= "number" then
		return
	end

	pendingListLayerOpen = {
		searchType = searchType,
		listID = list.m_listID,
		localID = list.m_M_ID,
	}
end

local function usePendingManagerOwnedList(list: GJLevelList): GJLevelList?
	local pending = pendingListLayerOpen
	pendingListLayerOpen = nil
	if not pending then
		return nil
	end

	if not listMatchesPending(list, pending) then
		return nil
	end

	return getManagerOwnedList(pending)
end

return table.freeze({
	isEditMode = isEditMode,
	getListIndex = getListIndex,
	moveListToIndex = moveListToIndex,
	openSetIndexPopup = openSetIndexPopup,
	usePendingReopenEditState = usePendingReopenEditState,
	setPendingListLayerOpen = setPendingListLayerOpen,
	usePendingManagerOwnedList = usePendingManagerOwnedList,
})
