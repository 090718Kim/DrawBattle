--!strict
--[[
	DrawChanceBar.lua  —  내가 그릴 차례가 얼마나 가까운가

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	막대와 숫자는 **같은 값**이다. 내 차례가 얼마나 가까운지를 나타낸다.

	  ⚠️ **확률이 아니다.** 처음에는 진짜 확률을 보여줬는데,
	     확률은 몇 명이 다투느냐에 달려 있어서 3명 서버에 막 들어오면 67%,
	     10명 서버면 같은 사람이 20% 로 시작했다. 아무것도 안 했는데
	     누가 들어오면 숫자가 떨어지기도 했다.
	     그러면 "내가 얼마나 기다렸나" 가 아니라 "지금 서버가 붐비나" 를 재게 된다.

	     지금 값은 가중치 진행도라 인원과 상관없다.
	     **새로 들어오면 0%, 판마다 오르고, 그리면 다시 0%.**

	  ⚠️ 한때 막대에 진행도, 숫자에 확률을 **따로** 넣은 적이 있다.
	     막대와 % 가 나란히 붙어 있으면 누구든 "막대가 저 % 를 그린 것" 으로 읽는데,
	     2명만 있어서 확률이 100% 인데 막대는 텅 비어 있었다. (README §5.5-11)
	     한 칸에 두 값을 넣으려면 둘이 같은 것을 재야 한다.

	버튼 하나
	  Sit Out   안 그리기 선언. 뽑기에서 빠지되 **막대는 계속 오른다.**
	            쉬었다고 줄 맨 뒤로 밀리면 아무도 이 버튼을 안 누른다.

	  ⚠️ 한때 여기에 "다음 라운드에 내가 그리기"(15 R$) 버튼도 있었다.
	     상점이 생기면서 그쪽으로 옮겼다. 로벅스를 쓰는 곳이 두 군데면
	     유저는 "여기서 산 것과 저기서 산 것이 같은 건가" 를 매번 생각해야 한다.
	     돈 쓰는 자리는 한 곳으로 모은다.

	왜 가운데 아래인가
	  처음에는 왼쪽 아래에 뒀는데 **모바일·태블릿에서 이동 조종기와 겹쳤다.**
	  StatsBar 와 달리 이 줄에는 누를 수 있는 버튼이 둘 있어서,
	  겹치면 조종기를 만지려다 Sit out 을 누르게 된다. 그냥 가려지는 것과 다르다.

	  모바일은 왼쪽 아래에 조종기, 오른쪽 아래에 점프 버튼이 뜬다.
	  아래쪽에서 비어 있는 곳은 가운데뿐이다.

	  가운데 아래에는 관전 줄이 올 수 있다. 그때는 **그 위로 올라간다.**
	  자리를 짐작하지 않고 관전 줄이 실제로 그려진 위치를 재서 그 위에 놓는다.
	  (README §5.5-4 — 내가 만들지 않은 것은 재서 쓴다)

	**이 파일은 아무것도 결정하지 않는다. 받아서 그리기만 한다.** (README §5.5-1)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local DrawChanceBar = {}
DrawChanceBar.__index = DrawChanceBar

local PADDING = 10
local ROW_GAP = 6

function DrawChanceBar.new(parent: Instance, callbacks: {
	onToggleSitOut: () -> (),
})
	local self = setmetatable({}, DrawChanceBar)
	self.callbacks = callbacks
	self.sittingOut = false

	local bar = UIHelper.panel("DrawChanceBar", parent)
	-- 실제 세로 자리는 DrawBattleUI:_placeChanceBar 가 정한다.
	-- 관전 줄이 펼쳐지면 그 위로 올라가야 하기 때문이다.
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -UI.CHANCE_BAR_MARGIN)
	bar.Size = UDim2.fromOffset(UI.CHANCE_BAR_WIDTH, 0)
	-- 높이는 내용에 맡긴다. 글자 크기를 바꿔도 아래가 잘리지 않는다.
	bar.AutomaticSize = Enum.AutomaticSize.Y
	-- 버튼이 들어 있다. 여기를 누른 것이 밑의 캔버스에 그려지면 안 된다. (§3.8)
	bar.Active = true
	bar.ZIndex = 10
	bar.Visible = false
	self.instance = bar

	UIHelper.padding(bar, PADDING)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.Parent = bar

	self:_buildHeader(bar)
	self:_buildTrack(bar)
	self:_buildButtons(bar)

	self:Update(nil)

	return self
end

-- 제목과 확률 숫자를 한 줄에 놓는다.
function DrawChanceBar:_buildHeader(parent: Instance)
	local row = Instance.new("Frame")
	row.Name = "Header"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, UI.CHANCE_BAR_TEXT_SIZE + 4)
	row.LayoutOrder = 1
	row.ZIndex = 11
	row.Parent = parent

	-- "Likely to draw" 가 아닌 이유:
	-- 이 숫자는 확률이 아니라 **우선순위**다. 100% 여도 반드시 그리는 것은 아니다.
	-- (가중치 상한에 닿았다는 뜻이고, 남도 높으면 밀릴 수 있다)
	-- 확률처럼 읽히는 이름 옆에 확률 아닌 % 를 두면 화면이 거짓말을 한다. (§5.5-11)
	local title = UIHelper.label("Turn priority", row)
	title.Name = "Title"
	self.titleLabel = title
	-- 제목이 길어서 자리를 넉넉히 준다. 좁으면 "Likely to dr..." 로 잘린다.
	title.Size = UDim2.new(0.68, 0, 1, 0)
	title.TextSize = UI.CHANCE_BAR_TEXT_SIZE
	title.TextColor3 = UI.MUTED_TEXT_COLOR
	title.ZIndex = 12

	local percent = UIHelper.label("0%", row)
	percent.Name = "Percent"
	percent.AnchorPoint = Vector2.new(1, 0)
	percent.Position = UDim2.fromScale(1, 0)
	percent.Size = UDim2.new(0.32, 0, 1, 0)
	percent.TextXAlignment = Enum.TextXAlignment.Right
	percent.TextSize = UI.CHANCE_BAR_TEXT_SIZE
	percent.Font = Enum.Font.GothamBold
	percent.ZIndex = 12
	self.percentLabel = percent
