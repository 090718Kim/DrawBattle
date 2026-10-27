--!strict
--[[
	DrawBattleUI.lua  —  그림판 화면 조립

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	화면 구조
		ScreenGui
		└ Backdrop            화면 전체. 기본은 완전 투명이라 3D 맵이 그대로 보인다.
		  ├ CanvasRegion      UI 자리를 뺀 나머지 영역
		  │ └ CanvasArea      그 안에 들어가는 가장 큰 정사각형
		  │   ├ Canvas        실제로 그림이 그려지는 ImageLabel (내 그림)
		  │   ├ PeekCanvas    엿보기로 보는 상대 그림 (평소에는 숨어 있다)
		  │   └ PeekToggle    👀 버튼 (그림판 오른쪽 위 모서리 바로 바깥)
		  ├ SideBar           오른쪽 세로줄 (되돌리기 줄 / 🎨 / 👁 / 🛒)
		  ├ ColorPanel        왼쪽 색상 패널
		  ├ TopBar            위쪽 줄 (주제 / 제출 / 남은 시간)
		  ├ Toolbar           아래쪽 도구 모음 (그리는 사람)
		  ├ SpectateBar       아래쪽 관전 목록 + 별점 줄
		  ├ ResultsPanel      결과 단계에 뜨는 라운드 결과
		  ├ PromptReveal      라운드 시작에 주제를 뽑는 연출
		  ├ Toast             짧은 안내 문구
		  └ ClearDialog       전체지우기 전에 한 번 묻는 경고창

	화면에 보이는 글자는 전부 영어로 둔다.
	나중에 여러 언어를 지원할 때 문구를 한곳에 모을 예정이라,
	지금 한국어와 영어를 섞어두면 그때 두 번 손대게 된다.

	이 파일이 하는 일은 부품을 놓고 서로 연결하는 것뿐이다.
	그리는 방법은 DrawingCanvas 가, 부품 모양은 각 UI 모듈이 알아서 한다.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local DrawingCanvas = require(ReplicatedStorage.Shared.DrawingCanvas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local UIHelper = require(script.Parent.UIHelper)
local ColorPanel = require(script.Parent.ColorPanel)
local Toolbar = require(script.Parent.Toolbar)
local ActionBar = require(script.Parent.ActionBar)
local Layout = require(script.Parent.Layout)
local TopBar = require(script.Parent.TopBar)
local SpectateBar = require(script.Parent.SpectateBar)
local StatsBar = require(script.Parent.StatsBar)
local DrawChanceBar = require(script.Parent.DrawChanceBar)
local ShopPanel = require(script.Parent.ShopPanel)
local Toast = require(script.Parent.Toast)
local ResultsPanel = require(script.Parent.ResultsPanel)
local PromptReveal = require(script.Parent.PromptReveal)
local ConfirmDialog = require(script.Parent.ConfirmDialog)

local UI = Config.UI

local DrawBattleUI = {}
DrawBattleUI.__index = DrawBattleUI

function DrawBattleUI.new(playerGui: Instance)
	local self = setmetatable({}, DrawBattleUI)

	self:_buildScreen(playerGui)
	self:_buildCanvas()
	self:_buildSideBar()

	-- 캔버스를 먼저 만들어야 UI 가 연결할 대상이 생긴다.
	self.canvas = DrawingCanvas.new(self.canvasLabel)

	-- 엿보기용 종이. **보기만** 한다.
	-- 만들자마자 꺼둔다. 꺼진 종이는 선도 안 긋고 마우스도 안 숨긴다.
	-- (출력창에 "render mode" 줄이 두 번 찍히는 것은 종이가 두 장이라서다)
	self.peekCanvas = DrawingCanvas.new(self.peekLabel)
	self.peekCanvas:SetEnabled(false)
	-- 상점에서 엿보기를 산 뒤 👀 로 상대 그림을 보고 있는가 (내가 누른 상태)
	self.peekViewing = false

	self:_buildPanels()
	self:_buildPanelToggle()
	self:_buildSpectateToggle()
	self:_buildBlur()
	self:_buildStats()
	self:_buildChance()
	self:_buildShop()
	self:_buildDebug()
	self:_setupControls()
	self:_connectCanvas()
	self:_connectRound()
	self:_bindLayout()
	self:_startReconciler()

	-- 시작 상태를 UI 와 캔버스 양쪽에 똑같이 맞춰둔다.
	self.actionBar:SetHistoryState(false, false)

	return self
end

--------------------------------------------------------------------
-- 뼈대
--------------------------------------------------------------------

function DrawBattleUI:_buildScreen(playerGui: Instance)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DrawBattleGui"
	-- 로블록스 자기 UI(메뉴·채팅·마이크)가 화면 맨 위 왼쪽을 쓴다.
	-- true 로 두면 그 아래로 우리 UI 가 파고들어서 상단 바가 가려진다.
	-- false 면 로블록스가 알아서 그만큼 아래로 밀어준다.
	screenGui.IgnoreGuiInset = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui
	self.screenGui = screenGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = UI.BACKDROP_COLOR
	-- 1 = 완전 투명. 캔버스 바깥으로 맵이 그대로 보인다.
	-- 화면을 어둡게 깔고 싶으면 Config.UI.BACKDROP_TRANSPARENCY 만 바꾸면 된다.
	backdrop.BackgroundTransparency = UI.BACKDROP_TRANSPARENCY
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screenGui
	self.backdrop = backdrop

end

-- 오른쪽 세로줄. 되돌리기·다시하기·전체지우기·팔레트·눈 버튼이 전부 여기 모인다.
--
-- 위쪽에 가로로 눕히면 상단 바와 같은 높이를 두고 다투게 되고,
-- 좁은 화면에서 반드시 겹친다. 실제로 모바일·태블릿에서 겹쳤다.
-- 세로줄은 위쪽 자리를 아예 안 써서, 그림도 그만큼 커지고 위로 올라온다.
function DrawBattleUI:_buildSideBar()
	local bar = Instance.new("Frame")
	bar.Name = "SideBar"
	bar.AnchorPoint = Vector2.new(1, 0.5)
	bar.Position = UDim2.new(1, -UI.SIDE_BAR_MARGIN, 0.5, 0)
	bar.Size = UDim2.fromOffset(UI.PANEL_TOGGLE_SIZE, 0)
	-- 버튼이 몇 개 켜지느냐에 따라 높이가 달라진다.
	bar.AutomaticSize = Enum.AutomaticSize.Y
	bar.BackgroundTransparency = 1
	bar.ZIndex = 11
	bar.Visible = false
	bar.Parent = self.backdrop
	self.sideBar = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, UI.SIDE_BAR_GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = bar

	local scale = Instance.new("UIScale")
	scale.Parent = bar
	self.sideBarScale = scale
end

-- 승리수/점수 줄을 만들고, 리더보드 값이 바뀌는 것을 지켜본다.
--
-- 값의 출처는 서버가 플레이어에 붙이는 leaderstats 다.
-- 로블록스가 알아서 클라이언트로 복제해주므로 따로 통로를 만들 필요가 없다.
--
-- ⚠️ leaderstats 는 **늦게 생긴다.**
--    서버가 저장소에서 값을 읽은 뒤에 붙이는데, 그게 몇 초 걸릴 수 있고
--    저장소가 느리면 더 걸린다. 그래서 지금 없다고 포기하면 안 되고 기다려야 한다.
function DrawBattleUI:_buildStats()
	self.statsBar = StatsBar.new(self.backdrop)
	self.statsBarScale = Instance.new("UIScale")
	self.statsBarScale.Parent = self.statsBar.instance

	-- 값은 여기 한 곳에만 둔다. StatsBar 는 받아서 그리기만 한다. (§5.5-1)
	self.stats = { wins = 0, score = 0, tokens = 0, drawNextBooked = false }

	local player = Players.LocalPlayer

	-- 값 하나를 찾아서 지켜본다. 찾는 동안 멈추므로 각자 따로 돈다.
	local function watch(folder: Instance, name: string, key: string)
		task.spawn(function()
			local value = folder:WaitForChild(name, 30)
			if not value or not value:IsA("IntValue") then
				warn("[DrawBattle] leaderstats." .. name .. " 을 찾지 못했다.")
				return
			end
			self.stats[key] = value.Value
			self:_paintStats()
			value:GetPropertyChangedSignal("Value"):Connect(function()
				self.stats[key] = value.Value
				self:_paintStats()
			end)
		end)
	end

	task.spawn(function()
		local folder = player:WaitForChild("leaderstats", 30)
		if not folder then
			-- 저장소가 막혀 있으면 서버가 leaderstats 를 못 붙인다.
			-- 그럴 때는 0 으로 남겨둔다. 화면이 사라지는 것보다 낫다.
			warn("[DrawBattle] leaderstats 가 오지 않았다. 승리수/점수는 0 으로 둔다.")
			return
		end
		watch(folder, "Wins", "wins")
		watch(folder, "Score", "score")
	end)

	-- 주제 작성권 개수는 특성(Attribute)으로 온다.
	--
	-- leaderstats 에 안 넣은 이유: 그건 공개 순위표라 남의 개수까지 보인다.
	-- 특성은 로블록스가 알아서 복제해주므로 통로를 새로 팔 필요가 없다.
	--
	-- ⚠️ 접속 직후에는 값이 **비어 있다.** 서버가 저장소를 읽는 데 1초쯤 걸리기 때문이다.
	--    그러다 "비어 있음 → 1" 로 바뀌는데, 이걸 "티켓을 새로 받았다" 로 착각하면
	--    티켓이 있는 사람이 들어올 때마다 "You got +1 ticket!" 이 뜬다.
	--    **처음 도착한 값은 받은 게 아니라 원래 있던 것이다.** 그때는 알리지 않는다.
	local function known(name: string): boolean
		return player:GetAttribute(name) ~= nil
	end

	self.stats.tokens = player:GetAttribute("PromptTokens") or 0
	local tokensLoaded = known("PromptTokens")
	player:GetAttributeChangedSignal("PromptTokens"):Connect(function()
		local before = self.stats.tokens
		self.stats.tokens = player:GetAttribute("PromptTokens") or 0
		self:_paintStats()
		self:_paintShop()

		if not tokensLoaded then
			tokensLoaded = true
			return -- 저장소에서 막 읽어온 값이다. 새로 받은 것이 아니다.
		end

		-- 늘었을 때만 알린다. 쓰거나 줄어든 것은 본인이 한 일이라 알릴 것이 없다.
		--
		-- 20분은 긴 시간이라, 받은 줄 모르고 지나가면 그동안 기다린 것이
		-- 없던 일이 된다. 오른쪽 아래 숫자가 0에서 1로 바뀌는 것만으로는
		-- 아무도 못 알아챈다.
		local gained = self.stats.tokens - before
		if gained > 0 and self.toast then
			self.toast:Show(string.format("You got +%d Write a Theme ticket!", gained))
		end
	end)

	-- "다음 라운드에 내가 그리기" 를 사뒀는가. 이것도 서버가 특성으로 알려준다.
	self.stats.drawNextBooked = player:GetAttribute("DrawNextBooked") == true
	local bookedLoaded = known("DrawNextBooked")
	player:GetAttributeChangedSignal("DrawNextBooked"):Connect(function()
		local before = self.stats.drawNextBooked
		self.stats.drawNextBooked = player:GetAttribute("DrawNextBooked") == true
		self:_paintShop()

		if not bookedLoaded then
			bookedLoaded = true
			return -- 원래 사둔 것이다. 방금 산 게 아니다.
		end
		-- 사고 나서 아무 반응이 없으면 결제가 된 건지 알 수가 없다.
		if self.stats.drawNextBooked and not before and self.toast then
			self.toast:Show("You'll draw next round!")
		end
	end)
end

-- 상점에 넘길 값은 두 곳에서 온다.
--   티켓 수, 내 예약  → 특성(Attribute). 서버가 바꿀 때마다 곧바로 온다.
--   주제 임자, 남의 예약 → 라운드 상태. broadcast 때 온다.
-- 둘 중 하나만 바뀌어도 다시 칠해야 하므로 한 함수로 모아둔다.
function DrawBattleUI:_paintShop()
	if not self.shop then
		return
	end
	local state = self.lastState
	local owner = state and state.nextPromptOwner
	local me = Players.LocalPlayer.UserId

	-- "다음 판 그리기" 버튼의 상태. 라운드당 **DRAW_NEXT_SEATS 명까지**다. (§3.2)
	--   mine     — 내가 사뒀다. 또 살 필요가 없다
	--   soldout  — 남이 이미 샀다. 이번엔 못 산다
	--   available — 살 수 있다
	--
	-- 내 것은 특성으로, 남의 것은 라운드 상태(drawInfo 의 booked)로 안다.
	-- 내 것을 특성으로 보는 이유: 두 사람이 거의 동시에 사면 서버는 한 명만
	-- 다음 판에 넣고 나머지는 그다음 판으로 미룬다. 미뤄진 사람의 drawInfo 에는
	-- booked 가 안 찍히지만, 돈은 냈으니 "품절" 이 아니라 "예약됨" 으로 보여야 한다.
	--
	-- 품절은 **남이 산 자리가 DRAW_NEXT_SEATS 개를 채웠을 때**다.
	-- 서버가 받는 수와 같은 숫자를 봐야 화면이 거짓말을 안 한다.
	local drawNext = "available"
	if self.stats.drawNextBooked then
		drawNext = "mine"
	elseif state and state.drawInfo then
		local taken = 0
		for key, info in state.drawInfo do
			if key ~= tostring(me) and info.booked then
				taken += 1
			end
		end
		if taken >= Config.DRAW_NEXT_SEATS then
			drawNext = "soldout"
		end
	end

	-- 주제를 이미 누가 정했는지만 넘긴다. **글자는 안 넘어온다.**
	-- 미리 알면 혼자 연습하고 들어올 수 있다. (§3.1)
	-- 한 번 정해지면 아무도 못 고친다. 내가 정했든 남이 정했든 칸은 잠긴다.
	-- mine 은 안내 문구를 가르는 데만 쓴다.
	self.shop:Update(self.stats.tokens, owner ~= nil, owner == me, drawNext)
end

function DrawBattleUI:_paintStats()
	self.statsBar:Update(self.stats.wins, self.stats.score, self.stats.tokens)
end

-- 그릴 차례 게이지. 그리는 동안에는 숨는다.
function DrawBattleUI:_buildChance()
	self.chanceBar = DrawChanceBar.new(self.backdrop, {
		onToggleSitOut = function()
			-- 지금 값의 반대를 보낸다. 실제로 바뀌었는지는 서버가 정해서 되돌려준다.
			Remotes.event(Remotes.SET_OPT_OUT):FireServer(not self.chanceBar.sittingOut)
		end,
	})
	self.chanceBarScale = Instance.new("UIScale")
	self.chanceBarScale.Parent = self.chanceBar.instance
end

-- 상점 창과 그것을 여는 아이콘, 그리고 짧은 알림.
function DrawBattleUI:_buildShop()
	self.toast = Toast.new(self.backdrop)

	self.shop = ShopPanel.new(self.backdrop, {
		onSubmitPrompt = function(text)
			-- 통과 여부는 **서버가 정한다.** 여기서는 보내기만 한다.
			-- 유저가 친 글자라 반드시 걸러야 한다. (§3.1)
			Remotes.event(Remotes.SUBMIT_PROMPT):FireServer(text)
		end,
		onClose = function()
			self.shopOpen = false
			self:_updateToolVisibility()
		end,
	})

	self.shopToggle = UIHelper.iconButton({
		name = "ShopToggle",
		parent = self.sideBar,
		size = UI.SHOP_TOGGLE_SIZE,
		icon = "🛒",
		layoutOrder = 30,
	})
	-- 흰 버튼에 회색 수레만 두면 배경에 묻혀서 못 찾는다.
	-- 색을 칠해 "여기 눌러도 된다" 를 먼저 보이게 한다. (팔레트 버튼과 같은 이유)
	--
	-- 팔레트는 파랑(ACCENT)을 쓰므로 상점은 다른 색이어야 한다.
	-- 같은 색이면 세로줄에 파란 버튼이 둘이라 손이 헷갈린다.
	self.shopToggle.BackgroundColor3 = UI.SHOP_BUTTON_COLOR
	self.shopToggle.BackgroundTransparency = 0
	self.shopToggle.Visible = false
	self.shopToggle.Activated:Connect(function()
		self.shopOpen = not self.shopOpen
		self:_updateToolVisibility()
	end)

	-- 엿보기 버튼. **그리는 동안에만** 뜬다.
	--
	-- 관전자용 눈 버튼(👁)과 아이콘을 달리 뒀다. 둘이 하는 일이 다르다.
	-- 관전자 것은 공짜로 목록을 여닫고, 이건 로벅스를 내고 상대 그림을 연다.
	-- 같은 그림을 쓰면 그리는 사람이 "아까 그 버튼" 인 줄 알고 누른다.
	--
	-- **그림판 오른쪽 위 모서리 바로 바깥**에 붙인다. (확정 2026-10-27 개발자 요청)
	-- 예전에는 오른쪽 세로줄 맨 아래에 있었는데, 넓은 화면에서는 그림판과 멀리 떨어져서
	-- 눈에 잘 안 띄었다. 그리는 사람의 눈은 그림판에 가 있으니 그 옆에 둔다.
	--
	-- 왜 하필 "오른쪽 **위**" 인가 — 다른 자리는 화면에 따라 무언가와 겹친다.
	--   오른쪽 가운데  태블릿(1024x768)에서 그림판과 세로줄 사이가 33px 뿐이라 세로줄과 겹친다.
	--                  세로줄도 화면 세로 가운데에 있어서 높이가 정확히 같다.
	--   상단 바 안     폭이 고정(520)이고 주제·Submit·시간으로 이미 꽉 차 있다.
	--   그림판 아래    펜 줄(툴바)이 있다.
	--   그림판 안      그림을 가린다. 처음부터 "그림판과 겹치지 않게" 가 조건이었다.
	--   오른쪽 위는 세로줄보다 위쪽이라, 폭이 모자란 화면에서도 세로 방향으로 비켜 간다.
	--   (PC·폰 가로·태블릿·폰 세로 네 가지로 계산해서 확인했다)
	--
	-- 그림판 칸(canvasArea)의 **자식**으로 넣는다. 그림판이 트윈으로 움직이고 커져도
	-- 따로 계산하지 않고 그대로 따라온다. 바깥에 두면 같은 트윈을 하나 더 걸어야 하고,
	-- 둘이 한 프레임이라도 어긋나면 버튼이 그림판 위로 올라탄다.
	-- 그림판 칸은 자식을 자르지 않으므로(ClipsDescendants 기본값 false) 바깥에 둬도 보인다.
	-- 그림 입력은 종이(canvasLabel) 안에서 시작된 것만 받으므로 여기를 눌러도 선이 안 그어진다.
	local peekButton = Instance.new("TextButton")
	peekButton.Name = "PeekToggle"
	-- 버튼의 왼쪽 위 모서리를 그림판 오른쪽 위 모서리 옆에 맞춘다.
	-- 틈(offset)과 배율은 화면 크기에 따라 _applyLayout 이 정한다.
	peekButton.AnchorPoint = Vector2.new(0, 0)
	peekButton.Position = UDim2.new(1, UI.CANVAS_GAP, 0, 0)
	peekButton.Size = UDim2.fromOffset(UI.PEEK_BUTTON_WIDTH, UI.PEEK_BUTTON_HEIGHT)
	-- 흰 버튼이면 배경에 묻혀서 있는 줄도 모른다. 돈 내고 쓰는 버튼이라 더더욱 눈에 띄어야 한다.
	peekButton.BackgroundColor3 = UI.PEEK_COLOR
	peekButton.BackgroundTransparency = 0
	peekButton.BorderSizePixel = 0
	peekButton.AutoButtonColor = true
	peekButton.Text = ""
	peekButton.ZIndex = 10
	peekButton.Visible = false
	peekButton.Parent = self.canvasArea
	UIHelper.corner(peekButton)
	-- setSelected 가 이 테두리 색으로 "지금 상대 그림을 보는 중" 을 보여준다.
	UIHelper.stroke(peekButton)
	self.peekButton = peekButton

	-- 이름이 "Icon" 이어야 setDisabled 가 같이 흐리게 만든다. (UIHelper 의 약속)
	local peekIcon = UIHelper.label("👀", peekButton)
	peekIcon.Name = "Icon"
	peekIcon.Position = UDim2.fromOffset(0, 6)
	peekIcon.Size = UDim2.new(1, 0, 0, 58)
	peekIcon.TextXAlignment = Enum.TextXAlignment.Center
	peekIcon.Font = Enum.Font.GothamBold
	peekIcon.TextSize = 31
	peekIcon.ZIndex = 11

	-- 아이콘만 있으면 처음 보는 사람은 무슨 버튼인지 모른다. **누르면 무엇을 하는지** 글자로 적는다.
	--   Peek — 상대 그림을 본다 (사기 전에는 결제창이 뜬다)
	--   Back — 내 그림으로 돌아간다
	-- 글자는 _updateToolVisibility 가 상태에 맞춰 바꾼다.
	local peekCaption = UIHelper.label("Peek", peekButton)
	peekCaption.Name = "Caption"
	peekCaption.AnchorPoint = Vector2.new(0, 1)
	peekCaption.Position = UDim2.new(0, 0, 1, -8)
	peekCaption.Size = UDim2.new(1, 0, 0, 22)
	peekCaption.TextXAlignment = Enum.TextXAlignment.Center
	peekCaption.Font = Enum.Font.GothamBold
	peekCaption.TextSize = 17
	peekCaption.TextColor3 = Color3.new(1, 1, 1)
	peekCaption.ZIndex = 11
	self.peekCaption = peekCaption

	-- 그림판 칸에는 배율이 안 걸려 있다. 다른 버튼들처럼 화면 크기에 맞춰 줄이려면 따로 단다.
	-- 왼쪽 위(AnchorPoint)를 기준으로 줄어들므로 그림판 쪽 모서리는 그대로 붙어 있다.
	local peekScale = Instance.new("UIScale")
	peekScale.Parent = peekButton
	self.peekButtonScale = peekScale

	self.peeking = false
	-- 버튼 하나가 두 가지 일을 한다.
	--   사기 전  — 결제창을 띄운다
	--   산 뒤    — 내 그림 ↔ 상대 그림을 바꿔 보여준다 (라운드 끝까지 몇 번이든)
	--
	-- 산 뒤에 버튼을 숨기면 바꿔 볼 방법이 없다. 그래서 그대로 두고 하는 일만 바꾼다.
	-- 산 건지 아닌지는 **서버가 알려준 값(peeking)** 으로만 판단한다.
	-- 화면이 "샀다" 고 멋대로 정하면 돈을 안 냈는데 열리는 길이 생긴다. (§3.4)
	self.peekButton.Activated:Connect(function()
		if self.peeking then
			self.peekViewing = not self.peekViewing
			self:_refreshView()
			return
		end
		local productId = Config.PRODUCT_IDS.PEEK
		if productId == 0 then
			return -- 아직 상품이 없다
		end
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
	end)

	-- 내가 보낸 것에 대한 대답. 나만 본다.
	-- 통과했을 때의 알림은 서버가 모두에게 따로 보내므로 여기서 또 띄우지 않는다.
	Remotes.event(Remotes.PROMPT_RESULT).OnClientEvent:Connect(function(ok, message)
		self.shop:ShowResult(ok == true, tostring(message))
	end)

	-- 모두가 알아야 하는 일. 서버가 정해서 보낸다.
	Remotes.event(Remotes.TOAST).OnClientEvent:Connect(function(message)
		if typeof(message) == "string" then
			self.toast:Show(message)
		end
	end)
end

function DrawBattleUI:_buildCanvas()
	-- 캔버스를 담는 껍데기. 화면 전체를 덮고, 보이고 숨기는 데만 쓴다.
	local region = Instance.new("Frame")
	region.Name = "CanvasRegion"
	region.Size = UDim2.fromScale(1, 1)
	region.BackgroundTransparency = 1
	region.Parent = self.backdrop
	self.canvasRegion = region

	-- 실제 종이를 담는 정사각형 틀.
	-- 크기와 자리는 _applyCanvasRegion 이 픽셀로 직접 정한다.
	--
	-- 예전에는 UIAspectRatioConstraint 로 "남은 영역 안에 들어가는 가장 큰 정사각형" 을
	-- 잡았는데, 그러면 정사각형이 늘 **영역의 한가운데**에 놓인다.
	-- 왼쪽에만 색상 패널이 있으면 영역 자체가 오른쪽으로 치우쳐서
	-- 그림도 같이 오른쪽으로 밀렸다. (PC 에서 178px 이나 밀려 있었다)
	--
	-- 지금은 **화면 한가운데**를 기준으로 놓고, UI 를 덮을 때만 그만큼 밀어낸다.
	-- 남는 자리가 있으면(대개 가로) 정확히 가운데에 온다.
	local area = Instance.new("Frame")
	area.Name = "CanvasArea"
	area.AnchorPoint = Vector2.new(0.5, 0.5)
	area.BackgroundTransparency = 1
	area.Parent = region
	self.canvasArea = area

	local canvasLabel = Instance.new("ImageLabel")
	canvasLabel.Name = "Canvas"
	canvasLabel.Size = UDim2.fromScale(1, 1)
	canvasLabel.BackgroundColor3 = Config.CANVAS_BACKGROUND_COLOR
	-- 불투명해야 한다. 여기가 비어 있으면 그림의 투명한 부분으로 3D 맵이 비친다.
	canvasLabel.BackgroundTransparency = 0
	canvasLabel.BorderSizePixel = 0
	canvasLabel.Parent = area
	self.canvasLabel = canvasLabel

	-- 종이처럼 보이도록 모서리를 살짝 둥글게. 그림 영역과는 상관없다.
	UIHelper.corner(canvasLabel, 8)

	-- 엿보기용 두 번째 종이. **상대 그림만** 그린다. (§2 캐시템)
	--
	-- 왜 종이를 하나 더 만드나
	--   내 종이 하나로 "내 그림 ↔ 상대 그림" 을 바꿔 보여주려면, 바꿀 때마다
	--   종이를 비우고 다시 그려야 한다. 그런데 비우는 순간 **내 그림이 날아간다.**
	--   서버에서 다시 받아올 수는 있어도, 되돌리기 기록은 내 컴퓨터에만 있어서 못 살린다.
	--   종이를 두 장 겹쳐 두고 **보이는 쪽만 바꾸면** 내 그림은 숨겨질 뿐 그대로 남는다.
	--
	-- 같은 칸(area) 안에 같은 크기로 넣는다. 그래서 자리와 크기는 따로 신경 쓸 필요가 없다.
	-- 캔버스 자리를 정하는 코드가 칸만 옮기면 두 장이 같이 따라온다.
	local peekLabel = Instance.new("ImageLabel")
	peekLabel.Name = "PeekCanvas"
	peekLabel.Size = UDim2.fromScale(1, 1)
	peekLabel.BackgroundColor3 = Config.CANVAS_BACKGROUND_COLOR
	peekLabel.BackgroundTransparency = 0
	peekLabel.BorderSizePixel = 0
	-- 혹시라도 둘이 같이 보이면 상대 그림이 위에 오게 한다. 평소에는 숨겨져 있다.
	peekLabel.ZIndex = canvasLabel.ZIndex + 1
	peekLabel.Visible = false
	peekLabel.Parent = area
	self.peekLabel = peekLabel
	UIHelper.corner(peekLabel, 8)

	-- 상대 그림을 볼 때 종이에 굵은 보라색 테두리를 두른다.
	-- 종이 색이 내 것과 똑같아서, 이게 없으면 지금 누구 그림인지 헷갈린다.
	-- 종이의 자식이라 종이가 숨으면 같이 숨는다. 따로 켜고 끌 필요가 없다.
	local border = Instance.new("UIStroke")
	border.Name = "PeekBorder"
	border.Color = UI.PEEK_COLOR
	border.Thickness = UI.PEEK_BORDER
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = peekLabel

	-- 지금 보는 게 상대 그림이라는 표시. 이게 없으면 내 그림이 사라진 줄 안다.
	-- 돌아가는 방법까지 적는다. 처음 보면 어떻게 돌아가는지 모른다.
	local badge = UIHelper.label("👀 Opponent's drawing  ·  press 👀 to go back", peekLabel)
	badge.Name = "PeekBadge"
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 0, 10)
	badge.Size = UDim2.fromOffset(0, 34)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = UI.PEEK_COLOR
	badge.BackgroundTransparency = 0
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 16
	badge.TextXAlignment = Enum.TextXAlignment.Center
	-- 종이 그림(EditableImage)보다 위에 떠야 한다.
	badge.ZIndex = peekLabel.ZIndex + 5
	UIHelper.corner(badge, 8)
	UIHelper.padding(badge, 8)
end

--------------------------------------------------------------------
-- 화면 크기에 맞추기
--------------------------------------------------------------------

-- 어긋난 상태를 스스로 되돌린다.
--
-- 화면 상태는 "신호가 올 때 갱신" 하는 구조라, 신호를 한 번 놓치거나
-- 갱신 도중 오류가 나면 그대로 굳는다. 굳은 화면은 사용자가 풀 방법이 없다.
-- 1초에 한 번 지금 상태를 처음부터 다시 계산해서, 어긋났으면 조용히 바로잡는다.
--
-- 값을 새로 만드는 게 아니라 이미 있는 값으로 다시 그리는 것뿐이라 비용이 거의 없다.
function DrawBattleUI:_startReconciler()
	-- 캔버스 자리는 **실제로 그려진 UI 를 재서** 정한다. (_measureFreeRect)
	-- 재는 값은 UI 가 바뀐 다음 프레임에야 갱신되므로, 한 번만 맞추면 늘 한 박자 늦다.
	-- 짧은 주기로 다시 맞춰서 따라잡는다. 값이 그대로면 아무것도 하지 않으므로 비용이 없다.
	task.spawn(function()
		while true do
			task.wait(0.25)
			-- 움직이는 중(트윈)에는 건드리지 않는다. 안 그러면 애니메이션이 끊긴다.
			local tweening = self.lastTweenAt ~= nil
				and os.clock() - self.lastTweenAt < Config.PRESENT_TWEEN_SECONDS + 0.1
			if not tweening then
				pcall(function()
					self:_applyCanvasRegion(false)
				end)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			-- 조종기와 흐림은 "바뀔 때만" 건드리도록 값을 기억해둔다.
			-- 되맞춤 때는 그 기억을 지워서 무조건 다시 적용하게 한다.
			self.controlsEnabled = nil
			self.blurTarget = nil
			local ok, err = pcall(function()
				self:_refreshView()
				-- UI 높이가 달라졌을 수 있다(탭 전환 등).
				self:_applyCanvasRegion(false)
				self:_fitColorPanel()
			end)
			if not ok then
				warn("[DrawBattle] Reconcile failed: " .. tostring(err))
			end
		end
	end)
end

-- 화면 구석에 지금 상태를 적어둔다. 버그를 잡을 때만 쓴다.
--
-- 화면이 이상할 때 "무엇이 어긋났는지" 를 스크린샷 한 장으로 알 수 있다.
-- 끄려면 Config.UI.SHOW_DEBUG 를 false 로.
function DrawBattleUI:_buildDebug()
	if not UI.SHOW_DEBUG then
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = "Debug"
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 8, 1, -8)
	label.Size = UDim2.new(1, -16, 0, 46)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Font = Enum.Font.Code
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	-- 모바일에서는 한 줄에 다 안 들어가 잘렸다. 줄바꿈해서 전부 보이게 한다.
	label.TextWrapped = true
	label.Text = ""
	label.ZIndex = 90
	label.Parent = self.backdrop
	self.debugLabel = label
end

function DrawBattleUI:_updateDebug()
	if not self.debugLabel then
		return
	end

	local state = self.lastState
	local viewport = self.backdrop.AbsoluteSize
	self.debugLabel.Text = string.format(
		"build=%s vp=%dx%d s=%.2f mouse=%s | phase=%s canDraw=%s showCanvas=%s viewing=%s canSpec=%s open=%s stars=%s canvas=%dpx res=%s",
		Config.BUILD_TAG,
		viewport.X,
		viewport.Y,
		if self.layout then self.layout.scale else -1,
		if UserInputService.MouseIconEnabled then "on" else "OFF",
		if state then tostring(state.phase) else "nil",
		tostring(self.canDraw == true),
		tostring(self.showCanvas == true),
		tostring(self.viewing),
		tostring(self.canSpectate == true),
		tostring(self.spectateOpen == true),
		tostring(self.showStars == true),
		math.floor(self.canvasArea.AbsoluteSize.X),
		if state and state.results then tostring(#state.results.entries) else "nil"
	)
end

function DrawBattleUI:_bindLayout()
	self:_applyLayout()
	-- 창 크기가 바뀌거나 기기를 가로/세로로 돌리면 다시 계산한다.
	self.backdrop:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_applyLayout()
	end)

	-- UI 자체의 높이가 바뀌어도 다시 계산해야 한다.
	-- 색상 패널은 탭에 따라, 관전 줄은 별 줄이 붙느냐에 따라 높이가 달라진다.
	-- 이걸 안 보면 어림값으로 잡아둔 자리와 실제가 어긋난다.
	-- 내용이 늘거나 줄면(탭 전환) 다시 맞춘다.
	-- AbsoluteSize 가 아니라 **내용 높이**를 본다. 판의 높이를 우리가 정하므로
	-- AbsoluteSize 를 보면 우리가 바꾼 것에 우리가 다시 반응하게 된다.
	self.colorPanel.instance:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
		self:_fitColorPanel()
	end)

