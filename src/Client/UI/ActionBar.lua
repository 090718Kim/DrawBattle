--!strict
--[[
	ActionBar.lua  —  되돌리기 / 다시하기 / 전체지우기

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	오른쪽 세로줄(SideBar) 안에 들어가는 버튼 묶음이다.
	자리와 배율은 세로줄이 정하므로 여기서는 버튼만 만든다.

	왜 캔버스 위가 아니라 오른쪽인가
	  예전에는 캔버스 바로 위에 가로로 눕혀뒀다.
	  그러면 상단 바(주제/제출/시간)와 **같은 높이**를 두고 다투게 되고,
	  화면이 좁아지면 반드시 겹친다. 실제로 모바일·태블릿에서 겹쳤다.
	  게다가 위쪽 자리를 그만큼 잡아먹어서 그림이 아래로 밀렸다.

	  오른쪽 세로줄로 옮기면 위쪽 자리를 아예 안 쓴다.
	  그림이 더 커지고, 상단 바와 다툴 일도 없어진다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local ActionBar = {}
ActionBar.__index = ActionBar

function ActionBar.new(parent: Instance, callbacks: {
	onUndo: () -> (),
	onRedo: () -> (),
	onClear: () -> (),
})
	local self = setmetatable({}, ActionBar)
	self.callbacks = callbacks

	local size = UI.ACTION_BUTTON_SIZE

	local group = Instance.new("Frame")
	group.Name = "ActionBar"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromOffset(size, 0)
	-- 버튼 세 개 높이에 맞춰 알아서 늘어난다.
	group.AutomaticSize = Enum.AutomaticSize.Y
	group.LayoutOrder = 1
	group.Visible = false
	group.Parent = parent
	self.instance = group

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, UI.ACTION_BUTTON_GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = group

	-- 아이콘을 이모지로 쓰는 이유:
	-- ↶ ↷ 같은 화살표 기호는 로블록스 기본 글꼴에 글자가 없어서 빈칸으로 나온다.
	-- 이모지는 별도 글꼴로 그려지므로 어느 기기에서나 보인다.
	--
	-- ↩️ ↪️ 는 갈고리가 붙어 있어 어느 쪽인지 헷갈린다는 얘기가 나왔다.
	-- 방향만 있는 ⬅️ ➡️ 로 바꿨다. "뒤로 / 앞으로" 라는 말과도 그대로 맞는다.
	self.undoButton = UIHelper.iconButton({
		name = "Undo",
		parent = group,
		size = size,
		icon = "⬅️",
		badge = "Z",
		layoutOrder = 1,
	})

	self.redoButton = UIHelper.iconButton({
		name = "Redo",
		parent = group,
		size = size,
		icon = "➡️",
		badge = "Y",
		layoutOrder = 2,
	})

	self.clearButton = UIHelper.iconButton({
		name = "Clear",
		parent = group,
		size = size,
		icon = "🗑",
		layoutOrder = 3,
	})

	self.undoButton.Activated:Connect(callbacks.onUndo)
	self.redoButton.Activated:Connect(callbacks.onRedo)
	self.clearButton.Activated:Connect(callbacks.onClear)

	self:_bindKeys()

	return self
end

-- 되돌릴 게 없으면 버튼을 흐리게 해서 "지금은 눌러도 소용없다" 를 보여준다.
-- 버튼 자체는 살려둔다. 눌러도 캔버스 쪽에서 아무 일도 안 일어나기 때문이다.
function ActionBar:SetHistoryState(canUndo: boolean, canRedo: boolean)
	UIHelper.setDisabled(self.undoButton, not canUndo)
	UIHelper.setDisabled(self.redoButton, not canRedo)
end

function ActionBar:_bindKeys()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- 채팅 입력 중이면 무시. 안 그러면 "z" 를 칠 때마다 그림이 지워진다.
		if gameProcessed then
			return
		end
		if not self.instance.Visible then
			return -- 그릴 수 없는 상태에서는 단축키도 없다
		end
		if input.KeyCode == Enum.KeyCode.Z then
			self.callbacks.onUndo()
		elseif input.KeyCode == Enum.KeyCode.Y then
			self.callbacks.onRedo()
		end
	end)
end

return ActionBar
