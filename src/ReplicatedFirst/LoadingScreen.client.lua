--!strict
--[[
	LoadingScreen.client.lua  —  게임에 들어올 때 뜨는 로딩 화면 (5c)

	배치 위치: ReplicatedFirst 안의 LocalScript. (Rojo: src/ReplicatedFirst)

	화면 구성 (확정 2026-10-28 개발자 결정)
	  제목        "Drawing Battle" — 대시보드에 등록된 게임 이름과 같게
	  배경        모눈종이 (흰 바탕 + 옅은 격자)
	  넣은 것     진행 막대 / 연필이 선을 긋는 애니메이션 / Skip 버튼
	  사라질 때   게임을 다 받고 내 캐릭터가 맵에 나타나면. 점수·티켓까지는 안 기다린다

	왜 ReplicatedFirst 인가
	  로블록스는 게임을 보낼 때 ReplicatedFirst 를 **가장 먼저** 보내고 곧바로 실행한다.
	  다른 곳(StarterPlayerScripts 등)의 스크립트는 게임을 다 받은 뒤에야 돈다.
	  거기에 로딩 화면을 만들면 **로딩이 끝난 다음에** 로딩 화면이 뜨는 셈이다.

	왜 Config 를 안 쓰고 값을 여기 직접 적나
	  Config 는 ReplicatedStorage 에 있는데, 이 스크립트가 도는 순간에는 아직 안 왔을 수 있다.
	  기다리면 그동안 화면이 텅 빈다. 로딩 화면은 **남을 기다리지 않고 혼자** 떠야 한다.
	  그래서 색은 Config.UI 와 같은 값을 여기 따로 적었다. 게임 색을 바꾸면 여기도 같이 바꿀 것.
	  (§5.5-3 "두 곳에 따로 적으면 어긋난다" 를 알고 고른 예외다. 몇 개 안 되고, 어긋나도 색만 다르다)

	갇히지 않게
	  무엇이 안 끝나도 MAX_SECONDS 가 지나면 무조건 사라진다.
	  로딩 화면이 안 걷히면 플레이어는 게임이 고장 난 줄 알고 나간다. 되돌릴 방법도 없다.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

--------------------------------------------------------------------
-- 설정
--------------------------------------------------------------------

local TITLE = "Drawing Battle"

-- 시간 (초)
local MIN_SECONDS = 2 -- 너무 빨리 번쩍 사라지면 무엇이 지나갔는지도 모른다
local MAX_SECONDS = 20 -- 이보다 오래 걸리면 기다리지 않고 걷는다. 갇히지 않게
local SKIP_AFTER_SECONDS = 3 -- 처음부터 Skip 이 있으면 화면을 보기도 전에 누른다

-- 스튜디오에서 디자인을 보려고 일부러 오래 띄워두는 시간.
-- 스튜디오는 게임을 순식간에 받아서, 이게 없으면 2초 만에 사라져 Skip 버튼도 못 본다.
-- ⚠️ **게시한 게임에는 절대 적용되지 않는다.** 아래에서 RunService:IsStudio() 로 막는다.
--    디자인 확인이 끝나면 0 으로 돌린다. 깜빡 잊어도 실제 플레이어는 영향이 없다.
--    (Skip 을 누르면 스튜디오에서도 바로 걷힌다)
--    2026-10-28 디자인 확인 끝(개발자 테스트) → 0. 디자인을 다시 손볼 때 8 정도로 올려서 본다.
local STUDIO_PREVIEW_SECONDS = 0

-- 색. 전부 Config.UI 와 같은 값이다. (맨 위 설명 참고)
local PAPER_COLOR = Color3.fromRGB(252, 252, 254) -- UI.PANEL_COLOR
local TEXT_COLOR = Color3.fromRGB(46, 48, 58) -- UI.TEXT_COLOR
local MUTED_TEXT_COLOR = Color3.fromRGB(140, 143, 155) -- UI.MUTED_TEXT_COLOR
local TRACK_COLOR = Color3.fromRGB(238, 239, 245) -- UI.HEADER_COLOR
local STROKE_COLOR = Color3.fromRGB(214, 216, 226) -- UI.PANEL_STROKE_COLOR
local ACCENT_COLOR = Color3.fromRGB(56, 174, 226) -- UI.ACCENT_COLOR
-- 연필이 한 줄을 다 그을 때마다 색을 바꾼다. 게임 버튼 세 가지 색이다.
local LINE_COLORS = {
	ACCENT_COLOR, -- 팔레트 버튼 (UI.ACCENT_COLOR)
	Color3.fromRGB(150, 90, 230), -- 엿보기 (UI.PEEK_COLOR)
	Color3.fromRGB(245, 176, 65), -- 상점 (UI.SHOP_BUTTON_COLOR)
}

-- 모눈종이. 다섯 칸마다 굵은 선이 오는 진짜 모눈종이처럼 진한 선을 섞는다.
local GRID_SPACING = 36
local GRID_COLOR = Color3.fromRGB(222, 231, 244)
local GRID_MAJOR_COLOR = Color3.fromRGB(196, 212, 234)
local GRID_MAJOR_EVERY = 5

-- 화면 크기에 맞춰 줄이는 기준. UI/Layout.lua 와 같은 숫자다.
-- (Layout 은 StarterPlayerScripts 에 있어서 여기서는 못 불러온다)
local REFERENCE_WIDTH = 1280
local REFERENCE_HEIGHT = 720
local MIN_UI_SCALE = 0.45

-- 가운데 묶음의 크기 (배율을 곱하기 전)
local CONTENT_WIDTH = 620
local CONTENT_HEIGHT = 250
local SKETCH_TOP = 96
local SKETCH_WIDTH = 460
local SKETCH_HEIGHT = 90
local BAR_TOP = 200
local BAR_WIDTH = 420
local BAR_HEIGHT = 12

-- 연필 애니메이션
local DRAW_SECONDS = 2.4 -- 한 줄을 긋는 데 걸리는 시간
local PAUSE_SECONDS = 0.5 -- 다 긋고 잠깐 멈춰서 보여주는 시간
local DOT_SIZE = 7
-- 필기체처럼 위쪽에 고리가 생기는 선(트로코이드).
-- LOOP_TIGHTNESS 가 1 보다 크면 연필이 잠깐 뒤로 돌아가면서 고리가 생긴다.
local LOOPS = 4
local LOOP_TIGHTNESS = 1.6
local THETA_STEP = 0.12 -- 점 사이 간격. 작을수록 선이 촘촘하다

--------------------------------------------------------------------
-- 화면 만들기
--------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreen"
-- 화면 맨 위 로블록스 줄 밑까지 전부 덮는다. 틈으로 아직 덜 받은 맵이 보이면 안 된다.
screenGui.IgnoreGuiInset = true
screenGui.ScreenInsets = Enum.ScreenInsets.None
-- ⚠️ 반드시 false. true 면 캐릭터가 나타나는 순간 로블록스가 이 화면을 지운다.
--    그런데 "캐릭터가 나타났다" 가 바로 이 화면이 기다리는 신호다.
--    기다리던 순간에 저절로 사라지면 진행 막대와 연출이 중간에 끊긴다.
screenGui.ResetOnSpawn = false
-- 게임 화면(DrawBattleGui)보다 위에 뜬다. 그 밑에서 게임 화면이 미리 만들어진다.
screenGui.DisplayOrder = 100
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- 종이 한 장. 사라질 때는 이 종이가 위로 걷힌다.
local paper = Instance.new("Frame")
paper.Name = "Paper"
paper.Size = UDim2.fromScale(1, 1)
paper.BackgroundColor3 = PAPER_COLOR
paper.BorderSizePixel = 0
-- 밑에 깔린 게임 화면(상점 버튼 등)이 눌리지 않게 클릭을 여기서 막는다.
paper.Active = true
paper.Parent = screenGui

local grid = Instance.new("Frame")
grid.Name = "Grid"
grid.Size = UDim2.fromScale(1, 1)
grid.BackgroundTransparency = 1
grid.ClipsDescendants = true
grid.Parent = paper

local content = Instance.new("Frame")
content.Name = "Content"
content.AnchorPoint = Vector2.new(0.5, 0.5)
content.Position = UDim2.fromScale(0.5, 0.5)
content.Size = UDim2.fromOffset(CONTENT_WIDTH, CONTENT_HEIGHT)
content.BackgroundTransparency = 1
content.ZIndex = 5
content.Parent = paper
local contentScale = Instance.new("UIScale")
contentScale.Parent = content

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 84)
title.BackgroundTransparency = 1
title.Text = TITLE
title.Font = Enum.Font.GothamBlack
title.TextSize = 64
title.TextColor3 = TEXT_COLOR
title.ZIndex = 6
title.Parent = content

-- 연필이 선을 긋는 자리
local sketch = Instance.new("Frame")
sketch.Name = "Sketch"
sketch.AnchorPoint = Vector2.new(0.5, 0)
sketch.Position = UDim2.new(0.5, 0, 0, SKETCH_TOP)
sketch.Size = UDim2.fromOffset(SKETCH_WIDTH, SKETCH_HEIGHT)
sketch.BackgroundTransparency = 1
sketch.ZIndex = 6
sketch.Parent = content

-- 진행 막대
local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0.5, 0)
track.Position = UDim2.new(0.5, 0, 0, BAR_TOP)
track.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
track.BackgroundColor3 = TRACK_COLOR
track.BorderSizePixel = 0
track.ZIndex = 6
track.Parent = content
local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(1, 0)
trackCorner.Parent = track

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = ACCENT_COLOR
fill.BorderSizePixel = 0
fill.ZIndex = 7
fill.Parent = track
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local status = Instance.new("TextLabel")
status.Name = "Status"
status.Position = UDim2.fromOffset(0, BAR_TOP + BAR_HEIGHT + 10)
status.Size = UDim2.new(1, 0, 0, 26)
status.BackgroundTransparency = 1
status.Text = ""
status.Font = Enum.Font.GothamBold
status.TextSize = 18
status.TextColor3 = MUTED_TEXT_COLOR
status.ZIndex = 6
status.Parent = content

