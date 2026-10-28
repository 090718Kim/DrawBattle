--!strict
--[[
	Toast.lua  —  짧게 떴다 사라지는 알림

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	게임의 **유일한** 알림 장치다. 주제 작성권을 받았을 때, 캐시템을 샀을 때,
	누가 다음 주제를 정했을 때, 스포이드로 색을 집었을 때 등에 쓴다.
	21분은 긴 시간이라, 받은 줄 모르고 지나가면 그동안 기다린 것이 없던 일이 된다.
	오른쪽 아래 🎟️ 칸이 0에서 1로 바뀌는 것만으로는 아무도 못 알아챈다.

	⚠️ 알림 장치를 하나 더 만들지 말 것.
	   2026-10-27 까지 DrawBattleUI 안에 옛 알림 창이 따로 있었는데, 둘이 같은 이름
	   (self.toast)을 쓰다가 나중 것이 덮어써서 스포이드 알림이 **소리 없이** 안 떴다.

	Active = false 로 둔다.
	이 알림이 클릭을 삼키면 떠 있는 몇 초 동안 그 자리를 못 누른다.
	알려주려고 만든 것이 방해가 되면 안 된다. (§3.8 의 반대쪽)

	화면 위쪽 가운데에 띄운다.
	아래쪽은 툴바·관전 줄·차례 게이지가 이미 나눠 쓰고, 양쪽 구석도 임자가 있다.
	위쪽은 상단 바 하나뿐이라 그 바로 아래가 비어 있다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local Toast = {}
Toast.__index = Toast

local SLIDE = 0.25
local FADE = 0.35

function Toast.new(parent: Instance)
	local self = setmetatable({}, Toast)
	-- 뒤에 또 뜨면 앞의 것은 화면을 넘겨줘야 한다.
	-- 표를 하나 두고, 자기 차례가 아니면 조용히 물러난다.
	self.token = 0

	local panel = UIHelper.panel("Toast", parent)
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Size = UDim2.fromOffset(0, UI.TOAST_HEIGHT)
	panel.AutomaticSize = Enum.AutomaticSize.X
	panel.BackgroundTransparency = 0
	-- ⚠️ 누르는 물건이 아니다. 입력을 삼키면 안 된다.
	panel.Active = false
	panel.ZIndex = 48
	panel.Visible = false
	panel.Parent = parent
	self.instance = panel

	UIHelper.padding(panel, 12)

	local label = UIHelper.label("", panel)
	label.Name = "Message"
	label.Size = UDim2.fromOffset(0, UI.TOAST_HEIGHT - 24)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.TextSize = 16
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 49
	self.label = label

	return self
end

function Toast:_setTransparency(value: number)
	self.instance.BackgroundTransparency = value
	self.label.TextTransparency = value
	local stroke = self.instance:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = value
	end
end

-- 위에서 미끄러져 내려왔다가, 잠시 머물고, 흐려지며 사라진다.
function Toast:Show(message: string, seconds: number?)
	self.token += 1
	local token = self.token
	local hold = seconds or UI.TOAST_SECONDS

	local function stillMine(): boolean
		return self.token == token
	end

	task.spawn(function()
		self.label.Text = message
		self.instance.Visible = true
		self.instance.Position = UDim2.new(0.5, 0, 0, UI.TOAST_TOP - 20)
		self:_setTransparency(0)

		TweenService:Create(
			self.instance,
			TweenInfo.new(SLIDE, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, UI.TOAST_TOP) }
		):Play()

		task.wait(hold)
		if not stillMine() then
			return -- 그 사이에 다음 알림이 화면을 가져갔다
		end

		local fade = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(self.instance, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(self.label, fade, { TextTransparency = 1 }):Play()
		local stroke = self.instance:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end

		task.wait(FADE)
		if stillMine() then
			self.instance.Visible = false
		end
	end)
end

return Toast
