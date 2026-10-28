--!strict
--[[
	TipLine.lua  —  기다리는 동안 상단 바 아래에 흐리게 도는 팁 한 줄

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	언제 보이나 (확정 2026-10-28 개발자 결정)
	  대기·인터미션 때, 그리고 그리기 단계에서는 그리지 않는 사람에게만(관전 화면을 안 열었을 때).
	  심사·결과 때와, 내가 그리는 중일 때는 숨는다.
	  보일지 말지는 DrawBattleUI 가 정한다. **이 파일은 받아서 그리기만 한다.** (README §5.5-1)

	왜 흐리게 하나
	  읽고 싶은 사람만 읽는 글이다. 진하면 알림(Toast)처럼 보여서 "무슨 일이 생겼나" 하고 보게 된다.
	  그리고 맵 위에 바로 떠 있어서 뒤 배경이 밝을 수도 어두울 수도 있다.
	  그래서 글자에 옅은 흰 테두리를 둘러 어느 배경에서도 읽히게 한다.

	문구는 Config.TIPS 에 있고 순서대로 돈다.
	처음 보여줄 팁은 사람마다 무작위로 고른다. 다들 첫 팁부터 보면 뒤쪽 팁은 아무도 못 본다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local FADE_SECONDS = 0.4

local TipLine = {}
TipLine.__index = TipLine

-- 글자에 <b> 같은 꾸밈(RichText)을 쓰므로, 팁 문구에 < > & 가 들어가면 꾸밈으로 읽혀서 깨진다.
-- 문구는 그대로 보이게 바꿔서 넣는다.
local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function TipLine.new(parent: Instance)
	local self = setmetatable({}, TipLine)

	local label = UIHelper.label("", parent)
	label.Name = "TipLine"
	label.AnchorPoint = Vector2.new(0.5, 0)
	-- 세로 자리는 화면 크기에 따라 SetLayout 이 정한다. (상단 바 높이가 배율을 타기 때문)
	label.Position = UDim2.new(0.5, 0, 0, 0)
	label.Size = UDim2.fromOffset(UI.TIP_WIDTH, 0)
	-- 길면 두 줄로 접는다. 높이는 내용에 맡긴다.
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextSize = UI.TIP_TEXT_SIZE
	label.Font = Enum.Font.GothamMedium
	label.RichText = true
	label.TextTransparency = 1 -- 처음에는 안 보이다가 서서히 나타난다
	-- 누르는 물건이 아니다. 밑에 있는 것을 가리면 안 된다. (Toast 와 같은 이유)
	label.Active = false
	label.ZIndex = 9
	label.Visible = false
	self.instance = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 1.5
	stroke.Transparency = 1
	-- Contextual: 글자 테두리로 쓴다. (기본값 Border 는 상자 테두리다)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	self.stroke = stroke

	local scale = Instance.new("UIScale")
	scale.Parent = label
	self.scale = scale

	self.index = math.random(#Config.TIPS)
	self.shown = false
	-- 숨겼다 다시 보여줄 때 예전 차례가 끼어들지 않게 번호를 매긴다. (Toast 와 같은 방법)
	self.token = 0

	return self
end

-- 화면 크기가 바뀔 때 부른다.
-- top 은 상단 바 바로 아래 높이다. 상단 바 높이는 배율을 타므로 바깥에서 계산해 넘긴다.
function TipLine:SetLayout(scale: number, top: number)
	self.scale.Scale = scale
	self.instance.Position = UDim2.new(0.5, 0, 0, top)
end

function TipLine:_fade(target: number)
	local info = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self.instance, info, { TextTransparency = target }):Play()
	-- 테두리는 글자보다 더 옅게 둔다. 진하면 글자가 두꺼워 보인다.
	local strokeTarget = if target >= 1 then 1 else math.min(1, target + 0.35)
	TweenService:Create(self.stroke, info, { Transparency = strokeTarget }):Play()
end

-- 보일지 말지만 받는다. 같은 값이 계속 와도(되맞춤이 1초마다 부른다) 처음 한 번만 움직인다.
function TipLine:SetVisible(visible: boolean)
	if visible == self.shown then
		return
	end
	self.shown = visible
	self.token += 1
	local token = self.token

	if not visible then
		self.instance.Visible = false
		self.instance.TextTransparency = 1
		self.stroke.Transparency = 1
		return
	end

	self.instance.Visible = true
	task.spawn(function()
		while self.token == token do
			self.instance.Text = "<b>TIP</b>   " .. escape(Config.TIPS[self.index])
			self:_fade(UI.TIP_TRANSPARENCY)
			task.wait(UI.TIP_SECONDS)
			if self.token ~= token then
				return -- 그 사이에 숨었다
			end
			self:_fade(1)
			task.wait(FADE_SECONDS)
			self.index = self.index % #Config.TIPS + 1
		end
	end)
end

return TipLine