-- Skip 버튼. **아래 가운데**에 둔다.
-- 처음에는 오른쪽 아래로 생각했는데, 모바일은 그 자리에 점프 버튼이 뜬다.
-- 점프 버튼은 로블록스 화면이라 우리 화면보다 위에 그려져서, Skip 을 누르려다 점프가 눌린다.
-- 왼쪽 아래는 이동 조종기 자리라, 아래쪽에서 비어 있는 곳은 가운데뿐이다. (DrawChanceBar 와 같은 이유)
local skip = Instance.new("TextButton")
skip.Name = "Skip"
skip.AnchorPoint = Vector2.new(0.5, 1)
skip.Position = UDim2.new(0.5, 0, 1, -40)
skip.Size = UDim2.fromOffset(140, 46)
skip.BackgroundColor3 = PAPER_COLOR
skip.BorderSizePixel = 0
skip.Text = "Skip"
skip.Font = Enum.Font.GothamBold
skip.TextSize = 18
skip.TextColor3 = TEXT_COLOR
skip.Visible = false
skip.ZIndex = 10
skip.Parent = paper
local skipCorner = Instance.new("UICorner")
skipCorner.CornerRadius = UDim.new(0, 12)
skipCorner.Parent = skip
local skipStroke = Instance.new("UIStroke")
skipStroke.Color = STROKE_COLOR
skipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
skipStroke.Parent = skip
local skipScale = Instance.new("UIScale")
skipScale.Parent = skip

