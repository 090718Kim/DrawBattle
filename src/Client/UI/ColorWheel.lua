--!strict
--[[
	ColorWheel.lua  —  둥근 색상환 + 밝기 막대

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	색을 고르는 방식
	  원판 위 어디를 눌렀는지로 색이 정해진다.
	    중심에서 본 각도  → 색상(Hue).   위쪽이 빨강, 시계 방향으로 돈다.
	    중심에서의 거리   → 진하기(Saturation). 중심이 흰색, 가장자리가 진한 색.
	    오른쪽 세로 막대  → 밝기(Value).

	여기서 제일 중요한 점:
	  **원판의 픽셀을 읽지 않는다.** 누른 위치만 알면 색은 계산으로 나온다.
	  그래서 색상환 이미지 에셋도, EditableImage 픽셀 API 도 필요 없다. (README §7-4)
	  화면에 보이는 원판은 "지금 어디를 누르면 무슨 색인지" 를 보여주는 그림일 뿐이다.

	원판을 어떻게 그리는가
	  로블록스 UI 에는 원형 그라디언트가 없다. 그래서 중심에서 바깥으로 뻗는
	  가늘고 긴 직사각형(살)을 빙 둘러 세워서 원판처럼 보이게 만든다.
	  살 하나하나는 자기 색상(Hue)을 갖고, 중심 쪽이 흰색이 되도록
	  UIGradient 를 세로로 넣는다. 그러면 진하기까지 한 번에 표현된다.

	⚠️ 함정: Rotation 은 AnchorPoint 가 아니라 **객체 자신의 한가운데**를 축으로 돈다.
	  살의 아래쪽 끝을 원판 중심에 못박고 돌리면 될 것 같지만 그렇게 되지 않는다.
	  살들이 각자 제자리에서 돌기만 해서 중심에서 벗어난 곳에 뭉쳐버린다.
	  그래서 회전시키기 전에 **살의 한가운데를 미리 제자리에 갖다 놓아야** 한다.

	  살의 폭을 "바깥 둘레 ÷ 살 개수" 로 잡는 이유:
	  가장 벌어지는 바깥쪽에서 살끼리 딱 닿게 하려는 것이다.
	  안쪽은 자연히 겹치므로 빈틈이 생기지 않는다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local ColorWheel = {}
ColorWheel.__index = ColorWheel

--------------------------------------------------------------------
-- 좌표 ↔ 색 변환 (인스턴스와 무관한 순수 계산)
--------------------------------------------------------------------

-- 원판 중심을 기준으로 한 상대 좌표 → 색상(0~1), 진하기(0~1)
--
-- 화면 좌표는 아래로 갈수록 y 가 커진다. 그래서 "위쪽" 은 -y 방향이다.
-- atan2(dx, -dy) 로 재면 위쪽이 0 이고 시계 방향으로 각이 커진다.
-- 살을 세울 때 쓴 Rotation 과 방향을 맞춰야 눌린 자리와 보이는 색이 일치한다.
local function positionToHueSaturation(dx: number, dy: number, radius: number): (number, number)
	local angle = math.atan2(dx, -dy)
	-- atan2 는 -π ~ π 를 준다. % 1 로 0~1 범위로 접는다.
	local hue = (angle / (2 * math.pi)) % 1
	local saturation = math.clamp(math.sqrt(dx * dx + dy * dy) / radius, 0, 1)
	return hue, saturation
end

-- 위의 반대. 색상/진하기 → 원판 위 위치 (0~1 비율)
local function hueSaturationToScale(hue: number, saturation: number): (number, number)
	local angle = hue * 2 * math.pi
	-- 반지름은 원판 폭의 절반이므로, 비율로 따지면 saturation * 0.5 만큼 떨어진 곳이다.
	local offset = saturation * 0.5
	return 0.5 + math.sin(angle) * offset, 0.5 - math.cos(angle) * offset
end

--------------------------------------------------------------------
-- 만들기
--------------------------------------------------------------------

function ColorWheel.new(opts: {
	name: string,
	parent: Instance,
	layoutOrder: number?,
	onChanged: (Color3) -> (),
})
	local self = setmetatable({}, ColorWheel)
	self.onChanged = opts.onChanged

	-- 시작 색은 검정. 검정은 밝기 0 이라 색상/진하기가 의미가 없어서
	-- 원판 표시는 빨강(0도) 자리에 둔다.
	self.hue = 0
	self.saturation = 0
	self.value = 0

	local wheelSize = UI.COLOR_WHEEL_SIZE
	local barWidth = UI.COLOR_WHEEL_BAR_WIDTH
	local gap = UI.COLOR_WHEEL_GAP

	-- 원판과 막대를 묶어서 패널 가운데에 놓는다.
	local group = Instance.new("Frame")
	group.Name = opts.name
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromOffset(wheelSize + gap + barWidth, wheelSize)
	group.AnchorPoint = Vector2.new(0.5, 0)
	group.Position = UDim2.fromScale(0.5, 0)
	group.LayoutOrder = opts.layoutOrder or 1
	group.Parent = opts.parent
	self.instance = group

	self:_buildWheel(group, wheelSize)
	self:_buildValueBar(group, barWidth)

	self:_refresh()

	return self
end

function ColorWheel:_buildWheel(parent: Instance, size: number)
	local radius = size / 2

	local wheel = Instance.new("Frame")
	wheel.Name = "Wheel"
	wheel.Size = UDim2.fromOffset(size, size)
	wheel.BackgroundTransparency = 1
	-- 살의 네 귀퉁이가 원 밖으로 아주 조금 삐져나오는 것을 잘라낸다.
	wheel.ClipsDescendants = true
	wheel.Parent = parent
	self.wheel = wheel
	self.wheelRadius = radius

	-- CornerRadius 를 Scale 1 로 주면 짧은 변 기준 완전한 원이 된다.
	UIHelper.corner(wheel, radius)

	local spokeCount = UI.COLOR_WHEEL_SPOKES
	-- 바깥 둘레를 살 개수로 나눈 값이 "바깥에서 살끼리 닿는 폭" 이다.
	-- +1 은 반올림 때문에 실오라기 같은 틈이 생기는 걸 막는 여유분.
	local spokeWidth = math.ceil(2 * math.pi * radius / spokeCount) + 1

	for index = 0, spokeCount - 1 do
		local hue = index / spokeCount
		local edgeColor = Color3.fromHSV(hue, 1, 1)

		local angle = hue * 2 * math.pi

		local spoke = Instance.new("Frame")
		spoke.Name = "Spoke"
		spoke.Size = UDim2.fromOffset(spokeWidth, radius)
		-- Rotation 이 살의 한가운데를 축으로 돌기 때문에(위 함정 참고),
		-- 살의 한가운데를 "중심에서 반지름의 절반만큼 떨어진 곳" 에 먼저 놓는다.
		-- 그래야 돌리고 나면 중심에서 바깥까지 정확히 이어진다.
		-- 원판 폭이 radius*2 이므로, radius/2 는 비율로 0.25 다.
		spoke.AnchorPoint = Vector2.new(0.5, 0.5)
		spoke.Position = UDim2.fromScale(
			0.5 + math.sin(angle) * 0.25,
			0.5 - math.cos(angle) * 0.25
		)
		spoke.Rotation = hue * 360
		spoke.BackgroundColor3 = edgeColor
		spoke.BorderSizePixel = 0
		spoke.Parent = wheel

		-- 살의 위쪽 끝이 원판 바깥, 아래쪽 끝이 중심이다.
		-- Rotation 90 이면 그라디언트가 위에서 아래로 흐른다.
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, edgeColor), -- 바깥: 진한 색
			ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)), -- 중심: 흰색
		})
		gradient.Parent = spoke
	end

	-- 원판은 밝기와 상관없이 항상 밝게 둔다.
	-- 검은 판을 덮어 어둡게 만들 수도 있지만, 그러면 시작할 때(검정 = 밝기 0)
	-- 원판이 새까맣게 나와서 고장난 것처럼 보인다. 참고 화면의 색상환도 늘 밝다.
	-- 지금 고른 색이 실제로 어떤지는 위의 미리보기 띠와 아래 표시 동그라미가 알려준다.

	-- 지금 고른 자리를 알려주는 작은 동그라미
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.Size = UDim2.fromOffset(16, 16)
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	-- 속을 고른 색으로 채운다. 원판이 늘 밝게 유지되므로
	-- 밝기를 낮췄을 때 그 사실이 보이는 곳이 여기다.
	marker.BackgroundTransparency = 0
	marker.ZIndex = 3
	marker.Parent = wheel
	UIHelper.corner(marker, 8)
	UIHelper.stroke(marker, Color3.new(1, 1, 1), 3)
	self.marker = marker

	self:_bindDrag(wheel, function(x, y)
		local center = wheel.AbsolutePosition + wheel.AbsoluteSize / 2
		local hue, saturation = positionToHueSaturation(
			x - center.X,
			y - center.Y,
			wheel.AbsoluteSize.X / 2
		)
		self.hue = hue
		self.saturation = saturation
		self:_refresh()
		self.onChanged(self:GetColor())
	end)