end

function DrawBattleUI:_applyLayout()
	local viewport = self.backdrop.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		-- 아직 화면에 한 번도 그려지지 않았다. 그려지면 위의 신호로 다시 불린다.
		return
	end

	local layout = Layout.compute(viewport)
	self.layout = layout

	self:_applyCanvasRegion(false)

	self:_fitColorPanel()
	self.toolbarScale.Scale = layout.scale
	self.sideBarScale.Scale = layout.scale
	self.topBarScale.Scale = layout.scale
	self.spectateBarScale.Scale = layout.scale
	self.statsBarScale.Scale = layout.scale
	self.chanceBarScale.Scale = layout.scale
	-- 👀 는 그림판 칸에 붙어 있어서 자리는 알아서 따라오고, 크기와 틈만 맞추면 된다.
	-- 틈은 그림판과 다른 UI 사이의 틈(layout.right)과 똑같이 둔다.
	self.peekButtonScale.Scale = layout.scale
	self.peekButton.Position = UDim2.new(1, layout.right, 0, 0)
	self:_placeChanceBar()

	self:_updateToolVisibility()
end

-- 캔버스가 놓일 자리를 잡는다.
--
-- 그리는 중에는 왼쪽 색상 패널과 아래 툴바 자리를 비켜서 앉는다.
-- 붓을 놓은 뒤(제출했거나 관전 중)에는 비켜줄 이유가 없으므로
-- 화면 한가운데로 옮겨가며 커진다. 그 이동을 트윈으로 보여준다.

