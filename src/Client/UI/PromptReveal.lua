--!strict
--[[
	PromptReveal.lua  —  주제 단어 뽑기 연출

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	라운드가 시작되면 화면 한가운데에 크게 떴다가,
	무작위 단어가 뽑기 기계처럼 돌다가 진짜 주제에서 멈추고, 잠시 뒤 사라진다.

	연출이 두 가지다.

	  뽑기 (Play) — 딕셔너리에서 고른 주제. 전부 합쳐 Config.PROMPT_REVEAL_SECONDS
	    1) 살짝 커지며 나타난다
	    2) 단어가 빠르게 돌다가 **점점 느려지며** 멈춘다
	       등속으로 돌리다 뚝 끊으면 "멈췄다" 가 아니라 "끊겼다" 로 보인다
	    3) 멈추는 순간 한 번 튕긴다
	    4) 잠시 머물렀다가 사라진다

	  누구의 주제 (ShowChosen) — 작성권으로 정한 주제. Config.PROMPT_CHOSEN_SECONDS
	    "MrKim's theme" 아래에 주제를 바로 띄우고, 잠시 뒤 사라진다. **돌리지 않는다.**
	    정해진 답을 놓고 뽑기 기계를 돌리면 연기다. 다들 알림으로 미리 들었다.

	  나타나기와 사라지기는 둘이 똑같다(_appear, _disappear).
	  가운데만 다르다. 한쪽만 고쳐서 둘이 다르게 보이는 일을 막으려는 것이다.

	Active = false 로 둔다. 이 창이 클릭을 삼키면
	연출이 도는 3초 동안 아무것도 누를 수 없게 된다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local PromptReveal = {}
PromptReveal.__index = PromptReveal

local FADE_IN = 0.2
local FADE_OUT = 0.3

function PromptReveal.new(parent: Instance)
	local self = setmetatable({}, PromptReveal)
	self.token = 0

	-- 뒤를 덮는 판. 캔버스까지 포함해서 화면 전체를 어둡게 한다.
	--
	-- 3D 배경은 BlurEffect 로 흐릴 수 있지만 UI 는 흐릴 수 없다.
	-- 대신 어둡게 덮으면 앞의 글자에 눈이 쏠려서 같은 효과가 난다.
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	-- 클릭을 삼키지 않는다. 연출 때문에 화면이 멈추면 안 된다.
	dim.Active = false
	dim.ZIndex = 39
	dim.Visible = false
	dim.Parent = parent
	self.dim = dim

	local panel = UIHelper.panel("PromptReveal", parent)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(UI.PROMPT_REVEAL_WIDTH, UI.PROMPT_REVEAL_HEIGHT)
	panel.BackgroundTransparency = 0
	-- 클릭을 삼키지 않는다. 연출 때문에 화면이 멈추면 안 된다.
	panel.Active = false
	-- 캔버스(1)와 패널(10) 위, 경고창(50) 아래.
	panel.ZIndex = 40
	panel.Visible = false
	self.instance = panel

	-- 나타날 때 살짝 커지는 효과에 쓴다.
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = panel
	self.scale = scale

	local caption = UIHelper.label("THEME", panel)
	caption.Name = "Caption"
	caption.Position = UDim2.fromScale(0, 0.18)
	caption.Size = UDim2.fromScale(1, 0.22)
	caption.TextXAlignment = Enum.TextXAlignment.Center
	caption.TextColor3 = UI.MUTED_TEXT_COLOR
	caption.Font = Enum.Font.GothamMedium
	caption.TextSize = 18
	-- 이름이 길면("SuperLongDisplayName's theme") 판 밖으로 넘친다. 끝을 줄인다.
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.ZIndex = 41
	self.caption = caption

	local word = UIHelper.label("", panel)
	word.Name = "Word"
	word.Position = UDim2.fromScale(0, 0.38)
	word.Size = UDim2.fromScale(1, 0.44)
	word.TextXAlignment = Enum.TextXAlignment.Center
	word.Font = Enum.Font.GothamBold
	-- ⚠️ 크기를 52 로 못박으면 긴 주제가 판 밖으로 넘친다.
	--    판은 460px 인데, 주제 작성권으로 쓸 수 있는 24자를 52 크기로 쓰면 750px 쯤 된다.
	--    단어가 전부 8자 이하일 때는 안 보이던 버그다.
	--
	--    TextScaled 를 켜면 칸에 맞게 글자가 줄어든다. 그런데 그것만 켜면
	--    "Cat" 같은 짧은 단어가 칸을 꽉 채우도록 **커지기도** 한다.
	--    그래서 최대 크기를 52 로 막는다. 짧으면 52, 길면 줄어든다.
	word.TextScaled = true
	word.ZIndex = 41
	self.word = word

	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 52
	-- 이보다 작아지면 화면 가운데 띄우는 의미가 없다. 그 전에 칸 끝이 잘린다.
	limit.MinTextSize = 20
	limit.Parent = word

	return self
end

