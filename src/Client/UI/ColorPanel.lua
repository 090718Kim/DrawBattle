--!strict
--[[
	ColorPanel.lua  —  왼쪽 색상 패널

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	구성
	  [Color Sets]            제목 줄
	  [Custom] [Palettes]     탭 두 개
	  ─ Custom  : 둥근 색상환 + 밝기 막대 (ColorWheel)
	  ─ Palettes: 자주 쓰는 색 격자
	  ─────────
	  투명도 / 브러시 굵기 / 지우개 굵기 슬라이더

	이 파일은 "무엇을 어디에 놓을지" 만 정한다.
	색상환이 실제로 어떻게 그려지고 어떻게 색을 계산하는지는 ColorWheel 이 갖고 있다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)
local ColorWheel = require(script.Parent.ColorWheel)

local UI = Config.UI

local ColorPanel = {}
ColorPanel.__index = ColorPanel

-- 패널 안쪽 여백. 격자 칸 크기를 계산할 때도 써야 해서 이름을 붙여둔다.
local INNER_PADDING = 14

--------------------------------------------------------------------
-- 만들기
--------------------------------------------------------------------

function ColorPanel.new(parent: Instance, callbacks: {
	onColorChanged: (Color3) -> (),
	onTransparencyChanged: (number) -> (),
	onThicknessChanged: (number) -> (),
	onEraserThicknessChanged: (number) -> (),
})
	local self = setmetatable({}, ColorPanel)
	self.callbacks = callbacks
	self.color = Config.DEFAULT_COLOR

	-- 스크롤되는 판이다.
	--
	-- 예전에는 내용에 맞춰 늘어나게(AutomaticSize) 두고, 화면을 넘치면
	-- 배율을 줄여서 맞췄다. 그런데 배율을 줄이려면 "원래 높이" 를 알아야 하고,
	-- 그걸 AbsoluteSize ÷ 배율 로 역산했다.
	-- AbsoluteSize 는 배율을 바꾼 **다음 프레임**에 갱신되므로 매번 틀린 값이 나왔고,
	-- 그게 다시 크기 변경 신호를 울려서 매 프레임 되먹임이 돌았다. (README §5.5)
	--
	-- 지금은 배율을 건드리지 않고, 화면에 안 들어가면 스크롤한다.
	-- 내용 높이(AbsoluteCanvasSize)는 판의 높이와 무관하게 정해져서 되먹임이 없다.
	local panel = Instance.new("ScrollingFrame")
	panel.Name = "ColorPanel"
	panel.BackgroundColor3 = UI.PANEL_COLOR
	panel.BackgroundTransparency = UI.PANEL_TRANSPARENCY
	panel.BorderSizePixel = 0
	panel.ScrollBarThickness = 4
	panel.ScrollBarImageColor3 = UI.MUTED_TEXT_COLOR
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.CanvasSize = UDim2.new()
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, UI.COLOR_PANEL_MARGIN, 0.5, 0)
	-- 높이는 DrawBattleUI 가 화면에 맞춰 정해준다.
	panel.Size = UDim2.fromOffset(UI.COLOR_PANEL_WIDTH, UI.COLOR_PANEL_HEIGHT)
	panel.Parent = parent
	UIHelper.corner(panel)
	UIHelper.stroke(panel)
	-- 클릭을 삼킨다. 좁은 화면에서 패널이 캔버스 위에 겹쳐 뜨는데,
	-- 이게 없으면 패널을 누른 게 밑의 캔버스에 선으로 그려진다.
	panel.Active = true
	-- 캔버스보다 위에 뜬다.
	panel.ZIndex = 10
	self.instance = panel

	UIHelper.padding(panel, INNER_PADDING)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = panel

	self:_buildHeader(panel)
	self:_buildTabs(panel)
	self:_buildCustomPage(panel)
	self:_buildPalettePage(panel)
	self:_buildDivider(panel)
	self:_buildBrushSliders(panel)

	self:_selectTab("custom")
	self:SetColor(self.color)

	return self
end