-- 색상 패널을 화면에 들어가게 맞춘다.
--
-- 배율은 건드리지 않는다. 배율로 맞추려면 "원래 높이" 를 알아야 하는데,
-- 그걸 AbsoluteSize 에서 역산하면 한 프레임 늦은 값이라 되먹임이 돈다.
-- 대신 판의 높이만 잘라내고, 넘치는 내용은 스크롤로 넘긴다.
function DrawBattleUI:_fitColorPanel()
	local layout = self.layout
	if not layout then
		return
	end
	local viewport = self.backdrop.AbsoluteSize
	if viewport.Y <= 0 then
		return
	end

	local scale = layout.scale
	self.colorPanelScale.Scale = scale

	local bandTop = layout.top
	local bandBottom = viewport.Y - layout.right
	local available = math.max(0, bandBottom - bandTop)

	-- 내용 높이는 판의 높이와 무관하게 정해진다. 그래서 되먹임이 없다.
	local panel = self.colorPanel.instance
	local content = panel.AbsoluteCanvasSize.Y
	local contentUnits = if scale > 0 and content > 0
		then content / scale
		else UI.COLOR_PANEL_HEIGHT
	local availableUnits = if scale > 0 then available / scale else available

	local height = math.max(140, math.min(contentUnits, availableUnits))
	panel.Size = UDim2.fromOffset(UI.COLOR_PANEL_WIDTH, height)
	panel.Position = UDim2.new(0, UI.COLOR_PANEL_MARGIN, 0, (bandTop + bandBottom) / 2)
