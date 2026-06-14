local createNodeId = require("./createNodeId")

local freeze = table.freeze

return freeze({
	NodeIds = freeze({
		ViewButton = "view-button",
		MainMenu = "main-menu",
		CreatedListsMenu = "new-level-menu",
		SavedListsMenu = "saved-menu",
		MoveUpButton = "up-button",
		MoveDownButton = "down-button",
		SetIndexButton = "flip-button",
		ReorderButton = createNodeId("reorder-lists-button"),
	}),
	Sprites = freeze({
		UpButton = "edit_upBtn_001.png",
		DownButton = "edit_downBtn_001.png",
		SetIndexButton = "edit_flipYBtn_001.png",
		GreenButton = "GJ_button_01.png",
		RedButton = "GJ_button_06.png",
		GreyButton = "GJ_button_04.png",
		EditButton = "GJ_editModeBtn_001.png",
	}),
})
