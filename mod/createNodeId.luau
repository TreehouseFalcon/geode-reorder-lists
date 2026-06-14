local MOD_ID = geode.Mod.getID()

return function(nodeId: string)
	return `{MOD_ID}/{nodeId}`
end