end

-- 화면에 실제로 그려진 UI 의 자리를 잰다.
--
-- 지금까지는 여백을 **계산**해서 캔버스를 밀어냈다.
-- 그런데 UI 마다 위치를 잡는 방식이 조금씩 달라서(어떤 값은 배율이 먹고 어떤 값은 안 먹고)
-- 계산과 실제가 계속 어긋났고, 어긋난 만큼 캔버스가 UI 위로 올라앉았다.
-- 어긋남을 하나씩 찾아 고치는 것은 끝이 없다.
--
-- 그래서 계산을 버리고 **실제로 그려진 사각형을 잰다.**
-- 어디에 무엇이 있든, 그것들이 차지하지 않은 틈이 캔버스 자리다.
-- 그릴 차례 게이지를 가운데 아래에 놓는다.
-- 관전 줄이 펼쳐져 있으면 그 위로 올라간다.
--
-- 관전 줄의 높이는 별 줄이 붙었는지에 따라 달라진다.
-- 어림값으로 잡으면 반드시 어긋나므로 **실제로 그려진 자리를 재서** 쓴다. (§5.5-4)
function DrawBattleUI:_placeChanceBar()
	local bar = self.chanceBar.instance
	local viewport = self.backdrop.AbsoluteSize
	local bottom = UI.CHANCE_BAR_MARGIN

	local spectate = self.spectateBar.instance
	if spectate.Visible and spectate.AbsoluteSize.Y > 0 and viewport.Y > 0 then
		local top = (spectate.AbsolutePosition - self.backdrop.AbsolutePosition).Y
		-- 관전 줄 윗변에서 한 칸 더 띄운다.
		bottom = math.max(bottom, viewport.Y - top + UI.CHANCE_BAR_MARGIN)
	end

	bar.Position = UDim2.new(0.5, 0, 1, -bottom)
end

function DrawBattleUI:_measureFreeRect()
	local base = self.backdrop.AbsolutePosition
	local viewport = self.backdrop.AbsoluteSize
	local gap = if self.layout then self.layout.right else 12

	local x0, y0 = 0, 0
	local x1, y1 = viewport.X, viewport.Y

	-- 보이지 않는 것은 자리를 차지하지 않는다.
	--
	-- ⚠️ 단, 엿보기 중에 숨긴 도구는 **자리를 그대로 맡아둔다.** (keepSpot)
	--    안 그러면 👀 를 누를 때마다 도구가 비킨 만큼 캔버스가 커졌다 작아졌다 한다.
	--    두 그림을 번갈아 보며 비교하는 기능인데, 볼 때마다 크기가 달라지면 비교가 안 된다.
	--    게다가 돌아올 때는 되맞춤(1초)이 돌기 전까지 도구가 캔버스를 덮는다.
	--    숨겨도 AbsolutePosition·AbsoluteSize 는 계속 계산되므로 그 값을 그대로 쓴다.
	--    **엿보기 때문에 숨긴 것만** 해당한다. 관전 줄·게이지처럼 원래 안 보이는 것까지
	--    자리를 맡으면, 엿보는 순간 캔버스가 오히려 작아진다.
	--
	--    그래서 "아직 그리는 중(showTools)" 일 때만 맡는다. 제출한 뒤에는 도구가
	--    원래 없으므로 엿보기와 상관없이 숨어 있다. 그때 자리를 맡으면, 제출 뒤 커졌던
	--    그림판이 👀 를 누를 때마다 그리던 때 크기로 줄어든다.
	local peekHidden: { [GuiObject]: boolean } = {}
	if self.peekShown == true and self.showTools == true then
		peekHidden[self.toolbar.instance] = true
		peekHidden[self.colorPanel.instance] = true
	end
	local function box(gui: GuiObject?): (Vector2?, Vector2?)
		if not gui or not (gui.Visible or peekHidden[gui]) then
			return nil, nil
		end
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return nil, nil
		end
		return gui.AbsolutePosition - base, size
	end

	-- 위쪽: 상단 바
	local pos, size = box(self.topBar.instance)
	if pos and size then
		y0 = math.max(y0, pos.Y + size.Y)
	end

	-- 아래쪽: 툴바와 관전 줄, 그리고 승리수/점수 줄.
	-- 승리수/점수 줄은 왼쪽 구석에만 있지만 자리는 똑같이 비켜준다.
	-- "왼쪽 구석이니까 어차피 안 겹치겠지" 로 넘어갔다가 겹친 적이 여러 번 있다.
	-- 실제로는 툴바가 더 높아서 이 줄이 캔버스를 줄이는 경우는 거의 없다.
	for _, gui in
		{ self.toolbar.instance, self.spectateBar.instance, self.statsBar.instance, self.chanceBar.instance }
	do
		pos, size = box(gui)
		if pos then
			y1 = math.min(y1, pos.Y)
		end
	end

	-- 왼쪽: 색상 패널.
	-- 좁은 화면에서는 서랍이라 캔버스를 덮어도 된다. 자리를 비켜주면 그림이 너무 작아진다.
	if not (self.layout and self.layout.compact) then
		pos, size = box(self.colorPanel.instance)
		if pos and size then
			x0 = math.max(x0, pos.X + size.X)
		end
	end

	-- 오른쪽: 세로줄
	--
	-- ⚠️ 엿보는 동안에는 세로줄의 버튼(되돌리기 줄, 🎨)이 전부 숨어서 줄이 **텅 빈다.**
	--    그래도 자리는 맡아둔다. 위의 peekHidden 과 같은 이유다.
	--    (예전에는 👀 가 이 줄에 남아 있어서 저절로 맡아졌다. 그림판 옆으로 옮기면서 따로 챙긴다)
	--    빈 줄은 높이가 0 이라 box 가 버리므로, 왼쪽 끝 위치만 직접 읽는다.
	--    세로줄은 폭이 고정이라 비어 있어도 그 위치는 믿을 수 있다.
	--    맡는 조건은 위의 peekHidden 과 같다(아직 그리는 중일 때만). 같은 이유로 움직이는 규칙이다.
	if self.sideBar.Visible or (self.peekShown == true and self.showTools == true) then
		x1 = math.min(x1, (self.sideBar.AbsolutePosition - base).X)
	end

	return x0 + gap, y0 + gap, x1 - gap, y1 - gap
end

