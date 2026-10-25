--!strict
--[[
	UIHelper.lua  —  UI 부품 공장

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	왜 이런 파일이 필요한가:
	  Instance.new("Frame") 를 하면 배경은 회색, 모서리는 각지고, 테두리는 1픽셀 검정이다.
	  버튼 하나 만들 때마다 이걸 6~7줄씩 고쳐야 하는데,
	  그걸 화면 곳곳에 복사해두면 나중에 "패널 색을 바꾸자" 가 대공사가 된다.
	  모양에 관한 결정은 전부 Config.UI 에, 그걸 적용하는 코드는 전부 여기에 둔다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local UI = Config.UI

local UIHelper = {}

--------------------------------------------------------------------
-- 아주 작은 부품
--------------------------------------------------------------------

function UIHelper.corner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or UI.PANEL_CORNER)
	corner.Parent = parent
	return corner
end

function UIHelper.stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or UI.PANEL_STROKE_COLOR
	stroke.Thickness = thickness or 1
	-- Border 로 두면 테두리가 안쪽을 파먹지 않아서 버튼 크기가 그대로 유지된다.
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UIHelper.padding(parent: Instance, amount: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, amount)
	padding.PaddingBottom = UDim.new(0, amount)
	padding.PaddingLeft = UDim.new(0, amount)
	padding.PaddingRight = UDim.new(0, amount)
	padding.Parent = parent
	return padding
end

--------------------------------------------------------------------
-- 패널 / 글자 / 버튼
--------------------------------------------------------------------

-- 둥근 흰 판. 색상 패널, 툴바 배경 등에 쓴다.
function UIHelper.panel(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = UI.PANEL_COLOR
	frame.BackgroundTransparency = UI.PANEL_TRANSPARENCY
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UIHelper.corner(frame)
	UIHelper.stroke(frame)
	return frame
end

function UIHelper.label(text: string, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = UI.TEXT_COLOR
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

-- 정사각형 아이콘 버튼 (도구, 되돌리기 등).
--
-- 아이콘을 ImageLabel 이 아니라 TextButton 의 글자로 넣는 이유:
-- 아직 아이콘 이미지 에셋이 없기 때문이다. Config.TOOLS 의 iconImage 에
-- 에셋 아이디를 채워 넣으면 아래 코드가 자동으로 이미지 쪽을 쓴다.
function UIHelper.iconButton(opts: {
	name: string,
	parent: Instance,
	size: number,
	icon: string,
	iconImage: string?,
	badge: string?,
	layoutOrder: number?,
}): TextButton
	local button = Instance.new("TextButton")
	button.Name = opts.name
	button.Size = UDim2.fromOffset(opts.size, opts.size)
	button.BackgroundColor3 = UI.PANEL_COLOR
	button.BackgroundTransparency = UI.PANEL_TRANSPARENCY
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.LayoutOrder = opts.layoutOrder or 1
	button.Text = ""
	button.Parent = opts.parent
	UIHelper.corner(button)
	UIHelper.stroke(button)

	if opts.iconImage and opts.iconImage ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(0.62, 0.62)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.55)
		image.Image = opts.iconImage
		image.Parent = button
	else
		local icon = Instance.new("TextLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromScale(1, 1)
		icon.Text = opts.icon
		icon.TextColor3 = UI.TEXT_COLOR
		icon.Font = Enum.Font.GothamBold
		icon.TextSize = math.floor(opts.size * 0.42)
		icon.Parent = button
	end

	-- 왼쪽 위 작은 숫자 (단축키 안내)
	if opts.badge then
		local badge = Instance.new("TextLabel")
		badge.Name = "Badge"
		badge.BackgroundTransparency = 1
		badge.Size = UDim2.fromOffset(18, 18)
		badge.Position = UDim2.fromOffset(6, 3)
		badge.Text = opts.badge
		badge.TextColor3 = UI.MUTED_TEXT_COLOR
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = 13
		badge.TextXAlignment = Enum.TextXAlignment.Left
		badge.Parent = button
	end

	return button
end

-- 버튼을 "선택된 상태" 로 보이게 한다. 도구 버튼과 탭이 같이 쓴다.
function UIHelper.setSelected(button: GuiObject, selected: boolean)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if selected then UI.ACCENT_COLOR else UI.PANEL_STROKE_COLOR
		stroke.Thickness = if selected then 3 else 1
	end
end

-- 잠긴 버튼(아직 못 만든 기능)을 흐리게 만든다.
function UIHelper.setDisabled(button: GuiObject, disabled: boolean)
	local target = if disabled then UI.DISABLED_TRANSPARENCY else UI.PANEL_TRANSPARENCY
	button.BackgroundTransparency = target
	local icon = button:FindFirstChild("Icon")
	if icon and icon:IsA("TextLabel") then
		icon.TextTransparency = if disabled then 0.5 else 0
	elseif icon and icon:IsA("ImageLabel") then
		icon.ImageTransparency = if disabled then 0.5 else 0
	end
end

--------------------------------------------------------------------
-- 슬라이더
--------------------------------------------------------------------

export type Slider = {
	instance: Frame,
	SetValue: (self: Slider, value: number) -> (),
	GetValue: (self: Slider) -> number,
	SetSwatch: (self: Slider, color: Color3) -> (),
}

-- 값을 끌어서 고르는 가로 막대.
--
-- 로블록스에는 슬라이더 UI 가 없어서 직접 만들어야 한다.
-- 굵기, 투명도, 색상(H/S/V) 이 전부 같은 모양이라 한 번 만들어 돌려 쓴다.
--
-- opts.onChanged 는 "사람이 끌었을 때" 만 불린다.
-- 코드에서 SetValue 로 바꿀 때는 안 불리는데, 그래야
-- 스포이드로 색을 집어서 슬라이더를 옮길 때 무한 되먹임이 안 생긴다.
function UIHelper.slider(opts: {
	name: string,
	parent: Instance,
	title: string,
	min: number,
	max: number,
	value: number,
	step: number?,
	layoutOrder: number?,
	swatchColor: Color3?,
	onChanged: (number) -> (),
}): Slider
	local ROW_HEIGHT = 50
	local TRACK_HEIGHT = 10
	local SWATCH_WIDTH = 40

	local row = Instance.new("Frame")
	row.Name = opts.name
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.LayoutOrder = opts.layoutOrder or 1
	row.Parent = opts.parent

	local title = UIHelper.label(opts.title, row)
	title.Size = UDim2.new(1, 0, 0, 18)
	title.TextSize = 14
	title.TextColor3 = UI.TEXT_COLOR

	-- 오른쪽 미리보기 사각형 (색/굵기가 어떻게 나오는지 바로 보이라고)
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Size = UDim2.fromOffset(SWATCH_WIDTH, 26)
	swatch.AnchorPoint = Vector2.new(1, 0.5)
	swatch.Position = UDim2.new(1, 0, 0, 34)
	swatch.BackgroundColor3 = opts.swatchColor or Color3.new(0, 0, 0)
	swatch.BorderSizePixel = 0
	swatch.Parent = row
	UIHelper.corner(swatch, 6)
	UIHelper.stroke(swatch)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, -(SWATCH_WIDTH + 12), 0, TRACK_HEIGHT)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 0, 0, 34)
	track.BackgroundColor3 = Color3.fromRGB(225, 227, 235)
	track.BorderSizePixel = 0
	track.Parent = row
	UIHelper.corner(track, TRACK_HEIGHT // 2)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = UI.ACCENT_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track
	UIHelper.corner(fill, TRACK_HEIGHT // 2)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(18, 18)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	UIHelper.corner(knob, 9)
	UIHelper.stroke(knob, Color3.fromRGB(180, 183, 195))

	local currentValue = opts.value

	local function applyVisual()
		local span = opts.max - opts.min
		local alpha = if span > 0 then (currentValue - opts.min) / span else 0
		alpha = math.clamp(alpha, 0, 1)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
	end

	-- 마우스 X 좌표를 값으로 바꾼다.
	local function valueFromX(x: number): number
		local left = track.AbsolutePosition.X
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return currentValue
		end
		local alpha = math.clamp((x - left) / width, 0, 1)
		local value = opts.min + (opts.max - opts.min) * alpha
		if opts.step then
			value = math.floor(value / opts.step + 0.5) * opts.step
		end
		return math.clamp(value, opts.min, opts.max)
	end

	local dragging = false

	local function setFromInput(x: number)
		local value = valueFromX(x)
		if value == currentValue then
			return
		end
		currentValue = value
		applyVisual()
		opts.onChanged(value)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		setFromInput(input.Position.X)
	end)

	-- 손잡이를 잡고 막대 밖으로 끌고 나가도 계속 따라오게 하려면
	-- track 이 아니라 전역 입력을 들어야 한다.
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		setFromInput(input.Position.X)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	applyVisual()

	local slider = {}
	slider.instance = row

	function slider:SetValue(value: number)
		currentValue = math.clamp(value, opts.min, opts.max)
		applyVisual()
	end

	function slider:GetValue(): number
		return currentValue
	end

	function slider:SetSwatch(color: Color3)
		swatch.BackgroundColor3 = color
	end

	return (slider :: any) :: Slider
end

return UIHelper
