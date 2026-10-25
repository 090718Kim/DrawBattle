--!strict
--[[
	TopBar.lua  —  화면 위쪽 줄 (주제 / 제출 / 남은 시간)

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	보여주는 것은 라운드 단계에 따라 달라진다.
		대기      "Waiting for players (2/3)"
		인터미션   "Next round · 3 Minute"   + 남은 시간
		그리기     "Theme: Apple"            + 남은 시간 + [Submit] (그리는 사람만)

	남은 시간을 어떻게 세는가
	  서버는 "몇 초 남았다" 가 아니라 **"언제 끝난다"** 를 한 번만 보낸다.
	  그러면 클라이언트가 알아서 세어 내려갈 수 있어서 네트워크를 훨씬 덜 쓴다.
	  서버와 같은 시계를 봐야 하므로 os.time() 이 아니라
	  Workspace:GetServerTimeNow() 를 쓴다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local TopBar = {}
TopBar.__index = TopBar

function TopBar.new(parent: Instance, callbacks: { onSubmit: () -> () })
	local self = setmetatable({}, TopBar)
	self.callbacks = callbacks

	local bar = UIHelper.panel("TopBar", parent)
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, UI.TOP_BAR_MARGIN)
	bar.Size = UDim2.fromOffset(UI.TOP_BAR_WIDTH, UI.TOP_BAR_HEIGHT)
	-- 이 줄을 누른 것이 밑의 캔버스에 그려지면 안 된다. (README §3.8)
	bar.Active = true
	bar.ZIndex = 10
	self.instance = bar

	-- 왼쪽: 주제
	local theme = UIHelper.label("", bar)
	theme.Name = "Theme"
	theme.Position = UDim2.fromOffset(18, 0)
	theme.Size = UDim2.new(0.34, 0, 1, 0)
	theme.Font = Enum.Font.GothamBold
	theme.TextSize = 17
	theme.TextTruncate = Enum.TextTruncate.AtEnd
	theme.ZIndex = 11
	self.themeLabel = theme

	-- 가운데: 제출 버튼
	local submit = Instance.new("TextButton")
	submit.Name = "Submit"
	submit.AnchorPoint = Vector2.new(0.5, 0.5)
	submit.Position = UDim2.fromScale(0.5, 0.5)
	submit.Size = UDim2.fromOffset(132, 38)
	submit.BackgroundColor3 = UI.ACCENT_COLOR
	submit.BorderSizePixel = 0
	submit.Text = "Submit"
	submit.TextColor3 = Color3.new(1, 1, 1)
	submit.Font = Enum.Font.GothamBold
	submit.TextSize = 16
	submit.Visible = false
	submit.ZIndex = 11
	submit.Parent = bar
	UIHelper.corner(submit, 10)
	self.submitButton = submit

	submit.Activated:Connect(function()
		-- 여기서는 "누르겠다" 만 알린다.
		-- 제출은 취소할 수 없으므로 경고창을 한 번 거친다. 잠그는 것은 그 뒤다.
		if self.hasSubmitted then
			return
		end
		self.callbacks.onSubmit()
	end)

	-- 오른쪽: 남은 시간
	local timer = UIHelper.label("", bar)
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(1, 0)
	timer.Position = UDim2.new(1, -18, 0, 0)
	timer.Size = UDim2.new(0.24, 0, 1, 0)
	timer.TextXAlignment = Enum.TextXAlignment.Right
	timer.Font = Enum.Font.GothamBold
	timer.TextSize = 20
	timer.ZIndex = 11
	self.timerLabel = timer

	-- 대기 중에는 줄 전체를 한 문장으로 쓴다.
	local waiting = UIHelper.label("", bar)
	waiting.Name = "Waiting"
	waiting.Size = UDim2.fromScale(1, 1)
	waiting.TextXAlignment = Enum.TextXAlignment.Center
	waiting.Font = Enum.Font.GothamMedium
	waiting.TextSize = 16
	waiting.TextColor3 = UI.MUTED_TEXT_COLOR
	waiting.Visible = false
	waiting.ZIndex = 11
	self.waitingLabel = waiting

	self.hasSubmitted = false
	self.timerText = ""
	self.promptHidden = false

	-- 시계는 서버가 다시 알려주지 않아도 계속 흘러야 한다.
	RunService.Heartbeat:Connect(function()
		self:_refreshTimer()
	end)

	return self
end

-- 바깥에서 잠글 때 쓴다. (경고창에서 확인을 누른 직후)
function TopBar:SetSubmitted(submitted: boolean)
	self:_setSubmitted(submitted)
end

-- 뽑기 연출이 도는 동안에는 주제를 감춘다.
-- 위쪽 줄에 답이 먼저 떠 있으면 가운데 연출이 아무 의미가 없다.
function TopBar:SetPromptHidden(hidden: boolean)
	self.promptHidden = hidden
end

function TopBar:_setSubmitted(submitted: boolean)
	self.hasSubmitted = submitted
	self.submitButton.Text = if submitted then "Submitted" else "Submit"
	self.submitButton.BackgroundColor3 = if submitted
		then UI.MUTED_TEXT_COLOR
		else UI.ACCENT_COLOR
	self.submitButton.AutoButtonColor = not submitted
end

function TopBar:_refreshTimer()
	local state = self.state
	if not state or state.endsAt <= 0 then
		self.timerLabel.Text = ""
		return
	end

	-- 정수로 내려서 계산해야 "0:60" 같은 이상한 값이 안 나온다.
	local remaining = math.max(0, math.floor(state.endsAt - Workspace:GetServerTimeNow()))
	local text = string.format("%d:%02d", remaining // 60, remaining % 60)

	-- 매 프레임 같은 글자를 다시 쓰면 낭비다. 바뀔 때만 건드린다.
	if text ~= self.timerText then
		self.timerText = text
		self.timerLabel.Text = text
	end
end

-- 서버가 보낸 라운드 상태를 화면에 반영한다.
function TopBar:Update(state, localUserId: number)
	self.state = state

	local waiting = state.phase == Config.PHASE.WAITING
	self.waitingLabel.Visible = waiting
	self.themeLabel.Visible = not waiting
	self.timerLabel.Visible = not waiting

	if waiting then
		self.submitButton.Visible = false
		-- 기다리는 이유가 둘이라 문구를 나눈다.
		--
		-- 사람은 충분한데 다들 "안 그리기" 를 눌러서 못 여는 경우가 있다.
		-- 그때 "Waiting for players (5/3)" 라고 띄우면 숫자는 채웠는데 안 시작하는,
		-- 설명이 안 되는 화면이 된다. 무엇이 모자란지 그대로 쓴다.
		if state.waitingForDrawers then
			self.waitingLabel.Text = "Waiting for someone to draw"
		else
			self.waitingLabel.Text = string.format(
				"Waiting for players (%d/%d)",
				state.playerCount, state.minPlayers
			)
		end
		return
	end

	if state.phase == Config.PHASE.INTERMISSION then
		self.submitButton.Visible = false
		self.themeLabel.Text = "Next round · " .. state.modeLabel
		-- 다음 라운드를 위해 잠금을 푼다.
		self:_setSubmitted(false)
	elseif state.phase == Config.PHASE.RATING then
		-- 심사 중에는 아무도 그리지 않는다. 제출 버튼이 있으면 안 된다.
		self.submitButton.Visible = false
		self.themeLabel.Text = "Rate: " .. (state.prompt or "?")
	elseif state.phase == Config.PHASE.RESULTS then
		self.submitButton.Visible = false
		self.themeLabel.Text = "Result"
	else
		-- 뽑기 연출이 도는 동안에는 답을 가린다.
		local prompt = if self.promptHidden then "???" else (state.prompt or "?")
		self.themeLabel.Text = "Theme: " .. prompt

		-- 제출 버튼은 이번 라운드에 그리는 사람에게만 보인다.
		local amDrawer = table.find(state.drawers, localUserId) ~= nil
		self.submitButton.Visible = amDrawer
		self:_setSubmitted(table.find(state.submitted, localUserId) ~= nil)
	end

	self:_refreshTimer()
end

return TopBar