function DrawBattleUI:_applyCanvasRegion(animate: boolean)
	local viewport = self.backdrop.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end

	local x0, y0, x1, y1 = self:_measureFreeRect()
	local size = math.min(x1 - x0, y1 - y0)

	-- 아래쪽 UI 가 자리를 너무 많이 먹었다.
	-- 겹치더라도 종이는 보여야 한다. 안 보이면 고장으로 읽힌다.
	if size < UI.MIN_CANVAS_SIZE then
		y1 = viewport.Y - (if self.layout then self.layout.right else 12)
		size = math.min(x1 - x0, y1 - y0)
	end
	size = math.max(0, size)

	-- 화면 한가운데에 두되, 틈을 벗어나지 않는 선까지만 밀어낸다.
	local centerX = math.clamp(viewport.X / 2, x0 + size / 2, math.max(x0 + size / 2, x1 - size / 2))
	local centerY = math.clamp(viewport.Y / 2, y0 + size / 2, math.max(y0 + size / 2, y1 - size / 2))

	local position = UDim2.fromOffset(centerX, centerY)
	local squareSize = UDim2.fromOffset(size, size)

	if not animate then
		self.canvasArea.Position = position
		self.canvasArea.Size = squareSize
		return
	end

	self.lastTweenAt = os.clock()
	TweenService:Create(
		self.canvasArea,
		TweenInfo.new(Config.PRESENT_TWEEN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = position, Size = squareSize }
	):Play()
end

-- 그림판과 도구를 보여줄지 정한다.
--
-- **캔버스가 보이는 것**과 **그릴 수 있는 것**은 다르다.
--   캔버스: 의자에 앉아 그리는 단계면 보인다. 제출한 뒤에도 내 그림은 계속 보여야 한다.
--   도구  : 실제로 그을 수 있을 때만. 제출했으면 붓은 치운다.
-- 둘을 한 값으로 묶으면 제출하는 순간 내 그림이 사라져버린다.
--
-- 도구는 화면이 좁을 때 색상 패널이 서랍이라는 조건도 함께 본다.
function DrawBattleUI:_updateToolVisibility()
	local compact = self.layout ~= nil and self.layout.compact
	local canDraw = self.canDraw == true
	local ratingPhase = self.lastState ~= nil
		and self.lastState.phase == Config.PHASE.RATING

	self.canvasRegion.Visible = self.showCanvas == true
	-- 두 장 중 하나만 보인다. 내 종이는 숨길 뿐, 비우지 않는다. (_buildCanvas 참고)
	self.canvasLabel.Visible = not self.peekShown
	self.peekLabel.Visible = self.peekShown == true

	-- 1) 무엇이 보이는지 먼저 전부 정한다.
	--    배치 계산이 이 값들을 쓰므로, 순서가 뒤집히면 한 박자 늦게 반영된다.
	-- 도구는 경고창이 떠 있어도 그대로 둔다. 사라지면 화면이 요동친다.
	local showTools = self.showTools == true
	-- 상대 그림을 보는 동안에는 붓·색·되돌리기를 **통째로 치운다.** (확정 2026-10-27)
	-- 이때는 어차피 못 그린다(canDraw). 남겨두면 눌러도 안 되는 버튼이 잔뜩 떠 있는 셈이다.
	-- 단축키도 같이 잠긴다. Z·Y(ActionBar)와 1~5(Toolbar)는 자기 줄이 숨겨져 있으면 무시한다.
	--
	-- ⚠️ showTools 자체는 건드리지 않는다. 그건 "내가 지금 그리는 사람인가" 이고,
	--    👀 버튼과 상점 버튼, 캔버스 배치가 전부 그 값을 본다.
	--    거기에 엿보기를 섞으면 👀 버튼까지 사라져서 **내 그림으로 돌아올 길이 없어진다.**
	local showBrushes = showTools and not self.peekShown
	self.toolbar.instance.Visible = showBrushes
	self.actionBar.instance.Visible = showBrushes
	-- 서랍 여는 버튼은 좁은 화면에서, 그릴 수 있을 때만 쓸모가 있다.
	self.panelToggle.Visible = showBrushes and compact
	self.colorPanel.instance.Visible = showBrushes and ((not compact) or self.panelOpen)

	-- 눈 버튼은 관전할 수 있을 때만. 목록은 그 버튼을 눌렀을 때만.
	--
	-- 심사 중에는 목록이 늘 펼쳐져 있으므로 눈 버튼이 필요 없다.
	-- 그린 사람도 이때는 버튼을 거치지 않고 곧바로 상대 그림을 본다.
	-- 관전을 끄는 유일한 방법이 이 버튼이다.
	-- 어떤 이유로든 관전이 켜진 채 남으면 나올 길이 없어지므로,
	-- 켜져 있는 동안에는 조건과 상관없이 버튼을 남겨둔다.
	self.spectateToggle.Visible = (self.canSpectate == true or self.spectateOpen == true)
		and not ratingPhase
	self.spectateBar.instance.Visible = self.canSpectate == true and self.spectateOpen == true

	self.chanceBar.instance.Visible = self.showChance == true

	-- 상점은 **그리는 동안에는 안 연다.**
	-- 여기서 파는 것은 전부 다음 라운드 물건이고,
	-- 그리는 중에 창을 띄우면 그 사이에 시간만 간다.
	self.shopToggle.Visible = not showTools
	if not self.shopToggle.Visible then
		self.shopOpen = false
	end
	self.shop.instance.Visible = self.shopOpen == true

	-- 엿보기는 반대로 **그리는 단계에만** 쓸 수 있다. 제출한 뒤에도 남는다. (_refreshView 의 canPeek)
	-- 산 뒤에도 버튼은 남는다. 그때부터는 "바꿔 보기" 버튼이다.
	-- 버튼은 그림판 칸 안에 있으므로, 그림판이 숨으면(관전·결과) 이 값과 상관없이 같이 숨는다.
	self.peekButton.Visible = self.canPeek == true
	-- 글자는 **지금 누르면 무엇을 하는지**를 적는다. 상대 그림을 보는 중이면 돌아가는 버튼이다.
	self.peekCaption.Text = if self.peekShown then "Back" else "Peek"
	-- 지금 상대 그림을 보는 중이면 눌린 모양으로 둔다. 어느 쪽을 보는지 헷갈리지 않게.
	UIHelper.setSelected(self.peekButton, self.peekShown == true)
	-- 상품을 아직 안 만들었고 산 적도 없으면 누를 일이 없다.
	UIHelper.setDisabled(self.peekButton, Config.PRODUCT_IDS.PEEK == 0 and not self.peeking)
	-- ⚠️ 캔버스 자리를 재기 **전에** 놓아야 한다.
	--    아래에서 _measureFreeRect 가 이 줄의 위치를 재기 때문에,
	--    순서가 뒤집히면 캔버스가 한 박자 늦게 따라온다.
	self:_placeChanceBar()

	-- 오른쪽 세로줄에 버튼이 하나라도 있으면 캔버스가 그쪽을 비켜줘야 한다.
	-- (👀 는 이제 이 줄이 아니라 그림판 옆에 있다. 엿보는 동안 비는 자리는 _measureFreeRect 가 챙긴다)
	self.sideBarVisible = self.actionBar.instance.Visible
		or self.panelToggle.Visible
		or self.spectateToggle.Visible
		or self.shopToggle.Visible
	self.sideBar.Visible = self.sideBarVisible

	-- 2) 그 결과로 캔버스 자리를 정한다.
	--    배치가 **실제로 바뀌는 순간에만** 움직인다.
	--    상태 신호는 자주 오므로 매번 트윈을 걸면 계속 덜덜거린다.
	local arrangement = table.concat({
		if showTools then "draw" else "view",
		if self.spectateOpen == true then (if self.showStars then "rate" else "spec") else "-",
		if self.sideBarVisible then "side" else "-",
		-- 게이지가 떴다 사라지면 캔버스가 쓸 수 있는 아래쪽 자리가 달라진다.
		-- 여기 안 넣으면 캔버스가 한 박자 늦게(되맞춤이 돌 때) 움직인다.
		if self.showChance == true then "chance" else "-",
		if self.shopOpen == true then "shop" else "-",
	}, "/")
	if arrangement ~= self.arrangement then
		self.arrangement = arrangement
		self:_applyCanvasRegion(true)
	end

	self:_updateBlur()
	self:_updateControls()
	self:_updateCursor()
	self:_updateDebug()
end

-- 마우스 포인터를 지금 상황에 맞게 맞춘다.
--
-- ⚠️ 경고창이 떠 있으면 **무조건** 포인터를 켠다.
--    경고창은 캔버스 위에 뜨지만, 그 뒤의 캔버스는 마우스 움직임을 계속 받는다.
--    그래서 "그릴 자격" 플래그만 보고 판단하면, 그 플래그가 어떤 경로로든
--    참으로 남아 있을 때 경고창 위에서 포인터가 사라진다.
--    경고창의 버튼을 눌러야 하는데 포인터가 없으면 빠져나갈 길이 없다.
function DrawBattleUI:_updateCursor()
	-- 아직 만들어지기 전에 불릴 수 있다. 여기서 오류가 나면
	-- 화면 갱신 전체가 끊기므로 반드시 확인하고 쓴다.
	local dialogOpen = self.submitDialog ~= nil
		and self.clearDialog ~= nil
		and (self.submitDialog.instance.Visible or self.clearDialog.instance.Visible)
	if dialogOpen then
		self.canvas:ShowPointer()
	else
		self.canvas:RefreshCursor()
	end
end

-- 좁은 화면에서 색상 패널을 여닫는 버튼.
-- 참고 화면 왼쪽의 "+" 버튼이 하던 역할이다.
function DrawBattleUI:_buildPanelToggle()
	self.panelOpen = false

	local button = UIHelper.iconButton({
		name = "PanelToggle",
		parent = self.sideBar,
		size = UI.PANEL_TOGGLE_SIZE,
		icon = "🎨",
		layoutOrder = 10,
	})
	-- 강조색을 칠한다. 흰 버튼으로 두면 배경에 묻혀서 못 찾는다.
	button.BackgroundColor3 = UI.ACCENT_COLOR
	button.BackgroundTransparency = 0
	button.Visible = false
	self.panelToggle = button

	button.Activated:Connect(function()
		self.panelOpen = not self.panelOpen
		self:_updateToolVisibility()
	end)
end

-- 관전 목록을 여닫는 눈 모양 버튼.
-- 색상 패널 서랍 버튼과 같은 자리에 놓는다. 둘은 동시에 보일 일이 없다.
-- (팔레트는 그리는 사람에게만, 눈은 관전자에게만 뜬다)
function DrawBattleUI:_buildSpectateToggle()
	self.spectateOpen = false

	local button = UIHelper.iconButton({
		name = "SpectateToggle",
		parent = self.sideBar,
		size = UI.SPECTATE_TOGGLE_SIZE,
		icon = "👁",
		layoutOrder = 11,
	})
	button.BackgroundColor3 = UI.ACCENT_COLOR
	button.BackgroundTransparency = 0
	button.Visible = false
	self.spectateToggle = button

	button.Activated:Connect(function()
		self:_setSpectateOpen(not self.spectateOpen)
	end)
end