function ColorPanel:_buildHeader(parent: Instance)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 34)
	header.BackgroundColor3 = UI.HEADER_COLOR
	header.BorderSizePixel = 0
	header.LayoutOrder = 1
	header.Parent = parent
	UIHelper.corner(header, 8)

	local title = UIHelper.label("Color Sets", header)
	title.Size = UDim2.fromScale(1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
end

function ColorPanel:_buildTabs(parent: Instance)
	local row = Instance.new("Frame")
	row.Name = "Tabs"
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundTransparency = 1
	row.LayoutOrder = 2
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row

	self.tabButtons = {}

	local function makeTab(id: string, text: string, order: number)
		local button = Instance.new("TextButton")
		button.Name = id
		-- 탭이 두 개니까 가로 절반씩. Padding 8 을 둘이 나눠 갖는다.
		button.Size = UDim2.new(0.5, -4, 1, 0)
		button.BackgroundColor3 = UI.PANEL_COLOR
		button.BackgroundTransparency = UI.PANEL_TRANSPARENCY
		button.BorderSizePixel = 0
		button.Text = text
		button.TextColor3 = UI.TEXT_COLOR
		button.Font = Enum.Font.GothamMedium
		button.TextSize = 15
		button.LayoutOrder = order
		button.Parent = row
		UIHelper.corner(button, 8)
		UIHelper.stroke(button)

		button.Activated:Connect(function()
			self:_selectTab(id)
		end)

		self.tabButtons[id] = button
	end

	makeTab("custom", "Custom", 1)
	makeTab("palettes", "Palettes", 2)
end

function ColorPanel:_selectTab(id: string)
	self.activeTab = id
	for tabId, button in self.tabButtons do
		UIHelper.setSelected(button, tabId == id)
	end
	-- UIListLayout 은 Visible = false 인 것을 아예 자리에서 빼준다.
	-- 그래서 페이지를 껐다 켜는 것만으로 패널 높이가 알아서 줄었다 늘었다 한다.
	self.customPage.Visible = (id == "custom")
	self.palettePage.Visible = (id == "palettes")
end

--------------------------------------------------------------------
-- Custom 탭 : HSV 슬라이더
--------------------------------------------------------------------

function ColorPanel:_buildCustomPage(parent: Instance)
	local page = Instance.new("Frame")
	page.Name = "CustomPage"
	page.Size = UDim2.new(1, 0, 0, 0)
	page.AutomaticSize = Enum.AutomaticSize.Y
	page.BackgroundTransparency = 1
	page.LayoutOrder = 3
	page.Parent = parent
	self.customPage = page

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = page

	-- 지금 색이 뭔지 크게 보여주는 띠
	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.Size = UDim2.new(1, 0, 0, 40)
	preview.BackgroundColor3 = self.color
	preview.BorderSizePixel = 0
	preview.LayoutOrder = 1
	preview.Parent = page
	UIHelper.corner(preview, 8)
	UIHelper.stroke(preview)
	self.preview = preview

	self.wheel = ColorWheel.new({
		name = "Wheel",
		parent = page,
		layoutOrder = 2,
		onChanged = function(color)
			-- 사람이 원판을 끌었을 때만 여기로 온다. 그대로 캔버스까지 전달한다.
			self:_applyColor(color, true)
		end,
	})
end

--------------------------------------------------------------------
-- Palettes 탭 : 색 격자
--------------------------------------------------------------------

function ColorPanel:_buildPalettePage(parent: Instance)
	local page = Instance.new("Frame")
	page.Name = "PalettePage"
	page.Size = UDim2.new(1, 0, 0, 0)
	page.AutomaticSize = Enum.AutomaticSize.Y
	page.BackgroundTransparency = 1
	page.LayoutOrder = 4
	page.Visible = false
	page.Parent = parent
	self.palettePage = page

	local columns = Config.PALETTE_COLUMNS
	local gap = 4
	-- 패널 안쪽 폭에서 칸 사이 간격을 뺀 뒤 열 수로 나눈다.
	-- 열 수나 패널 폭을 Config 에서 바꿔도 격자가 알아서 맞는다.
	local innerWidth = UI.COLOR_PANEL_WIDTH - INNER_PADDING * 2
	local cell = math.floor((innerWidth - gap * (columns - 1)) / columns)

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(cell, cell)
	grid.CellPadding = UDim2.fromOffset(gap, gap)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = page

	for index, color in Config.PALETTE do
		local swatch = Instance.new("TextButton")
		swatch.Name = "Color" .. index
		swatch.BackgroundColor3 = color
		swatch.BorderSizePixel = 0
		swatch.Text = ""
		swatch.LayoutOrder = index
		swatch.Parent = page
		UIHelper.corner(swatch, 6)
		UIHelper.stroke(swatch)

		swatch.Activated:Connect(function()
			-- 팔레트로 고른 색도 Custom 탭 슬라이더에 반영되어야 한다.
			-- 그래야 "팔레트에서 빨강 고르고 조금 어둡게" 가 자연스럽게 된다.
			self:SetColor(color)
			self.callbacks.onColorChanged(color)
		end)
	end
end

--------------------------------------------------------------------
-- 굵기 / 투명도
--------------------------------------------------------------------

function ColorPanel:_buildDivider(parent: Instance)
	local line = Instance.new("Frame")
	line.Name = "Divider"
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = UI.PANEL_STROKE_COLOR
	line.BorderSizePixel = 0
	line.LayoutOrder = 5
	line.Parent = parent
end

function ColorPanel:_buildBrushSliders(parent: Instance)
	self.transparencySlider = UIHelper.slider({
		name = "Transparency",
		parent = parent,
		title = "Transparency",
		min = 0, max = 1, value = Config.DEFAULT_TRANSPARENCY,
		layoutOrder = 6,
		swatchColor = self.color,
		onChanged = function(value)
			self.callbacks.onTransparencyChanged(value)
		end,
	})

	self.thicknessSlider = UIHelper.slider({
		name = "Brush",
		parent = parent,
		title = "Brush Size",
		min = Config.MIN_THICKNESS,
		max = Config.MAX_THICKNESS,
		value = Config.DEFAULT_THICKNESS,
		step = 1,
		layoutOrder = 7,
		swatchColor = self.color,
		onChanged = function(value)
			self.callbacks.onThicknessChanged(value)
		end,
	})

	self.eraserSlider = UIHelper.slider({
		name = "Eraser",
		parent = parent,
		title = "Eraser Size",
		min = Config.MIN_ERASER_THICKNESS,
		max = Config.MAX_ERASER_THICKNESS,
		value = Config.DEFAULT_ERASER_THICKNESS,
		step = 1,
		layoutOrder = 8,
		-- 지우개는 종이색으로 칠하는 것이므로 미리보기도 종이색이 맞다.
		swatchColor = Config.CANVAS_BACKGROUND_COLOR,
		onChanged = function(value)
			self.callbacks.onEraserThicknessChanged(value)
		end,
	})
end

--------------------------------------------------------------------
-- 색 반영
--------------------------------------------------------------------

-- notify 가 true 면 캔버스에도 알린다.
-- 슬라이더를 직접 끈 경우에만 true 다. (SetColor 로 들어온 건 이미 반영된 색)
function ColorPanel:_applyColor(color: Color3, notify: boolean)
	self.color = color
	self.preview.BackgroundColor3 = color
	self.transparencySlider:SetSwatch(color)
	self.thicknessSlider:SetSwatch(color)

	if notify then
		self.callbacks.onColorChanged(color)
	end
end

-- 바깥(팔레트 클릭, 스포이드)에서 색이 정해졌을 때 패널 전체를 맞춘다.
function ColorPanel:SetColor(color: Color3)
	-- ColorWheel:SetColor 는 onChanged 를 부르지 않는다. 안 그러면
	-- 원판 → 색 → 원판 으로 되먹임이 돌아버린다.
	self.wheel:SetColor(color)
	self:_applyColor(color, false)
end

return ColorPanel