function PromptReveal:_setTransparency(value: number)
	self.instance.BackgroundTransparency = value
	-- 1 → 완전히 투명, 0 → 가장 어둡게. 판의 최대 어둡기에 비례해서 따라간다.
	self.dim.BackgroundTransparency = 1 - (1 - value) * UI.PROMPT_DIM_STRENGTH
	self.caption.TextTransparency = value
	self.word.TextTransparency = value
	local stroke = self.instance:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = value
	end
end

-- 돌던 연출을 멈춘다. 라운드가 바뀌면 앞의 것이 화면을 뺏으면 안 된다.
function PromptReveal:Cancel()
	self.token += 1
	self.instance.Visible = false
	self.dim.Visible = false
end

-- 새 연출을 시작한다. 앞의 것은 이 순간부터 화면을 넘겨준다.
-- 돌려주는 함수로 "아직 내 차례인가" 를 물어볼 수 있다.
function PromptReveal:_begin(): () -> boolean
	self.token += 1
	local token = self.token
	return function(): boolean
		return self.token == token
	end
end

-- 살짝 커지며 나타난다. 두 연출이 똑같이 쓴다.
function PromptReveal:_appear()
	self.dim.Visible = true
	self.instance.Visible = true
	self:_setTransparency(1)
	self.scale.Scale = 0.8

	local appear = TweenInfo.new(FADE_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(self.scale, appear, { Scale = 1 }):Play()
	TweenService:Create(self.instance, appear, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(self.dim, appear, {
		BackgroundTransparency = 1 - UI.PROMPT_DIM_STRENGTH,
	}):Play()
	self:_setTransparency(0)
	task.wait(FADE_IN)
end

-- 흐려지며 사라진다. 두 연출이 똑같이 쓴다.
-- 다 사라지면 onFinished 를 부른다. 그 사이에 다른 연출이 화면을 가져갔으면 안 부른다.
function PromptReveal:_disappear(stillMine: () -> boolean, onFinished: (() -> ())?)
	local fade = TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(self.instance, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(self.dim, fade, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(self.caption, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(self.word, fade, { TextTransparency = 1 }):Play()
	task.wait(FADE_OUT)
	if not stillMine() then
		return
	end

	self.instance.Visible = false
	self.dim.Visible = false
	if onFinished then
		onFinished()
	end
end

-- word 에서 멈추는 뽑기 연출을 보여준다. 딕셔너리에서 고른 주제에 쓴다.
-- onFinished 는 연출이 완전히 끝났을 때 불린다.
function PromptReveal:Play(word: string, onFinished: (() -> ())?)
	local stillMine = self:_begin()
	local words = Config.PROMPTS

	task.spawn(function()
		-- ⚠️ 제목을 매번 다시 적는다.
		--    바로 앞 판이 "MrKim's theme" 였으면 그 글자가 그대로 남아 있다.
		self.caption.Text = "THEME"
		self.word.Text = words[math.random(#words)]

		-- 1) 살짝 커지며 나타난다
		self:_appear()
		if not stillMine() then
			return
		end

		-- 2) 점점 느려지며 멈춘다
		local elapsed = 0
		local step = 0.04
		while elapsed < Config.PROMPT_ROLL_SECONDS do
			if not stillMine() then
				return
			end
			self.word.Text = words[math.random(#words)]
			task.wait(step)
			elapsed += step
			step *= 1.18
		end
		if not stillMine() then
			return
		end

		-- 3) 진짜 주제에서 멈추면서 한 번 튕긴다
		self.word.Text = word
		self.scale.Scale = 1.15
		TweenService:Create(
			self.scale,
			TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()

		-- 4) 잠시 머물렀다가 사라진다
		local used = FADE_IN + elapsed + FADE_OUT
		local hold = math.max(0.4, Config.PROMPT_REVEAL_SECONDS - used)
		task.wait(hold)
		if not stillMine() then
			return
		end

		self:_disappear(stillMine, onFinished)
	end)
end

-- 누군가 작성권으로 정한 주제를 보여준다. **돌리지 않는다.**
--
--   MrKim's theme
--      Apple
--
-- 한 줄로 "MrKim's theme: Apple" 이라고 쓰지 않은 이유:
-- 주제 낱말이 이 창의 주인공인데, 이름과 같은 크기로 한 줄에 넣으면
-- 정작 그릴 낱말이 작아진다. 뽑기 연출과 같은 자리에 같은 크기로 둔다.
function PromptReveal:ShowChosen(word: string, author: string, onFinished: (() -> ())?)
	local stillMine = self:_begin()

	task.spawn(function()
		self.caption.Text = author .. "'s theme"
		self.word.Text = word

		self:_appear()
		if not stillMine() then
			return
		end

		local hold = math.max(0.4, Config.PROMPT_CHOSEN_SECONDS - FADE_IN - FADE_OUT)
		task.wait(hold)
		if not stillMine() then
			return
		end

		self:_disappear(stillMine, onFinished)
	end)
end

return PromptReveal