function DrawBattleUI:_setSpectateOpen(open: boolean)
	if self.spectateOpen == open then
		return
	end
	-- 볼 수 없는 단계에서는 켜지지 않는다. 켜두면 빈 화면에 갇힌다.
	if open and self.lastState and not self:_canSpectate(self.lastState) then
		self.spectateOpen = false
		return
	end

	self.spectateOpen = open
	if self.lastState then
		self:_syncViewing(self.lastState)
	end
	self:_refreshView()
end

-- 관전 대상을 규칙에 맞게 맞춘다. 규칙은 딱 하나다.
--
--   **목록이 펼쳐져 있고 관전할 수 있으면, 반드시 누군가를 보고 있다.**
--   **그 외에는 아무도 안 본다.**
--
-- 이 규칙을 한 곳에 모아둔 이유: 예전에는 "펼칠 때", "심사가 시작될 때",
-- "볼 수 없는 단계가 될 때" 세 군데에서 따로 판단했다.
-- 한 군데만 빠뜨려도 "목록은 떴는데 그림이 없는" 상태가 됐고, 실제로 그랬다.
function DrawBattleUI:_syncViewing(state)
	-- 보던 사람이 이번 라운드의 그리는 사람이 아니면 먼저 정리한다.
	-- (라운드가 바뀌었거나 그 사람이 나갔다)
	if self.viewing ~= nil and not table.find(state.drawers, self.viewing) then
		self:_setViewing(nil)
	end

	local canSpectate = self:_canSpectate(state)
	if canSpectate and self.spectateOpen then
		if self.viewing == nil then
			self:_setViewing(self:_defaultViewTarget(state))
		end
	else
		self:_setViewing(nil)
	end
end

-- 그림을 보는 동안 뒤의 3D 맵을 흐리게 한다. 그림에 눈이 가게 하려는 것이다.
--
-- BlurEffect 를 클라이언트에서 만들면 그 사람 화면에만 적용된다.
-- 서버가 만들면 전원에게 걸리므로 여기서 만들어야 한다.
function DrawBattleUI:_buildBlur()
	local blur = Instance.new("BlurEffect")
	blur.Name = "DrawBattleBlur"
	blur.Size = 0
	blur.Parent = Lighting
	self.blur = blur
	self.blurTarget = 0
end

-- 로블록스 기본 이동 조종기를 껐다 켜는 손잡이.
--
-- ⚠️ 모바일에서 캔버스를 문지르면 조종기(DynamicThumbstick)가 그 자리에 따라붙어서
--    그림 위에 회색 동그라미가 그려진다. GUI 에 Active = true 를 줘도 막히지 않는다.
--    조종기를 켜고 끄는 것 말고는 방법이 없다.
function DrawBattleUI:_setupControls()
	self.controlsEnabled = true

	-- WaitForChild 는 기다리는 동안 실행을 멈춘다.
	-- 여기서 멈추면 그동안 UI 가 정리되지 않은 채로 화면에 떠 있다.
	--
	-- ⚠️ 한 번 못 찾았다고 **포기하면 안 된다.**
	--    예전에는 10초 기다려보고 없으면 경고만 찍고 끝냈다.
	--    그런데 PlayerModule 은 캐릭터가 생기는 시점에 따라 더 늦게 오기도 한다.
	--    11초에 생겼다면 그 접속 내내 못 잡고, 그 동안 **그림을 그릴 때
	--    캐릭터 조종이 안 꺼진다.** 화면이 같이 돌아가는 그 증상이다.
	--    돌아간 뒤에 다시 할 사람이 없으면 그건 포기다. (README §5.5-9)
	task.spawn(function()
		local lastError = "?"
		for attempt = 1, 12 do -- 최대 1분쯤
			local ok, playerModule = pcall(function()
				local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 5)
				if not scripts then
					error("PlayerScripts 가 없다", 0)
				end
				local module = scripts:WaitForChild("PlayerModule", 5)
				if not module then
					error("PlayerScripts 안에 PlayerModule 이 없다", 0)
				end
				return require(module)
			end)
			if not ok then
				lastError = tostring(playerModule)
			end
			if ok and playerModule then
				self.controls = playerModule:GetControls()
				if attempt > 1 then
					print("[DrawBattle] PlayerModule 을 " .. attempt .. "번째에 찾았다.")
				end
				break
			end
			task.wait(1)
		end

		if not self.controls then
			-- 왜 실패했는지 같이 남긴다. 이유 없이 "못 찾았다" 만 있으면
			-- 다음에 볼 때도 똑같이 추측만 하게 된다. (§5.5-8)
			warn(
				"[DrawBattle] PlayerModule 을 끝내 못 찾았다. "
					.. "그리는 동안 캐릭터 조종이 안 꺼진다. 마지막 오류: "
					.. lastError
			)
		end

		-- 준비되는 사이에 이미 그릴 상태가 되었을 수 있다.
		self.controlsEnabled = nil
		self:_updateControls()
	end)
end

function DrawBattleUI:_updateControls()
	-- 종이가 떠 있는 동안에는 이동 조종기를 끈다.
	-- 그리는 사람은 어차피 의자에 앉아 있어서 움직일 일이 없고,
	-- 관전자는 그림을 보는 중이다.
	local enabled = not (self.showCanvas == true and self:_canvasOnScreen())
	if enabled == self.controlsEnabled then
		return -- 값이 그대로면 건드리지 않는다
	end
	self.controlsEnabled = enabled

	if self.controls then
		if enabled then
			self.controls:Enable()
		else
			self.controls:Disable()
		end
	end

	-- ⚠️ ControlModule 을 끄는 것만으로는 모자랄 때가 있다.
	--    조종기 그림(TouchGui)이 화면에 그대로 남아 색상 패널 위에 올라앉는다.
	--    그래서 그 판 자체도 같이 끄고 켠다.
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	if touchGui and touchGui:IsA("ScreenGui") then
		touchGui.Enabled = enabled
	end
end

-- 종이가 **실제로 화면에 떠 있는가.**
--
-- showCanvas 만 보면, 그 값이 참인데 종이가 안 그려진 상태에서
-- 배경만 흐려지고 이동이 잠긴 채로 갇힌다. 사용자가 풀 방법이 없다.
-- 눈에 보이는 것이 없으면 흐리게도, 못 움직이게도 하지 않는다.
function DrawBattleUI:_canvasOnScreen(): boolean
	return self.canvasRegion.Visible and self.canvasArea.AbsoluteSize.X > 1
end

function DrawBattleUI:_updateBlur()
	-- 결과 패널이 떠 있을 때도 흐리게 한다.
	-- 결과만 덩그러니 뜨고 뒤가 선명하면 화면이 둘로 갈라져 보인다.
	local resultsUp = self.lastState ~= nil
		and self.lastState.phase == Config.PHASE.RESULTS
	local blurred = (self.showCanvas == true and self:_canvasOnScreen()) or resultsUp
	local target = if blurred then UI.BACKGROUND_BLUR else 0
	if target == self.blurTarget then
		return -- 값이 그대로면 트윈을 새로 걸지 않는다
	end
	self.blurTarget = target
	TweenService:Create(
		self.blur,
		TweenInfo.new(Config.PRESENT_TWEEN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = target }
	):Play()
end

--------------------------------------------------------------------
-- 부품 붙이기
--------------------------------------------------------------------

function DrawBattleUI:_buildPanels()
	local canvas = self.canvas

	self.colorPanel = ColorPanel.new(self.backdrop, {
		onColorChanged = function(color)
			canvas:SetColor(color)
		end,
		onTransparencyChanged = function(value)
			canvas:SetTransparency(value)
		end,
		onThicknessChanged = function(value)
			canvas:SetThickness(value)
		end,
		onEraserThicknessChanged = function(value)
			canvas:SetEraserThickness(value)
		end,
	})

	-- 화면이 작으면 통째로 줄인다. 안쪽 배치는 손대지 않아도 된다.
	self.colorPanelScale = Instance.new("UIScale")
	self.colorPanelScale.Parent = self.colorPanel.instance

	self.toolbar = Toolbar.new(self.backdrop, {
		onToolSelected = function(toolId)
			canvas:SetTool(toolId)
		end,
	})

	self.toolbarScale = Instance.new("UIScale")
	self.toolbarScale.Parent = self.toolbar.instance

	self.topBar = TopBar.new(self.backdrop, {
		onSubmit = function()
			-- 제출은 취소할 수 없다. 한 번 묻고 나서 보낸다.
			-- 경고창이 뜬 동안 뒤에 그려지지 않도록 자격을 잠시 거둔다.
			self.wasEnabled = canvas.enabled
			canvas:SetEnabled(false)
			-- 경고창의 버튼을 누르려면 포인터가 있어야 한다.
			-- 상태를 따지지 않고 무조건 되돌린다.
			canvas:ShowPointer()
			self.submitDialog:Show()
		end,
	})

	self.submitDialog = ConfirmDialog.new(self.backdrop, {
		name = "SubmitDialog",
		title = "Submit Drawing?",
		message = "You cannot undo this. You will not be able to draw again this round.",
		confirmText = "Submit",
		cancelText = "Keep Drawing",
		onConfirm = function()
			-- ⚠️ **서버에 먼저 알린다.**
			--
			--    화면을 먼저 고치고 전송을 마지막에 두면, 앞에서 오류가 났을 때
			--    전송이 통째로 건너뛰어진다. 화면만 "제출됨" 이 되고 서버는 모른다.
			--    그러면 서버는 계속 "아직 그리는 중" 으로 보므로 그릴 자격이 남고,
			--    캔버스에 마우스를 올릴 때마다 포인터가 다시 숨는다.
			--    (제출 몇 초 뒤에 마우스가 사라지던 증상이 이것이다)
			Remotes.event(Remotes.SUBMIT_DRAWING):FireServer()

			self.topBar:SetSubmitted(true)
			-- onClose 가 먼저 자격을 되돌려 놓으므로 여기서 다시 거둔다.
			-- 서버가 상태를 보내주기 전까지의 짧은 틈을 막는 것이다.
			canvas:SetEnabled(false)
		end,
		onClose = function()
			canvas:SetEnabled(self.wasEnabled)
		end,
	})
	self.topBarScale = Instance.new("UIScale")
	self.topBarScale.Parent = self.topBar.instance

	self.spectateBar = SpectateBar.new(self.backdrop, {
		onSelect = function(userId)
			-- 이름을 누르면 언제나 그 사람을 본다. 여기서는 끄지 않는다.
			-- 관전을 끄는 것은 눈 버튼 하나로만 한다.
			self:_setViewing(userId)
		end,
		onRate = function(targetUserId, stars)
			-- 서버가 다시 검사한다. 여기서 보내는 건 "몇 개 주겠다" 는 뜻뿐이다.
			Remotes.event(Remotes.SEND_RATING):FireServer(targetUserId, stars)
		end,
	})
	self.resultsPanel = ResultsPanel.new(self.backdrop)
	self.promptReveal = PromptReveal.new(self.backdrop)
	self.spectateBarScale = Instance.new("UIScale")
	self.spectateBarScale.Parent = self.spectateBar.instance

	self.actionBar = ActionBar.new(self.sideBar, {
		-- ⚠️ 상대 그림을 보는 동안에는 셋 다 막는다.
		--    내 종이는 숨겨져 있을 뿐 살아 있어서, Z 를 누르면 **안 보이는 내 그림이** 지워진다.
		--    돌아와서야 선이 없어진 걸 알게 된다. 단축키(Z, Y)도 이 함수를 지나므로 같이 막힌다.
		--    지금은 그동안 이 줄 자체가 숨겨져서(_updateToolVisibility) 1차로 막힌다.
		--    여기는 2차 잠금이다. 숨기는 조건이 언젠가 바뀌어도 그림은 안 지워지게.
		onUndo = function()
			if self.peekShown then
				return
			end
			canvas:Undo()
		end,
		onRedo = function()
			if self.peekShown then
				return
			end
			canvas:Redo()
		end,
		-- 휴지통은 바로 지우지 않는다. 경고창을 먼저 띄운다.
		-- 되돌리기로 취소할 수 있게 만들어두긴 했지만,
		-- 그림을 다 그린 뒤에 잘못 누르면 심장이 내려앉는 버튼이라 한 번 더 묻는다.
		onClear = function()
			if self.peekShown then
				return -- 상대 그림을 보는 중이다. 안 보이는 내 그림을 지우면 안 된다.
			end
			-- 경고창이 떠 있는 동안은 그릴 자격을 잠시 거둔다.
			-- 감춰둔 마우스 포인터가 돌아와야 창의 버튼을 누를 수 있기 때문이다.
			-- 원래 자격이 있었는지 기억해뒀다가 그대로 되돌린다.
			-- (2단계에서 관전자가 이 창을 보게 되더라도 자격이 생기면 안 된다)
			self.wasEnabled = canvas.enabled
			canvas:SetEnabled(false)
			canvas:ShowPointer()
			self.clearDialog:Show()
		end,
	})

	self.clearDialog = ConfirmDialog.new(self.backdrop, {
		name = "ClearDialog",
		title = "Clear Canvas?",
		message = "This erases everything you have drawn. You can still undo it with Z.",
		confirmText = "Clear",
		cancelText = "Cancel",
		onConfirm = function()
			canvas:Clear()
		end,
		onClose = function()
			canvas:SetEnabled(self.wasEnabled)
		end,
	})
