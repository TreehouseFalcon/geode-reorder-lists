local function getBrowserLayerAncestor(node: CCNode?): LevelBrowserLayer?
	local current = node
	while current do
		if geode.fields(current).reorderListsBrowser == true then
			return current :: LevelBrowserLayer
		end

		current = current:getParent()
	end

	return nil
end

return getBrowserLayerAncestor
