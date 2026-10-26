--!strict
--[[
	Toolbar.lua  —  화면 아래쪽 도구 모음

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	버튼 목록은 여기가 아니라 Config.TOOLS 가 갖고 있다.
	도구를 추가하거나 순서를 바꾸고 싶으면 Config 만 고치면 되고,
	이 파일은 "표를 읽어서 버튼으로 만든다" 는 일만 한다.

	숫자 키 1~7 로도 고를 수 있다. 참고 화면의 버튼에 붙은 숫자가 그 뜻이다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local Toolbar = {}
Toolbar.__index = Toolbar

-- 도형 종류별 아이콘. 도형 버튼을 다시 누르면 이 글자가 바뀌어서
-- 지금 어떤 도형인지 버튼만 봐도 알 수 있다.
function Toolbar.new(parent: Instance, callbacks: {
	onToolSelected: (string) -> (),
})
	local self = setmetatable({}, Toolbar)
	self.callbacks = callbacks
	self.buttons = {}
	self.toolById = {}
	self.activeTool = Config.DEFAULT_TOOL

	local count = #Config.TOOLS
	local size = UI.TOOL_BUTTON_SIZE
	local gap = UI.TOOL_BUTTON_GAP
	local pad = 8

	local bar = UIHelper.panel("Toolbar", parent)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -UI.TOOLBAR_BOTTOM_MARGIN)
	-- 버튼 개수에서 폭을 계산한다. Config 에 도구를 하나 더 넣어도 알아서 넓어진다.
	bar.Size = UDim2.fromOffset(
		count * size + (count - 1) * gap + pad * 2,
		size + pad * 2
	)
	-- 툴바를 누른 게 밑의 캔버스에 그려지지 않도록 클릭을 삼킨다.
	bar.Active = true
	bar.ZIndex = 10
	self.instance = bar

	UIHelper.padding(bar, pad)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = bar

	for index, tool in Config.TOOLS do
		self.toolById[tool.id] = tool

		local button = UIHelper.iconButton({
			name = tool.id,
			parent = bar,
			size = size,
			icon = tool.icon,
			iconImage = tool.iconImage,
			badge = tostring(index),
			layoutOrder = index,
		})

		button.Activated:Connect(function()
			self:_handleClick(tool)
		end)

		self.buttons[tool.id] = button
	end

	self:_bindNumberKeys()
	self:SetTool(self.activeTool)

	return self
end

function Toolbar:_handleClick(tool)
	self:SetTool(tool.id)
	self.callbacks.onToolSelected(tool.id)
end

-- 어떤 도구가 켜져 있는지 화면에 표시한다. 실제 도구 변경은 호출한 쪽이 한다.
function Toolbar:SetTool(toolId: string)
	self.activeTool = toolId
	for id, button in self.buttons do
		UIHelper.setSelected(button, id == toolId)
	end
end

function Toolbar:_bindNumberKeys()
	-- 숫자 1 의 KeyCode 값에서 하나씩 더해가면 2, 3, 4... 가 된다.
	-- Enum 을 하나씩 나열하는 것보다 짧고, Config.TOOLS 가 늘어나도 그대로 동작한다.
	local firstKey = Enum.KeyCode.One.Value

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- 채팅창에 글자를 치는 중이면 gameProcessed 가 true 다. 그때는 무시해야
		-- "1" 을 치려다 도구가 바뀌는 일이 없다.
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		-- 도구 줄이 안 보이면 단축키도 없다. ActionBar 의 Z·Y 와 같은 규칙이다.
		-- 예전에는 이 검사가 없어서, 관전 중이든 상대 그림을 보는 중이든
		-- 숫자를 누르면 **안 보이는 곳에서** 도구가 바뀌어 있었다.
		if not self.instance.Visible then
			return
		end

		local index = input.KeyCode.Value - firstKey + 1
		local tool = Config.TOOLS[index]
		if not tool then
			return
		end
		-- 키보드로 눌러도 마우스로 누른 것과 완전히 같게 처리한다.
		self:_handleClick(tool)
	end)
end

return Toolbar