end

-- 캔버스에서 일어난 일을 UI 에 되돌려 알린다.
-- 이 방향의 연결이 없으면 스포이드로 색을 집어도 패널은 옛날 색을 보여준다.
function DrawBattleUI:_connectCanvas()
	local canvas = self.canvas

	canvas.onHistoryChanged = function()
		self.actionBar:SetHistoryState(canvas:CanUndo(), canvas:CanRedo())
	end

	canvas.onColorPicked = function(color)
		self.colorPanel:SetColor(color)
		-- 2초만 띄운다. (확정 2026-10-27 개발자 결정) 다른 알림(3.5초)보다 짧게 둔다.
		-- 그리다가 자주 쓰는 도구라, 길게 떠 있으면 그림 위쪽을 계속 가린다.
		--
		-- ⚠️ 2026-10-27 까지 이 알림은 **한 번도 안 떴다.** 알림 장치가 둘 있었기 때문이다.
		--    예전 것(아래쪽 작은 창)이 먼저 self.toast 라는 이름으로 만들어지고,
		--    나중에 생긴 상점 쪽 알림(Toast 모듈)이 **같은 이름을 덮어썼다.**
		--    여기서는 계속 예전 창을 켠다고 믿고 self.toast.Visible = true 를 했는데,
		--    그 이름은 이미 GUI 가 아니라 Lua 표였다. Lua 는 표에 없는 칸을 써도
		--    **오류 없이** 칸을 하나 새로 만들고 끝난다. 그래서 아무도 몰랐다.
		--    알림 장치를 하나로 합쳐서 같은 이름을 두 번 쓸 일 자체를 없앴다.
		self.toast:Show("Color picked", 2)
	end

	-- 3단계에서 여기에 서버 전송을 붙인다.
	-- canvas.onStrokeFinished = function(stroke) ... end
end

--------------------------------------------------------------------
-- 라운드
--------------------------------------------------------------------

function DrawBattleUI:_connectRound()
	-- 서버가 상태를 알려주기 전에는 아무것도 안 보여준다.
	-- 기본값을 true 로 두면 접속 직후 한순간 빈 종이가 번쩍인다.
	self.canDraw = false
	self.showCanvas = false
	self.roundPhase = nil
	-- 관전 중인 대상의 userId. 내가 그리는 중일 때는 nil 이다.
	self.viewing = nil
	self:_updateToolVisibility()

	-- 내가 선 하나를 다 그으면 서버로 보낸다.
	-- 로컬에는 이미 그려져 있으므로 서버 답을 기다리지 않는다. (README §5.3)
	self.canvas.onStrokeFinished = function(stroke)
		if not self.canDraw then
			return
		end
		Remotes.event(Remotes.SEND_STROKE):FireServer(DrawingCanvas.SerializeStroke(stroke))
	end

	Remotes.event(Remotes.ROUND_STATE).OnClientEvent:Connect(function(state)
		self:_applyRoundState(state)
	end)

	-- 관전 중인 사람이 새로 그은 선.
	Remotes.event(Remotes.STROKE_ADDED).OnClientEvent:Connect(function(userId, data)
		-- 그리는 중에 상대 그림이 오면 엿보기용 종이에 그린다.
		if self:_isPeekSource(userId) then
			self.peekCanvas:DrawStroke(DrawingCanvas.DeserializeStroke(data))
			return
		end
		-- 그 밖에는 내가 보고 있는 사람 것만 그린다.
		-- 내가 그은 선도 여기로 되돌아오지만, 그릴 때는 viewing 이 nil 이라 걸러진다.
		if self.viewing ~= userId then
			return
		end
		self.canvas:DrawStroke(DrawingCanvas.DeserializeStroke(data))
	end)

	-- 관전을 시작할 때, 또는 엿보기를 산 순간에 받는 그림 전체.
	Remotes.event(Remotes.CANVAS_SYNC).OnClientEvent:Connect(function(userId, list)
		if self:_isPeekSource(userId) then
			self.peekCanvas:Clear()
			for _, data in list do
				self.peekCanvas:DrawStroke(DrawingCanvas.DeserializeStroke(data))
			end
			return
		end
		if self.viewing ~= userId then
			return -- 답이 오는 사이에 다른 사람으로 옮겼다
		end
		self.canvas:Clear()
		for _, data in list do
			self.canvas:DrawStroke(DrawingCanvas.DeserializeStroke(data))
		end
	end)

	-- 중간에 들어왔어도 지금 상태를 바로 받아본다.
	Remotes.event(Remotes.REQUEST_STATE):FireServer()
end

-- 이 사람의 선을 엿보기용 종이에 그려야 하는가.
--
-- 조건: 지금 그리는 단계이고, 나도 이번 판에 그리는 사람이고, 보낸 사람은 상대다.
--
-- ⚠️ "엿보기를 샀는가(peeking)" 는 **일부러 안 본다.**
--    서버는 엿보기를 열어주는 순간 ① 상대 그림 전체를 보내고 ② 그다음에 "열렸다" 는
--    상태를 보낸다. 순서가 그렇다. peeking 을 보고 거르면 ①이 ②보다 먼저 와서 버려지고,
--    빈 종이만 보이게 된다. 돈을 냈는데 지금까지 그린 게 하나도 안 보이는 셈이다.
--
--    애초에 서버는 산 사람에게만 상대 그림을 보낸다. (RoundService 의 canSee)
--    **그림이 왔다는 것 자체가 볼 자격이 있다는 뜻이다.** 화면은 받은 것을 보여주기만 한다.
function DrawBattleUI:_isPeekSource(userId: number): boolean
	local state = self.lastState
	if not state or state.phase ~= Config.PHASE.DRAWING then
		return false
	end
	local me = Players.LocalPlayer.UserId
	if userId == me then
		return false
	end
	return table.find(state.drawers, me) ~= nil and table.find(state.drawers, userId) ~= nil
end

-- 처음에 띄울 그림. 아무도 안 고른 상태에서 쓰인다.
function DrawBattleUI:_defaultViewTarget(state): number?
	local userId = Players.LocalPlayer.UserId
	-- 그린 사람에게는 **상대 그림**을 먼저 보여준다.
	-- 자기 그림은 방금까지 보고 있었으니 궁금한 것은 상대 쪽이다.
	for _, id in state.drawers do
		if id ~= userId then
			return id
		end
	end
	return state.drawers[1]
end

-- 누구 그림을 볼지 바꾼다. nil 이면 관전을 끝낸다.
function DrawBattleUI:_setViewing(userId: number?)
	if self.viewing == userId then
		return
	end
	self.viewing = userId

	-- ⚠️ 여기서 오류가 나면 viewing 은 이미 바뀌었는데 화면은 옛 상태로 굳는다.
	--    그러면 빈 캔버스가 화면을 덮은 채 흐림과 이동 잠금이 안 풀린다.
	--    (실제로 모바일에서 그 상태에 갇혔다)
	--    그래서 캔버스 조작은 pcall 로 감싸고, 화면 갱신은 무슨 일이 있어도 지난다.
	local ok, err = pcall(function()
		-- 보던 그림을 지우고 새로 받는다.
		-- 지우지 않으면 두 사람의 그림이 한 종이에 겹친다.
		self.canvas:Clear()
		if userId then
			Remotes.event(Remotes.REQUEST_CANVAS):FireServer(userId)
		end
	end)
	if not ok then
		warn("[DrawBattle] Failed to switch canvas: " .. tostring(err))
	end

	self:_refreshView()
end

-- 지금 그림을 볼 수 있는 단계인가.
--   그리는 중(DRAWING) — 관전자만. 그리는 사람은 자기 그림을 그리느라 바쁘다.
--   심사 중(RATING)    — 모두. 그린 사람도 상대 그림을 본다.
function DrawBattleUI:_canSpectate(state): boolean
	if #state.drawers == 0 then
		return false
	end
	if state.phase == Config.PHASE.RATING then
		return true
	end
	if state.phase == Config.PHASE.DRAWING then
		return table.find(state.drawers, Players.LocalPlayer.UserId) == nil
	end
	return false
end

-- 별점을 줄 수 있는가. 그리는 사람은 심사하지 않는다. (§1)
function DrawBattleUI:_canRate(state): boolean
	return state.phase == Config.PHASE.RATING
		and table.find(state.drawers, Players.LocalPlayer.UserId) == nil
end

