--!strict
--[[
	Layout.lua  —  화면 크기에 맞는 배치값 계산

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	하는 일은 딱 하나다. **화면 크기를 넣으면 배치값이 나온다.**
	인스턴스를 만들지도, 건드리지도 않는다.
	그래서 "폰에서 얼마나 줄어드나" 를 확인할 때 이 파일만 보면 된다.

	왜 필요한가
	  1.5단계 UI 는 데스크탑 해상도에서만 성립했다. (README §3.5)
	  캔버스는 Scale 로 잡아서 잘 줄어들었지만 주변 UI 는 전부 고정 픽셀이라,
	  폰 세로에서는 색상 패널이 캔버스를 통째로 덮어 그림이 아예 안 보였다.

	두 가지 장치로 푼다.
	  1) 배율(scale)  — 화면이 기준 크기보다 작으면 그 비율만큼 UI 를 줄인다.
	  2) 접이식(compact) — 화면이 좁으면 색상 패널을 늘 펼쳐두지 않고 서랍으로 접는다.

	그리고 캔버스를 "화면 한가운데" 가 아니라 **"UI 를 뺀 나머지 한가운데"** 에 놓는다.
	이게 사실 1.5단계의 진짜 버그였다. 화면 기준으로 가운데를 잡으니
	태블릿에서도 왼쪽 패널이 캔버스를 100px 쯤 가리고 있었다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UI = Config.UI

local Layout = {}

export type Result = {
	scale: number, -- UI 를 얼마로 줄일 것인가 (1 = 그대로)
	compact: boolean, -- 색상 패널을 서랍으로 접을 것인가
	left: number, -- 캔버스가 쓸 수 있는 영역의 여백 (픽셀)
	sideRight: number, -- 오른쪽 세로줄이 있을 때의 오른쪽 여백
	right: number,
	top: number,
	bottom: number,
}

-- 툴바의 실제 높이. 버튼 크기에 위아래 안쪽 여백(8+8)을 더한 값이다.
-- Toolbar.lua 가 같은 계산을 하므로 값이 어긋나지 않게 여기에 이름을 붙여둔다.
local TOOLBAR_PADDING = 8

function Layout.compute(viewport: Vector2): Result
	-- 가로와 세로 중 더 빡빡한 쪽에 맞춘다.
	-- 한쪽만 보면 폰 가로(852x393)처럼 납작한 화면에서 세로가 넘쳐버린다.
	local raw = math.min(
		viewport.X / UI.REFERENCE_WIDTH,
		viewport.Y / UI.REFERENCE_HEIGHT
	)
	-- 아래로는 한계를 둔다. 더 줄이면 손가락으로 누를 수 없어진다.
	-- 위로도 1 을 넘기지 않는다. 큰 모니터에서 버튼만 커지면 우스워진다.
	local scale = math.clamp(raw, UI.MIN_UI_SCALE, 1)

	-- 색상 패널을 왼쪽에 늘 펼쳐둘 만큼 넓은가.
	-- 좁으면 서랍으로 접고, 캔버스가 화면을 다 쓰게 한다.
	local compact = viewport.X < UI.WIDE_LAYOUT_MIN_WIDTH

	local gap = UI.CANVAS_GAP * scale

	-- 패널 바깥 여백은 줄이지 않는다. 화면 가장자리에서 띄우는 거리라
	-- 배율과 상관없이 일정한 편이 보기 좋다.
	local dockedPanel = UI.COLOR_PANEL_MARGIN + UI.COLOR_PANEL_WIDTH * scale + gap
	-- 관전 목록이 펼쳐졌을 때 아래쪽에 비켜줘야 할 높이.
	-- 관전 줄의 높이는 별 줄이 붙었는지에 따라 달라진다.
	-- 어림값으로 잡으면 어긋나므로, 쓰는 쪽에서 실제 크기를 재서 쓴다.

	local toolbarHeight = (UI.TOOL_BUTTON_SIZE + TOOLBAR_PADDING * 2) * scale
	-- 위쪽을 쓰는 것은 상단 바(주제/제출/시간) 하나뿐이다.
	-- 되돌리기 줄은 오른쪽 세로줄로 옮겨서 위쪽 자리를 안 쓴다.
	local topBarHeight = (UI.TOP_BAR_HEIGHT + UI.TOP_BAR_MARGIN) * scale
	-- 오른쪽 세로줄 자리. 가장 넓은 버튼(팔레트/눈) 기준.
	local sideWidth = UI.SIDE_BAR_MARGIN + UI.PANEL_TOGGLE_SIZE * scale + gap

	return {
		scale = scale,
		compact = compact,
		-- 접었으면 패널이 캔버스 위에 잠깐 떴다 사라지므로 자리를 비워둘 필요가 없다.
		left = if compact then gap else dockedPanel,
		-- 관전 목록이 펼쳐졌을 때의 아래쪽 여백. 쓰는 쪽에서 골라 쓴다.
		right = gap,
		top = topBarHeight + gap,
		sideRight = sideWidth,
		bottom = toolbarHeight + UI.TOOLBAR_BOTTOM_MARGIN * scale + gap,
	}
end

-- 위 계산이 실제로 들어맞는지 눈으로 확인할 때 쓴다.
-- 기기 크기를 넣으면 캔버스가 몇 픽셀이 되는지 출력한다.
--   require(...Layout).Debug(Vector2.new(852, 393))
function Layout.Debug(viewport: Vector2)
	local result = Layout.compute(viewport)
	local width = viewport.X - result.left - result.right
	local height = viewport.Y - result.top - result.bottom
	print(string.format(
		"[Layout] %dx%d -> scale %.2f, %s, canvas %d px",
		viewport.X, viewport.Y, result.scale,
		if result.compact then "compact" else "wide",
		math.min(width, height)
	))
end

return Layout