end

function ColorWheel:_buildValueBar(parent: Instance, width: number)
	local bar = Instance.new("Frame")
	bar.Name = "ValueBar"
	bar.Size = UDim2.new(0, width, 1, 0)
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Position = UDim2.fromScale(1, 0)
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = parent
	self.valueBar = bar
	UIHelper.corner(bar, width // 2)
	UIHelper.stroke(bar)

	-- 위가 가장 밝고 아래가 검정. 위쪽 색은 지금 고른 색상/진하기를 따라간다.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = bar
	self.valueGradient = gradient

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.new(1, 8, 0, 10)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = bar
	UIHelper.corner(knob, 5)
	UIHelper.stroke(knob, Color3.fromRGB(120, 123, 135), 2)
	self.valueKnob = knob

	self:_bindDrag(bar, function(_, y)
		local top = bar.AbsolutePosition.Y
		local height = bar.AbsoluteSize.Y
		if height <= 0 then
			return
		end
		-- 위쪽이 밝으므로 아래로 갈수록 값이 작아진다. 그래서 1 에서 뺀다.
		self.value = 1 - math.clamp((y - top) / height, 0, 1)
		self:_refresh()
		self.onChanged(self:GetColor())
	end)
end

-- 누르고 끄는 동안 계속 값을 받는 공통 처리.
-- 원판과 밝기 막대가 완전히 같은 방식이라 한 번만 만들어 둘이 나눠 쓴다.
function ColorWheel:_bindDrag(target: GuiObject, apply: (number, number) -> ())
	local dragging = false

	target.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		apply(input.Position.X, input.Position.Y)
	end)

	-- 손가락이 원판 밖으로 나가도 계속 따라오게 하려면 전역 입력을 들어야 한다.
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		apply(input.Position.X, input.Position.Y)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

--------------------------------------------------------------------
-- 표시 갱신
--------------------------------------------------------------------

function ColorWheel:_refresh()
	local x, y = hueSaturationToScale(self.hue, self.saturation)
	self.marker.Position = UDim2.fromScale(x, y)
	self.marker.BackgroundColor3 = self:GetColor()

	-- 밝기 막대의 위쪽 색은 "지금 색상·진하기에서 가장 밝은 색" 이다.
	self.valueGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHSV(self.hue, self.saturation, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
	})
	self.valueKnob.Position = UDim2.fromScale(0.5, 1 - self.value)
end

function ColorWheel:GetColor(): Color3
	return Color3.fromHSV(self.hue, self.saturation, self.value)
end

-- 바깥(팔레트 클릭, 스포이드)에서 색이 정해졌을 때 원판을 그 색에 맞춘다.
-- onChanged 는 부르지 않는다. 안 그러면 색 → 원판 → 색 으로 되먹임이 돈다.
function ColorWheel:SetColor(color: Color3)
	local h, s, v = color:ToHSV()
	self.hue = h
	self.saturation = s
	self.value = v
	self:_refresh()
end

return ColorWheel