function DrawBattleUI:_applyRoundState(state)
	self.lastState = state
	local drawing = state.phase == Config.PHASE.DRAWING

	-- 여기서 하는 일은 **바뀌는 순간에만 해야 하는 것**뿐이다.
	-- 화면에 그리는 일은 전부 _refreshView 가 맡는다.
	--
	-- ⚠️ 각 단계를 따로 pcall 로 감싼다.
	--    예전에는 한 덩어리였는데, 앞 단계에서 오류가 나면 뒤 단계가 통째로 건너뛰어졌다.
	--    그래서 lastState 는 최신인데 상단 바와 결과 패널만 옛 상태로 굳었다.
	--    (phase=results 인데 상단 바는 "Rate: ... 0:14" 인 화면이 그것이다)

	-- 1) 관전 대상을 단계에 맞게 정리한다.
	local ok, err = pcall(function()
		if state.phase == Config.PHASE.RATING then
			-- 심사 중에는 눈 버튼을 거치지 않는다. 별을 주는 것이 이 단계의 할 일이다.
			self.spectateOpen = true
		elseif not self:_canSpectate(state) then
			self.spectateOpen = false
		end
		self:_syncViewing(state)
	end)
	if not ok then
		warn("[DrawBattle] Spectate sync failed: " .. tostring(err))
	end

	-- 2) 새 라운드가 시작되는 그 순간에만 캔버스를 비운다.
	ok, err = pcall(function()
		if drawing and self.roundPhase ~= Config.PHASE.DRAWING then
			self.canvas:Clear()
			-- 엿보기용 종이도 같이 비운다. 지난 판 상대 그림이 남아 있으면 안 된다.
			self.peekCanvas:Clear()
		end
	end)
	if not ok then
		warn("[DrawBattle] Canvas clear failed: " .. tostring(err))
	end
	-- 그리는 단계가 아니면 엿보기 화면은 무조건 닫는다.
	-- 심사로 넘어갔는데 상대 그림 쪽에 멈춰 있으면 내 그림으로 못 돌아온다.
	if not drawing then
		self.peekViewing = false
	end
	self.roundPhase = state.phase

	-- 3) 주제 공개 연출. 주제가 새로 정해진 그 순간에만 한 번 돈다.
	ok, err = pcall(function()
		if drawing and state.prompt ~= self.revealedPrompt then
			self.revealedPrompt = state.prompt
			-- 위쪽 줄에 답이 먼저 뜨면 연출이 의미가 없다. 끝날 때까지 가려둔다.
			self.topBar:SetPromptHidden(true)
			local function done()
				self.topBar:SetPromptHidden(false)
				self:_refreshView()
			end

			-- 누가 작성권으로 정한 주제면 뽑기를 돌리지 않고 이름과 함께 보여준다.
			-- 정해진 답을 놓고 기계를 돌리면 연기다. 다들 알림으로 미리 들었다.
			if typeof(state.promptAuthor) == "string" and state.promptAuthor ~= "" then
				self.promptReveal:ShowChosen(state.prompt, state.promptAuthor, done)
			else
				self.promptReveal:Play(state.prompt, done)
			end
		elseif not drawing then
			self.revealedPrompt = nil
			self.promptReveal:Cancel()
			self.topBar:SetPromptHidden(false)
		end
	end)
	if not ok then
		warn("[DrawBattle] Prompt reveal failed: " .. tostring(err))
	end

	-- 4) 화면 전체를 다시 그린다. 무슨 일이 있어도 여기까지 온다.
	self:_refreshView()
end

-- 지금 상태를 화면에 반영한다.
-- 라운드 상태가 새로 왔을 때와, 관전 대상을 바꿨을 때 둘 다 여기를 지난다.
function DrawBattleUI:_refreshView()
	local state = self.lastState
	if not state then
		return
	end

	local userId = Players.LocalPlayer.UserId
	local drawing = state.phase == Config.PHASE.DRAWING
	-- 뽑혔는지가 아니라 **앉아 있는지**를 본다.
	-- 의자에 앉은 사람만 그린다는 규칙이라 이쪽이 기준이다. (§5.7)
	local amSeated = table.find(state.seated or {}, userId) ~= nil
	local submitted = table.find(state.submitted, userId) ~= nil

	self.canSpectate = self:_canSpectate(state)
	self.showStars = self:_canRate(state)

	-- ⚠️ 경고창이 떠 있으면 그릴 자격을 거둔다.
	--
	--    예전에는 경고창을 띄울 때 canvas:SetEnabled(false) 를 한 번 부르고 말았다.
	--    그런데 되맞춤이 1초마다 이 함수를 부르면서 canDraw 로 다시 켜버렸다.
	--    경고창이 떠 있는 동안은 아직 제출 전이라 canDraw 가 참이기 때문이다.
	--    **내가 만든 회복 장치가 내가 꺼둔 것을 다시 켠 것이다.**
	--    그래서 경고창 위에서 마우스 포인터가 1초 뒤에 사라졌다.
	--
	--    회복 장치가 보는 값 자체에 "지금은 그리면 안 된다" 를 넣어야 한다.
	local dialogOpen = self.submitDialog ~= nil
		and (self.submitDialog.instance.Visible or self.clearDialog.instance.Visible)

	-- **"도구를 보여줄까" 와 "지금 그을 수 있는가" 는 다른 질문이다.**
	--
	-- 경고창이 떠 있는 동안에도 도구는 그대로 보여야 한다.
	-- 하나로 묶었더니 경고창을 띄우는 순간 팔레트와 펜이 통째로 사라졌다.
	self.showTools = amSeated and drawing and not submitted

	-- 엿보기를 샀는가. **서버가 알려준 값으로만** 정한다.
	--
	-- ⚠️ 아래 canDraw 보다 **먼저** 정해야 한다. 상대 그림을 보는 중이면 못 그리기 때문이다.
	--    뒤에서 정하면 이번 차례에는 옛 값을 보고 판단해서 한 박자 늦는다.
	local mine = state.drawInfo and state.drawInfo[tostring(userId)]
	local peeking = mine ~= nil and mine.peeking == true
	if peeking and not self.peeking then
		-- 막 열렸다. 산 줄 모르고 지나가지 않게 어떻게 쓰는지까지 알려준다.
		self.toast:Show("Peek unlocked! Press 👀 to switch views.")
	end
	self.peeking = peeking

	-- 👀 를 쓸 수 있는가. **이번 판의 그리는 사람이면 제출한 뒤에도** 쓴다. (확정 2026-10-27 개발자 결정)
	--
	-- 처음에는 showTools(= 아직 그리는 중)를 그대로 썼다. 그래서 Submit 을 누르는 순간 👀 가 사라졌다.
	-- 그런데 제출하고 나서 남은 시간에 "상대는 뭘 그렸나" 가 제일 궁금하다. 이때 사도 된다.
	-- 이미 제출했으니 베낄 수도 없다. (§3.3 의 걱정이 오히려 사라지는 때다)
	--
	-- 서버는 원래부터 "제출했는가" 를 안 본다. applyPeek 과 canSee 둘 다 단계와
	-- "그리는 사람인가" 만 본다. 그래서 바꿀 것은 화면 쪽 조건 하나뿐이다.
	--
	-- 의자에 앉아 있어야 한다는 조건은 그림판이 보이는 조건(showCanvas 의 1번)과 같다.
	-- 👀 는 그림판에 붙어 있으므로 그림판 없이 혼자 뜰 일이 없게 맞춰둔다.
	self.canPeek = amSeated and drawing

	-- 지금 상대 그림을 보여줄 것인가.
	-- 내가 👀 를 눌렀고(peekViewing), 실제로 샀고(peeking), 👀 를 쓸 수 있을 때만.
	-- 셋 중 하나라도 아니면 무조건 내 그림으로 돌아온다. 갇히는 일이 없게.
	-- (심사로 넘어가면 canPeek 이 거짓이 되어 저절로 돌아온다. 심사 때는 관전 줄로 둘 다 본다)
	self.peekShown = self.peekViewing and self.peeking and self.canPeek

	-- ⚠️ 이 잠금은 클라이언트 편의 기능일 뿐이다. 익스플로잇으로 우회된다.
	--    서버가 스트로크를 받을 때마다 자격을 다시 검사한다. (README §3.4, §7-7)
	--
	-- 상대 그림을 보는 동안에는 못 그린다. **그 사이에도 타이머는 간다.**
	-- 이게 엿보기의 대가다. 베끼려면 시간을 써야 한다. (§3.3)
	self.canDraw = self.showTools and not dialogOpen and not self.peekShown

	-- 그릴 차례 게이지를 숨기는 경우는 둘이다.
	--
	--   1) 심사 중 — **모두에게** 숨긴다.
	--      이때는 화면 아래 가운데에 별점 줄이 펼쳐져 있어서 자리가 겹치고,
	--      지금 할 일은 남의 그림에 별을 주는 것이지 다음 판을 가늠하는 게 아니다.
	--
	--   2) 내가 이번 라운드의 그리는 사람 — 그리는 동안과 결과까지.
	--      이미 뽑힌 판에서 "그릴 확률" 은 뜻이 없고, 옆에 버튼이 있으면 방해가 된다.
	--
	-- 대기·인터미션에는 모두에게 보인다. 다음 판을 가늠하는 값이라 그때가 제일 쓸모 있다.
	local drawerThisRound = table.find(state.drawers, userId) ~= nil
	local roundRunning = state.phase == Config.PHASE.DRAWING
		or state.phase == Config.PHASE.RATING
		or state.phase == Config.PHASE.RESULTS
	local ratingPhase = state.phase == Config.PHASE.RATING
	self.showChance = not ratingPhase and not (drawerThisRound and roundRunning)

	-- 종이가 보이는 경우는 둘이다.
	--   1) 내가 앉아서 그리는 중 (제출한 뒤에도 내 그림은 계속 보여야 한다)
	--   2) 남의 그림을 관전하는 중
	self.showCanvas = (amSeated and drawing) or self.viewing ~= nil

	-- **화면에 그리는 일은 전부 여기 모아둔다.**
	-- 되맞춤(_startReconciler)이 1초마다 이 함수를 부르므로,
	-- 한 번 어긋나도 여기 있는 것은 전부 스스로 회복된다.
	-- 상단 바와 결과 패널이 여기 없어서 영영 안 고쳐진 적이 있다.
	self.topBar:Update(state, userId)

	if state.phase == Config.PHASE.RESULTS then
		self.resultsPanel:Update(state.results)
	else
		self.resultsPanel:Hide()
	end

	self.spectateBar:Update(state, self.viewing, self.showStars)
	-- 승리수/점수도 여기서 한 번 더 칠한다.
	-- 값은 leaderstats 신호로 이미 들어오지만, 신호를 한 번 놓치면
	-- 스스로 회복할 방법이 없다. 되맞춤이 1초마다 덮어준다. (§5.5-6)
	self:_paintStats()
	-- 내 몫만 꺼내 쓴다. 서버는 전원 몫을 한 번에 보낸다.
	-- 표의 열쇠가 문자열인 이유: 로블록스는 숫자 열쇠를 그대로 실어 보내지 못한다.
	self.chanceBar:Update(mine)

	self:_paintShop()

	self.canvas:SetEnabled(self.canDraw)
	self:_updateToolVisibility()
end

return DrawBattleUI
