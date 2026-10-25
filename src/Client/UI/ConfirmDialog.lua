--!strict
--[[
	ConfirmDialog.lua  —  되돌릴 수 없어 보이는 일을 하기 전에 한 번 묻는 창

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	지금은 전체지우기 하나만 쓰지만, 나중에 "라운드 포기" 같은 것도
	같은 창을 쓰게 될 것이라 처음부터 문구를 받아서 만들도록 해뒀다.

	화면 전체를 덮는 판에 Active = true 를 준다.
	이 판이 클릭을 삼켜서, 경고창이 떠 있는 동안 뒤쪽 캔버스에
	실수로 선이 그려지는 것을 막는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local ConfirmDialog = {}
ConfirmDialog.__index = ConfirmDialog

function ConfirmDialog.new(parent: Instance, opts: {
	name: string,
	title: string,
	message: string,
	confirmText: string,
	cancelText: string,
	onConfirm: () -> (),
	-- 창이 닫힐 때(취소든 실행이든) 불린다. 창을 띄우며 잠가둔 것을 되돌리는 자리다.
	onClose: (() -> ())?,
})
	local self = setmetatable({}, ConfirmDialog)
	self.onConfirm = opts.onConfirm
	self.onClose = opts.onClose

	local overlay = Instance.new("Frame")
	overlay.Name = opts.name
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	-- 다른 UI 보다 확실히 위에 뜨도록 넉넉히 올린다.
	overlay.ZIndex = 50
	-- 클릭을 삼켜서 뒤쪽 캔버스가 반응하지 않게 한다.
	overlay.Active = true
	overlay.Visible = false
	overlay.Parent = parent
	self.instance = overlay

	local box = UIHelper.panel("Box", overlay)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	-- 세로 길이는 문구 길이에 맞춰 알아서 늘어난다.
	box.Size = UDim2.fromOffset(380, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundTransparency = 0
	box.ZIndex = 51
	UIHelper.padding(box, 22)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 14)
	layout.Parent = box

	local title = UIHelper.label(opts.title, box)
	title.Size = UDim2.new(1, 0, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.LayoutOrder = 1
	title.ZIndex = 52

	local message = UIHelper.label(opts.message, box)
	message.Size = UDim2.new(1, 0, 0, 0)
	-- 문구가 길어지면 줄바꿈되고, 그만큼 라벨도 창도 같이 커진다.
	message.AutomaticSize = Enum.AutomaticSize.Y
	message.TextWrapped = true
	message.TextXAlignment = Enum.TextXAlignment.Center
	message.TextColor3 = UI.MUTED_TEXT_COLOR
	message.LayoutOrder = 2
	message.ZIndex = 52

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.Size = UDim2.new(1, 0, 0, 42)
	buttons.BackgroundTransparency = 1
	buttons.LayoutOrder = 3
	buttons.ZIndex = 52
	buttons.Parent = box

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Padding = UDim.new(0, 10)
	buttonLayout.Parent = buttons

	local function makeButton(text: string, order: number, danger: boolean): TextButton
		local button = Instance.new("TextButton")
		button.Name = if danger then "Confirm" else "Cancel"
		-- 둘이 가로를 반씩 나눠 갖는다. 사이 간격 10 을 둘이 나눈 값이 5 다.
		button.Size = UDim2.new(0.5, -5, 1, 0)
		button.BackgroundColor3 = if danger then UI.DANGER_COLOR else UI.PANEL_COLOR
		button.BackgroundTransparency = 0
		button.BorderSizePixel = 0
		button.Text = text
		button.TextColor3 = if danger then Color3.new(1, 1, 1) else UI.TEXT_COLOR
		button.Font = Enum.Font.GothamBold
		button.TextSize = 16
		button.LayoutOrder = order
		button.ZIndex = 53
		button.Parent = buttons
		UIHelper.corner(button, 10)
		UIHelper.stroke(button)
		return button
	end

	-- 취소를 왼쪽, 실행을 오른쪽에 둔다.
	-- 위험한 쪽만 빨갛게 칠해서 눈으로 구분되게 한다.
	local cancelButton = makeButton(opts.cancelText, 1, false)
	local confirmButton = makeButton(opts.confirmText, 2, true)

	cancelButton.Activated:Connect(function()
		self:Hide()
	end)

	confirmButton.Activated:Connect(function()
		self:Hide()
		self.onConfirm()
	end)

	return self
end

function ConfirmDialog:Show()
	self.instance.Visible = true
end

function ConfirmDialog:Hide()
	-- 이미 닫혀 있으면 onClose 를 두 번 부르지 않는다.
	if not self.instance.Visible then
		return
	end
	self.instance.Visible = false
	if self.onClose then
		self.onClose()
	end
end

return ConfirmDialog