end

-- 막대. 회색 홈 위에 파란 칸이 자란다.
function DrawChanceBar:_buildTrack(parent: Instance)
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, UI.CHANCE_BAR_TRACK_HEIGHT)
	track.BackgroundColor3 = UI.HEADER_COLOR
	track.BorderSizePixel = 0
	track.LayoutOrder = 2
	track.ZIndex = 11
	track.Parent = parent
	UIHelper.corner(track, UI.CHANCE_BAR_TRACK_HEIGHT // 2)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = UI.ACCENT_COLOR
	fill.BorderSizePixel = 0
	fill.ZIndex = 12
	fill.Parent = track
	UIHelper.corner(fill, UI.CHANCE_BAR_TRACK_HEIGHT // 2)
	self.fill = fill
end

function DrawChanceBar:_buildButtons(parent: Instance)
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, UI.CHANCE_BAR_BUTTON_HEIGHT)
	row.LayoutOrder = 3
	row.ZIndex = 11
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.Parent = row

	self.sitOutButton = self:_button(row, "SitOut", 1, 1)
	self.sitOutButton.Activated:Connect(function()
		-- 흐리게 만드는 것만으로는 클릭이 안 막힌다. (UIHelper.setDisabled 참고)
		-- 서버도 똑같이 거절하지만, 화면에서 먼저 막아야 눌렀는데 아무 일도 없는 순간이 안 생긴다.
		if self.sitOutButton:GetAttribute("Disabled") then
			return
		end
		self.callbacks.onToggleSitOut()
	end)
end

function DrawChanceBar:_button(parent: Instance, name: string, order: number, width: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	-- 가로는 비율로, 세로는 고정. 줄 폭이 바뀌어도 같이 늘어난다.
	button.Size = UDim2.new(width, 0, 1, 0)
	button.BackgroundColor3 = UI.PANEL_COLOR
	button.BackgroundTransparency = UI.PANEL_TRANSPARENCY
	button.BorderSizePixel = 0
	button.Text = ""
	button.TextColor3 = UI.TEXT_COLOR
	button.Font = Enum.Font.GothamMedium
	button.TextSize = UI.CHANCE_BAR_TEXT_SIZE - 2
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.LayoutOrder = order
	button.ZIndex = 12
	button.Parent = parent
	UIHelper.corner(button, 8)
	UIHelper.stroke(button)
	return button
end

-- info 는 서버가 보낸 내 몫이다. 없으면(아직 안 왔으면) 0 으로 둔다.
--   info.progress  차례 진행도 (0~1). 막대와 숫자 **둘 다** 이 값을 쓴다.
--   info.optedOut  안 그리기를 선언했는가
--   info.hasDrawNext "다음 판 그리기" 예약을 들고 있는가
function DrawChanceBar:Update(info: any)
	local progress = if info then info.progress or 0 else 0
	local sittingOut = if info then info.optedOut == true else false
	self.sittingOut = sittingOut
	-- 예약이 있으면 쉬기를 못 누른다. (확정 2026-10-27)
	-- 쉬는 중에 "돌아오기" 는 언제나 된다. 잠그는 것은 **쉬러 가는 쪽만**이다.
	-- 그래야 어떤 이유로든 둘이 겹쳐도 갇히지 않는다.
	local locked = info ~= nil and info.hasDrawNext == true and not sittingOut

	-- 막대와 숫자는 **같은 값**이어야 한다. 다르면 화면이 자기 모순을 일으킨다.
	self.fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)

	-- ⚠️ 쉬는 중에도 숫자와 막대를 그대로 보여준다.
	--    예전에는 숫자 자리에 "Sitting out" 을 넣고 막대를 비웠는데,
	--    그러면 그동안 쌓인 것이 **사라진 것처럼** 보인다.
	--    실제로는 쉬는 동안에도 가중치가 계속 올라서 값은 오르고 있다.
	--    상태는 제목 줄이 알려주고, 숫자와 막대는 늘 진행도를 보여준다.
	self.percentLabel.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))
	self.titleLabel.Text = if sittingOut then "Sitting out" else "Turn priority"

	-- 쉬는 중이라는 것은 색으로 알린다.
	-- 막대를 비우는 대신 흐리게 두면 "멈춰 있지만 남아 있다" 로 읽힌다.
	self.fill.BackgroundColor3 = if sittingOut then UI.MUTED_TEXT_COLOR else UI.ACCENT_COLOR
	self.titleLabel.TextColor3 = if sittingOut then UI.ACCENT_COLOR else UI.MUTED_TEXT_COLOR

	-- 잠겼을 때 "Sit out" 을 흐리게만 두면 왜 안 눌리는지 모른다. 이유를 글자로 보여준다.
	--
	-- ⚠️ 기호(✓)는 안 쓴다. 같은 기호 묶음의 ✕ 가 로블록스 기본 글꼴에 없어서
	--    **빈 네모로 나온 적이 있다.** (ShopPanel 닫기 버튼) 글자로만 쓰면 어느 기기에서나 나온다.
	self.sitOutButton.Text = if locked then "Booked for next round" elseif sittingOut then "Join back" else "Sit out"
	UIHelper.setSelected(self.sitOutButton, sittingOut)
	UIHelper.setDisabled(self.sitOutButton, locked)
	-- setDisabled 는 배경만 흐리게 한다. 이 버튼은 글자가 본체라 글자도 같이 흐린다.
	self.sitOutButton.TextColor3 = if locked then UI.MUTED_TEXT_COLOR else UI.TEXT_COLOR

end

return DrawChanceBar
