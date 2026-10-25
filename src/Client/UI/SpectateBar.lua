--!strict
--[[
	SpectateBar.lua  —  누구 그림을 볼지 고르고, 별점을 매기는 줄

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	**이 파일은 아무것도 결정하지 않는다. 받아서 그리기만 한다.**
	  누구를 보고 있는지, 관전이 가능한 단계인지, 별점을 줄 수 있는지는
	  전부 DrawBattleUI 가 정해서 Update 로 넘겨준다.

	  예전에는 여기서도 selected 를 들고 판단까지 했는데, DrawBattleUI 쪽 viewing 과
	  어긋나면서 "버튼은 파랗게 켜져 있는데 그림은 안 뜨는" 상태가 됐다.
	  반대로 그림은 뜨는데 테두리가 안 켜지기도 했다. (README §5.5)

	별을 이모지(⭐)로 그리는 이유
	  ★ ☆ 같은 별 기호는 로블록스 기본 글꼴에 글자가 없어서 빈칸으로 나온다.
	  (되돌리기 화살표에서 이미 한 번 겪었다, README §5.2 함정 참고)
	  빈 별에 해당하는 이모지는 없으므로, 같은 ⭐ 를 흐리게 만들어 빈 별로 쓴다.

	펼쳐진 동안에는 캔버스가 그만큼 위로 비켜준다. (README §5.4)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local SpectateBar = {}
SpectateBar.__index = SpectateBar

local PADDING = 8
local GAP = 8

-- 이 줄이 차지할 높이. **재는 게 아니라 계산한다.**
--
-- AbsoluteSize 로 재면 방금 바뀐 내용이 아직 반영 안 된 값을 읽게 된다.
-- 그래서 Done 버튼이 새로 붙는 순간 한 박자 늦게 반영되고, 그동안 그림과 겹쳤다.
-- 안에 무엇이 들어가는지는 우리가 정하므로 계산으로 정확히 알 수 있다.
function SpectateBar.heightFor(showStars: boolean): number
	local height = UI.SPECTATE_BUTTON_HEIGHT -- 이름 버튼 줄
	if showStars then
		height += GAP + UI.STAR_ROW_HEIGHT -- 별 줄
	end
	return height + PADDING * 2
end

function SpectateBar.new(parent: Instance, callbacks: {
	onSelect: (number) -> (),
	onRate: (number, number) -> (),
})
	local self = setmetatable({}, SpectateBar)
	self.callbacks = callbacks
	self.viewing = nil :: number?
	self.showStars = false
	self.userIds = {} :: { number }
	-- 내가 각 그림에 준 별점. 서버가 되돌려주지 않으므로 여기서 기억한다.
	self.myRatings = {} :: { [number]: number }

	local count = Config.DRAWERS_PER_ROUND
	local bar = UIHelper.panel("SpectateBar", parent)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -UI.SPECTATE_BAR_MARGIN)
	bar.Size = UDim2.fromOffset(
		UI.SPECTATE_BUTTON_WIDTH * count + GAP * (count - 1) + PADDING * 2,
		0
	)
	-- 별 줄이 붙었다 떨어졌다 하므로 높이는 내용에 맡긴다.
	bar.AutomaticSize = Enum.AutomaticSize.Y
	-- 이 줄을 누른 것이 밑의 캔버스에 그려지면 안 된다. (README §3.8)
	bar.Active = true
	bar.ZIndex = 10
	bar.Visible = false
	self.instance = bar

	UIHelper.padding(bar, PADDING)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = bar

	self:_buildDrawerButtons(bar, count)
	self:_buildStars(bar)

	return self
end

function SpectateBar:_buildDrawerButtons(parent: Instance, count: number)
	local row = Instance.new("Frame")
	row.Name = "Drawers"
	row.Size = UDim2.new(1, 0, 0, UI.SPECTATE_BUTTON_HEIGHT)
	row.BackgroundTransparency = 1
	row.LayoutOrder = 1
	row.ZIndex = 11
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = row

	-- 버튼을 미리 만들어두고 이름만 갈아 끼운다.
	self.buttons = {}
	for index = 1, count do
		local button = Instance.new("TextButton")
		button.Name = "Drawer" .. index
		button.Size = UDim2.fromOffset(UI.SPECTATE_BUTTON_WIDTH, UI.SPECTATE_BUTTON_HEIGHT)
		button.BackgroundColor3 = UI.PANEL_COLOR
		button.BackgroundTransparency = UI.PANEL_TRANSPARENCY
		button.BorderSizePixel = 0
		button.Text = ""
		button.TextColor3 = UI.TEXT_COLOR
		button.Font = Enum.Font.GothamMedium
		button.TextSize = 15
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.LayoutOrder = index
		button.ZIndex = 12
		button.Parent = row
		UIHelper.corner(button, 10)
		UIHelper.stroke(button)

		button.Activated:Connect(function()
			local userId = self.userIds[index]
			if userId then
				-- 이름을 누르면 언제나 그 사람을 본다.
				-- 관전을 끄는 것은 눈 버튼 하나로만 한다.
				self.callbacks.onSelect(userId)
			end
		end)

		self.buttons[index] = button
	end
end

function SpectateBar:_buildStars(parent: Instance)
	local row = Instance.new("Frame")
	row.Name = "Stars"
	row.Size = UDim2.new(1, 0, 0, UI.STAR_ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.LayoutOrder = 2
	row.Visible = false
	row.ZIndex = 11
	row.Parent = parent
	self.starRow = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row

	self.stars = {}
	for value = Config.MIN_STARS, Config.MAX_STARS do
		local star = Instance.new("TextButton")
		star.Name = "Star" .. value
		star.Size = UDim2.fromOffset(UI.STAR_SIZE, UI.STAR_SIZE)
		star.BackgroundTransparency = 1
		star.Text = "⭐"
		star.TextSize = math.floor(UI.STAR_SIZE * 0.8)
		star.LayoutOrder = value
		star.ZIndex = 12
		star.Parent = row

		star.Activated:Connect(function()
			local target = self.viewing
			if not target or not self.showStars then
				return
			end
			-- 화면부터 바꾸고 서버에 알린다. 서버가 되돌려주지 않으므로
			-- 여기서 기억한 값이 곧 화면에 보이는 값이다.
			self.myRatings[target] = value
			self:_paint()
			self.callbacks.onRate(target, value)
		end)

		self.stars[value] = star
	end
end


function SpectateBar:_paint()
	for index, button in self.buttons do
		local id = self.userIds[index]
		UIHelper.setSelected(button, id ~= nil and id == self.viewing)
	end

	local given = if self.viewing then self.myRatings[self.viewing] else nil
	for value, star in self.stars do
		-- 빈 별에 해당하는 이모지가 없어서, 같은 별을 흐리게 만들어 쓴다.
		star.TextTransparency = if given and value <= given then 0 else 0.75
	end
end

-- 화면을 맞춘다. 판단은 전부 DrawBattleUI 가 해서 넘겨준다.
--
-- ⚠️ viewing 이 바뀔 때마다 반드시 다시 불러야 한다.
--    서버 상태가 올 때만 부르면 파란 테두리가 한 박자 늦는다.
function SpectateBar:Update(state, viewing: number?, showStars: boolean)
	self.userIds = state.drawers
	self.viewing = viewing
	self.showStars = showStars

	for index, button in self.buttons do
		local userId = state.drawers[index]
		button.Visible = userId ~= nil
		if userId then
			button.Text = state.drawerNames[index] or ("Player " .. index)
		end
	end

	self.starRow.Visible = showStars

	-- 새 라운드가 시작되면 지난 라운드에 준 별점은 잊는다.
	if state.phase == Config.PHASE.DRAWING then
		self.myRatings = {}
	end

	self:_paint()
end

return SpectateBar