--------------------------------------------------------------------
-- 모눈종이와 배율 (화면 크기가 바뀔 때마다 다시)
--------------------------------------------------------------------

local function currentScale(): number
	local size = paper.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return 1
	end
	local raw = math.min(size.X / REFERENCE_WIDTH, size.Y / REFERENCE_HEIGHT)
	return math.clamp(raw, MIN_UI_SCALE, 1)
end

local function makeGridLine(position: UDim2, size: UDim2, major: boolean)
	local line = Instance.new("Frame")
	line.Position = position
	line.Size = size
	line.BackgroundColor3 = if major then GRID_MAJOR_COLOR else GRID_COLOR
	line.BorderSizePixel = 0
	line.ZIndex = 2
	line.Parent = grid
end

-- 화면 크기에 맞춰 선을 다시 깐다. 폰을 돌리면 화면 크기가 바뀐다.
-- 이미지를 바둑판으로 깔면 Frame 이 덜 들지만, 아직 이미지 에셋이 없다. (UIHelper 의 아이콘과 같은 사정)
-- 1920x1080 에서 선이 80개쯤이라 부담 없는 양이다.
local function layout()
	local size = paper.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local scale = currentScale()
	contentScale.Scale = scale
	skipScale.Scale = scale

	grid:ClearAllChildren()
	local spacing = math.max(18, math.floor(GRID_SPACING * scale))
	local index = 0
	for x = 0, size.X, spacing do
		makeGridLine(UDim2.fromOffset(x, 0), UDim2.new(0, 1, 1, 0), index % GRID_MAJOR_EVERY == 0)
		index += 1
	end
	index = 0
	for y = 0, size.Y, spacing do
		makeGridLine(UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, 1), index % GRID_MAJOR_EVERY == 0)
		index += 1
	end
