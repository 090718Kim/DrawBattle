--!strict
--[[
	StatsBar.lua  —  내 승리수와 점수를 화면에 띄운다

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	보여주는 것
	  🏆 이긴 판 수      leaderstats.Wins
	  ⭐ 누적 점수        leaderstats.Score
	  🎟️ 주제 작성권      21분 놀 때마다 하나씩, 쌓인다. **하나도 없으면 이 칸은 안 보인다.**
	                     늘 0 으로 떠 있으면 무슨 뜻인지 모르는 칸이 하나 늘 뿐이다.
	  ⏱️ 이번 접속 시간   이 서버에 들어온 뒤 지난 시간. "45m", "3h 12m" 처럼 분 단위. (2026-10-28 개발자 결정)
	                     총 플레이 시간이 아니다. 다시 들어오면 0 부터 센다. 계산은 DrawBattleUI 가 한다.

	왜 만드는가
	  앞의 두 값은 로블록스 기본 리더보드(leaderstats)에 이미 있다.
	  그런데 모바일에서는 그걸 보려면 메뉴를 열어야 해서 번거롭다.
	  라운드가 끝날 때마다 확인하고 싶은 값인데 매번 메뉴를 여는 건 말이 안 된다.
	  그래서 화면에 늘 붙여둔다. PC·태블릿에서도 똑같이 보인다.

	**이 파일은 아무것도 결정하지 않는다. 받아서 그리기만 한다.**
	  leaderstats 를 읽고 값이 바뀌는 것을 지켜보는 일은 DrawBattleUI 가 한다.
	  (관전 줄에서 상태를 두 곳에 두었다가 어긋난 적이 있다, README §5.5-1)

	왜 오른쪽 아래인가
	  바닥 가운데는 이미 임자가 있다. 그리는 중에는 툴바가,
	  관전·심사 중에는 관전 줄이 거기 있다. 둘 다 화면 아래 가운데다.
	  그래서 남는 곳은 양쪽 아래 구석뿐이다.

	  **처음에는 왼쪽 아래에 뒀는데 색상 패널과 겹쳤다.**
	  색상 패널은 왼쪽에 세로로 길게 서 있고, 슬라이더 세 개까지 붙으면
	  화면 아래까지 내려온다. 모바일과 태블릿에서 실제로 겹쳤다.

	  오른쪽 세로줄(되돌리기·팔레트·눈)은 화면 **가운데**에 붙어 있어서
	  아래 구석까지 내려오지 않는다. 그래서 오른쪽 아래가 비어 있다.

	  눈으로 보고 "괜찮겠지" 하지 않고 계산해 뒀다.
	  세로줄은 최대 374px(되돌리기 3 + 팔레트 + 눈), 이 줄은 46px 이고
	  둘 다 배율(Layout.scale, 최소 0.45)을 같이 탄다.
	  세로줄 아래끝 = 화면높이/2 + 374·s/2,  이 줄 윗끝 = 화면높이 − 16 − 46·s

	     750x332  s=0.46 → 여유 43px
	     852x393  s=0.55 → 여유 53px
	    1000x300  s=0.45 → 여유 29px   ← 가장 빡빡한 경우
	    1280x720  s=1.00 → 여유 111px

	  화면이 납작할수록 빡빡해지지만, 배율이 같이 줄어서 뒤집히지 않는다.

	  모바일에서는 로블록스 점프 버튼이 오른쪽 아래에 뜬다. 겹칠 수 있다.
	  그래도 괜찮은 이유는 **이것이 누르는 물건이 아니기 때문이다.**
	  Active = false 라 입력을 삼키지 않으므로, 겹쳐도 점프는 그대로 된다.
	  게다가 그리는 중에는 조종기가 통째로 꺼져서 점프 버튼도 사라진다.

	숫자를 이모지로 꾸미는 이유
	  🏆 ⭐ 는 별도 글꼴로 그려져서 어느 기기에서나 보인다.
	  글자로 "Wins" "Score" 라고 쓰면 좁은 화면에서 줄이 길어진다.
	  (★ 같은 기호는 로블록스 기본 글꼴에 없어서 빈칸이 된다, README §5.2)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local StatsBar = {}
StatsBar.__index = StatsBar

local PADDING = 12

function StatsBar.new(parent: Instance)
	local self = setmetatable({}, StatsBar)

	local bar = UIHelper.panel("StatsBar", parent)
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Position = UDim2.new(1, -UI.STATS_BAR_MARGIN, 1, -UI.STATS_BAR_MARGIN)
	-- ⚠️ 크기를 고정하지 않는다. 가로세로 모두 내용에 맡긴다.
	--    가로: 점수가 1234 가 되면 줄도 길어져야 한다. 고정하면 네 자리부터 잘린다.
	--    세로: 글자 크기를 바꾸면 높이도 따라와야 한다.
	--          높이를 44 로 박아두고 안쪽 여백을 빼면 20px 가 남는데
	--          아이콘이 22px 라 아래가 잘렸다. 이런 계산은 늘 어긋난다.
	bar.Size = UDim2.fromOffset(0, 0)
	bar.AutomaticSize = Enum.AutomaticSize.XY
	-- ⚠️ 누르는 물건이 아니다. 입력을 삼키면 안 된다. (README §3.8 의 반대쪽)
	--    모바일에서 이 위를 만졌을 때 이동 조종기가 먹통이 되면 안 된다.
	bar.Active = false
	bar.ZIndex = 10
	self.instance = bar

	UIHelper.padding(bar, PADDING)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, UI.STATS_BAR_GAP)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = bar

	self.winsLabel = self:_buildEntry(bar, "Wins", "🏆", 1)
	self.scoreLabel = self:_buildEntry(bar, "Score", "⭐", 2)
	-- 주제 작성권은 **가지고 있을 때만** 보인다.
	-- 늘 0 으로 떠 있으면 무슨 뜻인지 모르는 칸이 하나 늘 뿐이다.
	self.tokenLabel, self.tokenGroup = self:_buildEntry(bar, "Tokens", "🎟️", 3)
	-- 플레이 시간은 맨 끝에 둔다. 네 칸 중 가장 길어서(3h 12m) 가운데 끼면 줄이 들쭉날쭉해 보인다.
	self.playLabel = self:_buildEntry(bar, "Playtime", "⏱️", 4)

	self:Update(0, 0, 0, 0)

	return self
end

-- 아이콘 하나와 숫자 하나를 한 덩어리로 만든다.
-- 숫자만 돌려준다. 나중에 바꿔 쓰는 것은 그것뿐이다.
function StatsBar:_buildEntry(
	parent: Instance,
	name: string,
	icon: string,
	order: number
): (TextLabel, Frame)
	local group = Instance.new("Frame")
	group.Name = name
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromOffset(0, UI.STATS_BAR_TEXT_SIZE + 4)
	group.AutomaticSize = Enum.AutomaticSize.X
	group.LayoutOrder = order
	group.ZIndex = 11
	group.Parent = parent

	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 5)
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Parent = group

	local iconLabel = UIHelper.label(icon, group)
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.fromOffset(UI.STATS_BAR_TEXT_SIZE + 4, UI.STATS_BAR_TEXT_SIZE + 4)
	iconLabel.TextSize = UI.STATS_BAR_TEXT_SIZE
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	iconLabel.LayoutOrder = 1
	iconLabel.ZIndex = 12

	local value = UIHelper.label("0", group)
	value.Name = "Value"
	-- 숫자 자리도 내용에 맡긴다. 1 에서 1234 로 바뀌어도 잘리지 않는다.
	value.Size = UDim2.fromOffset(0, UI.STATS_BAR_TEXT_SIZE + 4)
	value.AutomaticSize = Enum.AutomaticSize.X
	value.TextSize = UI.STATS_BAR_TEXT_SIZE
	value.Font = Enum.Font.GothamBold
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.LayoutOrder = 2
	value.ZIndex = 12

	return value, group
end

-- 초를 "45m" / "3h 12m" 로 바꾼다.
-- 초는 안 보여준다. 1초마다 바뀌는 숫자가 구석에서 계속 움직이면 자꾸 눈이 간다.
local function formatPlaytime(seconds: number): string
	local totalMinutes = math.floor(seconds / 60)
	local hours = totalMinutes // 60
	local minutes = totalMinutes % 60
	if hours <= 0 then
		return string.format("%dm", minutes)
	end
	return string.format("%dh %dm", hours, minutes)
end

-- 보여줄 값을 받아 그대로 찍는다. 판단은 하지 않는다.
function StatsBar:Update(wins: number, score: number, tokens: number, sessionSeconds: number)
	self.winsLabel.Text = tostring(wins)
	self.scoreLabel.Text = tostring(score)
	self.tokenLabel.Text = tostring(tokens)
	self.tokenGroup.Visible = tokens > 0
	self.playLabel.Text = formatPlaytime(sessionSeconds)
end

return StatsBar