end

local resizeConnection = paper:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

--------------------------------------------------------------------
-- 연필 애니메이션
--------------------------------------------------------------------

-- 선이 지나갈 점들을 **한 번만** 계산해둔다. 모양은 매번 같고 색만 바뀐다.
-- 점(Frame)도 처음에 다 만들어두고 보였다 숨겼다만 한다.
-- 매번 새로 만들고 지우면, 게임을 받느라 바쁜 기기에 쓸데없는 일을 더 시키게 된다.
local points: { Vector2 } = {}
do
	local raw: { Vector2 } = {}
	local minX, maxX = math.huge, -math.huge
	local thetaMax = LOOPS * 2 * math.pi
	local theta = 0
	while theta <= thetaMax do
		local x = theta - LOOP_TIGHTNESS * math.sin(theta)
		local y = -LOOP_TIGHTNESS * math.cos(theta)
		table.insert(raw, Vector2.new(x, y))
		minX = math.min(minX, x)
		maxX = math.max(maxX, x)
		theta += THETA_STEP
	end
	-- 실제로 나온 폭에 맞춰 늘린다. 미리 짐작한 폭으로 늘리면 끝이 삐져나간다.
	local scaleX = (SKETCH_WIDTH - DOT_SIZE) / (maxX - minX)
	local scaleY = scaleX * 0.85 -- 살짝 납작하게. 고리가 너무 동그라면 글씨보다 스프링처럼 보인다
	for _, p in raw do
		table.insert(points, Vector2.new((p.X - minX) * scaleX + DOT_SIZE / 2, SKETCH_HEIGHT / 2 + p.Y * scaleY))
	end
end

local dots: { Frame } = {}
for _, point in points do
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromOffset(point.X, point.Y)
	dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.ZIndex = 7
	dot.Parent = sketch
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	table.insert(dots, dot)
end

-- 이모지는 별도 글꼴로 그려져서 어느 기기에서나 보인다. (ActionBar 의 아이콘과 같은 이유)
--
-- ⚠️ 로블록스의 ✏️ 는 연필심이 **오른쪽 아래**를 향한다. (2026-10-28 개발자 테스트 스크린샷으로 확인)
--    처음에는 왼쪽 아래라고 짐작하고 그 모서리를 선 끝에 맞췄는데, 그래서 심이 선보다 앞에 나가 있었다.
--    이모지는 글꼴마다 그림이 달라서 짐작하면 안 되고 **눈으로 봐야** 안다. (§5.5-4 와 같은 이야기)
--
-- 시계 방향으로 90도 돌려서 심이 왼쪽 아래로 오게 한다. 실제로 오른손으로 글씨를 쓸 때처럼
-- 연필 윗부분이 진행 방향(오른쪽 위)으로 기운다. 그냥 기준점만 오른쪽 아래로 옮기면 심은 맞지만
-- 연필이 뒤로 누운 채 끌려가는 모양이 된다.
-- 돌리는 축은 기준점(AnchorPoint)이 아니라 **칸의 가운데**다. 그래서 오른쪽 아래였던 심이
-- 돌린 뒤에는 칸의 왼쪽 아래에 오고, 기준점을 거기 두면 심이 선 끝에 닿는다.
-- 숫자(0.12, 0.88)는 스크린샷을 보고 맞춘 눈대중이다.
local pencil = Instance.new("TextLabel")
pencil.Name = "Pencil"
pencil.Rotation = 90
pencil.AnchorPoint = Vector2.new(0.12, 0.88)
pencil.Size = UDim2.fromOffset(44, 44)
pencil.BackgroundTransparency = 1
pencil.Text = "✏️"
pencil.TextSize = 40
pencil.ZIndex = 8
pencil.Parent = sketch

local colorIndex = 0
local shownDots = 0
local lineStartedAt = 0

local function startLine()
	colorIndex = colorIndex % #LINE_COLORS + 1
	local color = LINE_COLORS[colorIndex]
	for _, dot in dots do
		dot.Visible = false
		dot.BackgroundColor3 = color
	end
	shownDots = 0
	lineStartedAt = os.clock()
end

-- 경과 시간으로 그린다. 프레임 수로 세면 느린 기기에서 연필도 같이 느려진다.
local function stepPencil()
	local elapsed = os.clock() - lineStartedAt
	if elapsed >= DRAW_SECONDS + PAUSE_SECONDS then
		startLine()
		elapsed = 0
	end
	local target = math.clamp(math.floor(elapsed / DRAW_SECONDS * #dots), 0, #dots)
	for i = shownDots + 1, target do
		dots[i].Visible = true
	end
	shownDots = math.max(shownDots, target)
	local tip = points[math.max(1, shownDots)]
	pencil.Position = UDim2.fromOffset(tip.X, tip.Y)
end

startLine()
stepPencil()
local animationConnection = RunService.Heartbeat:Connect(stepPencil)

--------------------------------------------------------------------
-- 진행 막대
--------------------------------------------------------------------

-- **단계마다 한 칸씩** 채운다. 부드럽게 차오르는 막대는 만들지 않는다.
-- 로블록스는 "얼마나 남았나" 를 정확히 알려주지 않는다. 그걸 흉내 내서 시간에 맞춰 채우면
-- 다 찼는데 안 끝나거나, 반도 안 찼는데 끝나는 **거짓말하는 막대**가 된다. (§5.5-11 과 같은 이야기)
-- 대신 단계 사이는 트윈으로 미끄러지게 해서 뚝뚝 끊겨 보이지 않게 한다.
local STEP_COUNT = 2

local closed = false

local function setStep(done: number, text: string)
	if closed then
		return
	end
	status.Text = text
	TweenService:Create(
		fill,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(done / STEP_COUNT, 1) }
	):Play()
end

--------------------------------------------------------------------
-- 걷기
--------------------------------------------------------------------

-- 종이가 위로 걷히듯 사라진다. 그다음 통째로 지운다.
-- 하나하나 흐리게 만드는 방법은 격자 선 80개를 다 따로 흐려야 해서 위로 밀어 올리는 쪽이 간단하다.
local function close()
	if closed then
		return
	end
	closed = true
	animationConnection:Disconnect()
	resizeConnection:Disconnect()
	skip.Active = false

	local tween = TweenService:Create(
		paper,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.fromScale(0, -1) }
	)
	tween.Completed:Connect(function()
		screenGui:Destroy()
	end)
	tween:Play()
end

skip.Activated:Connect(close)

--------------------------------------------------------------------
-- 실행
--------------------------------------------------------------------

local startedAt = os.clock()
local minSeconds = MIN_SECONDS
if RunService:IsStudio() then
	minSeconds = math.max(minSeconds, STUDIO_PREVIEW_SECONDS)
end

-- 조건이 참이 되거나, 이미 걷혔거나(Skip), 시간이 다 되면 돌아온다.
-- :Wait() 로 신호를 기다리지 않고 짧게 자꾸 확인한다. 신호는 안 오면 **영영** 안 돌아오기 때문이다.
local function waitUntil(condition: () -> boolean)
	while not closed and not condition() and os.clock() - startedAt < MAX_SECONDS do
		task.wait(0.1)
	end
end

-- ⚠️ 화면을 먼저 붙이고 나서 로블록스 기본 로딩 화면을 치운다.
--    순서가 뒤집히면 그 사이 한순간 아무것도 없는 화면이 보인다.
screenGui.Parent = player:WaitForChild("PlayerGui")
layout()
ReplicatedFirst:RemoveDefaultLoadingScreen()

task.delay(SKIP_AFTER_SECONDS, function()
	if not closed then
		skip.Visible = true
	end
end)

-- 1단계: 게임을 다 받았는가
setStep(0, "Loading game...")
waitUntil(function()
	return game:IsLoaded()
end)

-- 2단계: 내 캐릭터가 맵에 나타났는가.
-- 캐릭터가 섰다는 것은 그 주변 맵이 다 와 있다는 뜻이라, "맵 준비" 의 신호로 쓴다.
setStep(1, "Loading map...")
waitUntil(function()
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
end)

setStep(2, "Ready!")
waitUntil(function()
	return os.clock() - startedAt >= minSeconds
end)
close()
