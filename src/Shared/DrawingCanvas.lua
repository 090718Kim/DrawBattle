--!strict
--[[
	DrawingCanvas.lua  —  스트로크 기반 그림판 코어

	배치 위치: ReplicatedStorage.Shared 안의 ModuleScript.
	(나중에 관전자도 같은 모듈로 그림을 재생하므로 Shared 가 맞다)

	쓰는 법:
		local canvas = DrawingCanvas.new(someImageLabel)
		canvas:SetTool("pen")
		canvas:SetColor(Color3.fromRGB(255, 0, 0))
		canvas:SetThickness(8)

	핵심 개념 ─ 픽셀이 아니라 "스트로크"를 저장한다.
	  스트로크 1개 = { tool, color, thickness, transparency, points = {Vector2, ...} }
	  이렇게 하면 (1) 네트워크로 보내기 가볍고 (2) 되돌리기가 공짜고
	  (3) 신고당한 그림을 나중에 그대로 재생할 수 있다.

	렌더링 방식이 두 가지인 이유
	  EditableImage 는 'Allow Mesh / Image APIs' 설정이 켜져 있어야 쓸 수 있다.
	  이 설정은 **경험(experience) 단위**이고, 켜는 데 신원 인증(ID verified)이
	  필요한 쪽은 **개발자 계정**이다. 한 번 켜두면 게임에 들어오는 플레이어는
	  아무 조건이 없다. 즉 대비해야 할 상황은 "플레이어가 못 쓴다" 가 아니라
	  "개발자가 그 스위치를 못 켠다" 쪽이다. 그래서 두 가지 방식을 준비한다.

	    "image" 모드 — EditableImage 에 픽셀을 직접 찍는다. 빠르고 가볍다.
	    "frame"  모드 — 선분 1개당 둥근 Frame 1개를 눕혀서 선을 만든다.
	                    권한이 전혀 필요 없다. 대신 Instance 가 많이 생긴다.

	  스트로크 데이터 구조는 두 모드가 완전히 똑같다. 그래서 나중에 설정을
	  켜게 되면 렌더링만 바뀌고 저장/전송/되돌리기 코드는 하나도 안 바뀐다.

	도구를 "그리는 방법" 이 아니라 "점을 선분으로 바꾸는 규칙" 으로 다룬다.
	  segmentsOf(stroke) 하나가 펜이든 직선이든 전부 선분 목록으로 바꾼다.
	  덕분에 실제로 찍는 코드(_stampSegment)는 도구가 몇 개로 늘어나든 그대로다.
]]

local AssetService = game:GetService("AssetService")
local UserInputService = game:GetService("UserInputService")

local Config = require(script.Parent.Config)

-- 예전에는 이 값들을 이 파일 안에 따로 적어뒀었다.
-- Config 에 같은 값이 또 있어서 "Config 만 고쳤는데 아무 일도 안 일어나는" 함정이었다.
-- 이제 출처는 Config 하나뿐이다. (README §7-3)
local CANVAS_SIZE = Config.CANVAS_SIZE
local MIN_POINT_DISTANCE = Config.MIN_POINT_DISTANCE
local MAX_POINTS_PER_STROKE = Config.MAX_POINTS_PER_STROKE
local PAPER_COLOR = Config.CANVAS_BACKGROUND_COLOR

-- 손이 움직이는 대로 점이 쌓이는 도구들. 나머지는 시작점과 끝점 두 개만 쓴다.
local FREEHAND_TOOLS: { [string]: boolean } = {
	pen = true,
	brush = true,
	eraser = true,
}

export type Stroke = {
	tool: string,
	color: Color3,
	thickness: number,
	transparency: number,
	points: { Vector2 },
}

local DrawingCanvas = {}
DrawingCanvas.__index = DrawingCanvas

--------------------------------------------------------------------
-- 순수 계산 함수들 (인스턴스와 무관)
--------------------------------------------------------------------

-- 점 p 에서 선분 ab 까지의 최단 거리. 스포이드가 "이 선을 찍었나" 를 판단할 때 쓴다.
local function distanceToSegment(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local lengthSquared = ab.X * ab.X + ab.Y * ab.Y
	if lengthSquared <= 0 then
		return (p - a).Magnitude -- a 와 b 가 같은 점인 경우
	end
	local ap = p - a
	-- 선분 위에서 가장 가까운 지점을 0~1 로 구한다. clamp 가 "선분 밖으로 안 나가게" 한다.
	local t = math.clamp((ap.X * ab.X + ap.Y * ab.Y) / lengthSquared, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

-- 저장된 스트로크가 "실제로 화면에 어떤 색/굵기로 나가는가".
--
-- 저장값과 표시값을 나누는 이유: 지우개는 색을 안 고르고 그리는데
-- 저장할 때 종이색을 박아버리면 나중에 종이색을 바꿨을 때 옛날 그림이 깨진다.
-- 그래서 저장은 "지우개였다" 만 하고, 색은 그릴 때 정한다.
local function renderParams(stroke: Stroke): (Color3, number, number)
	local color = stroke.color
	local thickness = stroke.thickness
	local transparency = stroke.transparency or 0

	if stroke.tool == "brush" then
		thickness = thickness * Config.BRUSH_THICKNESS_MULTIPLIER
		transparency = math.clamp(transparency + Config.BRUSH_EXTRA_TRANSPARENCY, 0, 1)
	elseif stroke.tool == "eraser" then
		color = PAPER_COLOR
		-- 지우개가 반투명하면 밑에 있는 선이 비쳐서 안 지워진 것처럼 보인다.
		transparency = 0
	end

	return color, thickness, transparency
end

-- 스트로크의 점들을 "그려야 할 선분 목록" 으로 바꾼다.
-- 도구가 늘어나면 여기에만 분기를 추가하면 된다.
local function segmentsOf(stroke: Stroke): { { Vector2 } }
	local points = stroke.points
	local segments = {}
	if #points == 0 then
		return segments
	end

	if FREEHAND_TOOLS[stroke.tool] then
		if #points == 1 then
			-- 점 하나만 찍고 뗀 경우 (탭). 길이 0 짜리 선분으로 두면 동그라미가 찍힌다.
			table.insert(segments, { points[1], points[1] })
		else
			for i = 1, #points - 1 do
				table.insert(segments, { points[i], points[i + 1] })
			end
		end
		return segments
	end

	-- 여기부터는 시작점과 끝점만 쓰는 도구다.
	local a = points[1]
	local b = points[#points]

	if stroke.tool == "line" then
		table.insert(segments, { a, b })
	end

	return segments
end

--------------------------------------------------------------------
-- 생성
--------------------------------------------------------------------

function DrawingCanvas.new(imageLabel: ImageLabel)
	local self = setmetatable({}, DrawingCanvas)

	self.imageLabel = imageLabel

	self.strokes = {} :: { Stroke }
	self.redoStack = {} :: { Stroke }
	self.currentStroke = nil :: Stroke?
	self.lastPoint = nil :: Vector2?

	-- 전체지우기를 되돌릴 수 있게 직전 상태를 한 번만 보관한다.
	-- 휴지통을 잘못 누르는 일이 실제로 자주 일어나기 때문이다.
	self.clearedSnapshot = nil :: { Stroke }?

	self.tool = Config.DEFAULT_TOOL
	self.color = Config.DEFAULT_COLOR
	self.thickness = Config.DEFAULT_THICKNESS
	self.eraserThickness = Config.DEFAULT_ERASER_THICKNESS
	self.transparency = Config.DEFAULT_TRANSPARENCY
	self.enabled = true

	-- 스트로크가 끝났을 때 호출됨. 나중에 여기에 서버 전송을 붙이면 멀티플레이가 된다.
	self.onStrokeFinished = nil :: ((Stroke) -> ())?
	-- 되돌리기/다시하기 버튼을 켜고 끄기 위해 UI 가 구독한다.
	self.onHistoryChanged = nil :: (() -> ())?
	-- 스포이드로 색을 집었을 때. UI 가 현재 색 표시를 바꿔야 하므로 알려준다.
	self.onColorPicked = nil :: ((Color3) -> ())?

	-- 종이부터 깐다. 어느 렌더링 방식을 쓰든 공통이다.
	self:_setupPaper()

	-- 어느 방식으로 그릴지 정한다.
	-- Config.FORCE_RENDER_MODE 가 "frame" 이면 EditableImage 를 아예 시도하지 않는다.
	-- (and 는 앞이 false 면 뒤를 실행하지 않으므로 시도 자체가 건너뛰어진다)
	local forced = Config.FORCE_RENDER_MODE
	local useImage = forced ~= "frame" and self:_trySetupImageMode()

	if useImage then
		self.mode = "image"
	else
		self.mode = "frame"
		self:_setupFrameMode()
		if forced == "frame" then
			-- 일부러 고른 것이므로 경고가 아니다.
			print("[DrawingCanvas] Frame mode forced by Config.FORCE_RENDER_MODE.")
		else
			warn("[DrawingCanvas] EditableImage is unavailable, falling back to Frame mode. "
				.. "To make it lighter, enable 'Allow Mesh / Image APIs' in "
				.. "File > Game Settings > Security (requires an ID-verified account).")
		end
	end
	print("[DrawingCanvas] render mode =", self.mode)

	self:_setupPreviewLayer()
	self:_setupCursorLayer()
	self:Clear()
	self:_bindInput()

	return self
end

-- 캔버스 자체를 종이로 만든다.
--
-- ⚠️ 이걸 두 방식 공통으로 두는 것이 중요하다.
--    image 방식에서는 그림을 EditableImage 가 그리므로 ImageLabel 배경은
--    필요 없어 보이지만, 그림 픽셀의 투명도가 조금이라도 있으면
--    그 자리에 아무것도 없어서 **3D 맵이 그대로 비쳐 보인다.**
--    (브러시는 일부러 살짝 투명하게 긋기 때문에 반드시 겪는 문제다)
--    ImageLabel 배경을 종이색으로 깔아두면 뒤를 받쳐줘서 그런 일이 없다.
function DrawingCanvas:_setupPaper()
	local label = self.imageLabel
	label.BackgroundColor3 = PAPER_COLOR
	label.BackgroundTransparency = 0
	-- 선과 미리보기가 캔버스 밖으로 삐져나가지 않게 잘라낸다.
	label.ClipsDescendants = true
end

-- EditableImage 방식 준비. 성공하면 true.
--
-- 주의: CreateEditableImage 가 성공했다고 쓸 수 있는 게 아니다.
-- 권한 검사는 객체를 만들 때가 아니라 **픽셀을 실제로 그릴 때** 걸린다.
-- 그래서 생성 결과만 보고 판단하면 안 되고, 아래에서 한 번 그려봐야 한다.
function DrawingCanvas:_trySetupImageMode(): boolean
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({
			Size = Vector2.new(CANVAS_SIZE, CANVAS_SIZE),
		})
	end)
	if not ok or image == nil then
		return false
	end

	local okContent = pcall(function()
		self.imageLabel.ImageContent = Content.fromObject(image)
	end)
	if not okContent then
		return false
	end

	-- 진짜 검사. 여기서 "EditableImage is not accessible" 가 터진다.
	local okDraw = pcall(function()
		image:DrawRectangle(
			Vector2.zero,
			Vector2.new(CANVAS_SIZE, CANVAS_SIZE),
			PAPER_COLOR,
			0,
			Enum.ImageCombineType.Overwrite
		)
	end)
	if not okDraw then
		-- 못 쓰는 이미지를 붙여두면 화면에 빈 칸으로 남으므로 떼어낸다.
		self.imageLabel.ImageContent = Content.none
		return false
	end

	self.image = image
	return true
end

-- Frame 방식 준비. ImageLabel 자체를 도화지로 쓴다.
function DrawingCanvas:_setupFrameMode()
	local label = self.imageLabel

	-- 종이는 _setupPaper 가 이미 깔아뒀다. 여기서는 못 쓰는 이미지를 떼기만 한다.
	label.ImageContent = Content.none

	-- 선들을 따로 담아두면 :Clear() 가 ClearAllChildren() 한 줄로 끝난다.
	-- (ImageLabel 에 직접 붙이면 나중에 추가할 UI 까지 같이 지워진다)
	local container = Instance.new("Frame")
	container.Name = "Strokes"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = label

	self.strokeContainer = container
end

-- 직선/도형을 끄는 동안 보여줄 "미리보기" 판.
--
-- 미리보기를 캔버스에 직접 그리면 마우스가 움직일 때마다 지웠다 다시 그려야 하는데,
-- image 모드에서는 그게 512x512 를 매 프레임 다시 칠하는 일이라 너무 무겁다.
-- 그래서 미리보기는 항상 별도의 투명한 판 위에 Frame 으로만 그리고,
-- 손을 뗄 때 진짜 캔버스에 한 번만 옮겨 그린다. 두 모드에서 코드가 같아지는 이점도 있다.
function DrawingCanvas:_setupPreviewLayer()
	local layer = Instance.new("Frame")
	layer.Name = "Preview"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	-- 스트로크 위에 떠야 하므로 ZIndex 를 올린다.
	layer.ZIndex = 5
	layer.Parent = self.imageLabel

	self.previewLayer = layer
end

-- 캔버스 위에서 마우스를 따라다니는 동그라미. 그림판 앱의 그 커서다.
--
-- 왜 필요한가: 지금 붓이 얼마나 굵은지, 어디가 지워질지를
-- 긋기 전에 알 수 있어야 한다. 굵기 슬라이더를 끌 때도 이걸 보고 맞추게 된다.
--
-- 흰 테두리 안에 어두운 테두리를 겹쳐 두 겹으로 만든다.
-- 한 겹이면 비슷한 밝기의 그림 위에서 사라져 버린다.
-- (UIStroke 는 한 인스턴스에 하나만 먹으므로 Frame 을 두 개 겹친다)
--
-- 크기를 Offset(픽셀)이 아니라 Scale 로 주는 이유:
-- 창 크기가 바뀌어 캔버스가 커지거나 작아져도 실제로 그려지는 굵기와
-- 동그라미가 저절로 같이 움직인다. 다시 계산해줄 필요가 없다.
function DrawingCanvas:_setupCursorLayer()
	local cursor = Instance.new("Frame")
	cursor.Name = "Cursor"
	cursor.AnchorPoint = Vector2.new(0.5, 0.5)
	cursor.BackgroundColor3 = Color3.new(1, 1, 1)
	cursor.BackgroundTransparency = 1
	cursor.BorderSizePixel = 0
	cursor.ZIndex = 6
	cursor.Visible = false
	cursor.Parent = self.imageLabel

	-- CornerRadius 를 Scale 1 로 주면 정확한 원이 된다.
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = cursor

	local outerStroke = Instance.new("UIStroke")
	outerStroke.Color = Color3.new(1, 1, 1)
	outerStroke.Thickness = 3
	outerStroke.Parent = cursor

	-- 흰 테두리 바로 안쪽에 어두운 테두리를 하나 더 두른다.
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -3, 1, -3)
	inner.BackgroundTransparency = 1
	inner.BorderSizePixel = 0
	inner.ZIndex = 6
	inner.Parent = cursor

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(1, 0)
	innerCorner.Parent = inner

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = Color3.fromRGB(40, 42, 52)
	innerStroke.Thickness = 1.5
	innerStroke.Parent = inner

	self.cursor = cursor
	-- 지금 포인터를 감춘 상태인지 기억해둔다.
	-- 마우스가 움직일 때마다 MouseIcon 을 다시 쓰지 않기 위한 것이다.
	self.cursorShown = false
	self:_updateCursorSize()
end

-- 지금 도구가 그릴 굵기. 그게 곧 동그라미의 지름이다.
function DrawingCanvas:_cursorThickness(): number
	local thickness
	if self.tool == "eraser" then
		thickness = self.eraserThickness
	elseif self.tool == "eyedropper" then
		-- 스포이드는 굵기가 없다. 집는 자리만 가리키면 되므로 작게 고정한다.
		thickness = Config.EYEDROPPER_CURSOR_SIZE
	elseif self.tool == "brush" then
		thickness = self.thickness * Config.BRUSH_THICKNESS_MULTIPLIER
	else
		thickness = self.thickness
	end
	-- 너무 얇으면 동그라미가 점이 되어 안 보인다.
	return math.max(thickness, Config.MIN_CURSOR_SIZE)
end

function DrawingCanvas:_updateCursorSize()
	local scale = self:_cursorThickness() / CANVAS_SIZE
	self.cursor.Size = UDim2.fromScale(scale, scale)

	-- 지우개일 때만 속을 옅게 채운다. 어느 범위가 지워지는지 면으로 보여주려는 것이다.
	self.cursor.BackgroundTransparency = if self.tool == "eraser" then 0.75 else 1
end

function DrawingCanvas:_moveCursor(point: Vector2)
	self.cursor.Position = UDim2.fromScale(point.X / CANVAS_SIZE, point.Y / CANVAS_SIZE)
end

-- 동그라미를 켜고 끈다. 진짜 마우스 포인터를 감추는 일도 같이 한다.
--
-- ⚠️ 포인터를 감추는 것은 **그릴 자격이 있는 사람에게만** 해당한다.
--    enabled 가 false 인 사람(2단계의 관전자)은 평소 포인터를 그대로 쓴다.
--    별점을 매기려면 버튼을 눌러야 하는데 포인터가 없으면 곤란하기 때문이다.
--
-- ⚠️ 캔버스를 벗어나거나 그리기가 잠기면 **반드시** 되돌려야 한다.
--    포인터가 사라진 채로 남으면 화면의 다른 버튼을 아예 못 누른다.
function DrawingCanvas:_setCursorVisible(visible: boolean)
	local show = visible and self.enabled
	if show == self.cursorShown then
		return -- 값이 그대로면 아무것도 하지 않는다 (마우스는 1초에 수십 번 움직인다)
	end
	self.cursorShown = show

	self.cursor.Visible = show
	-- MouseIcon 에 빈 그림을 넣는 방법은 PC 에서 포인터가 그대로 남았다.
	-- MouseIconEnabled 는 포인터 자체를 끄는 것이라 확실하다.
	UserInputService.MouseIconEnabled = not show
end

--------------------------------------------------------------------
-- 설정
--------------------------------------------------------------------

function DrawingCanvas:SetTool(tool: string)
	-- 도구를 바꾸는 순간 그리던 선은 끝난 것으로 친다.
	self:_endStroke()
	self.tool = tool
	-- 도구마다 굵기가 다르므로 동그라미 크기도 따라 바뀐다.
	self:_updateCursorSize()
end

function DrawingCanvas:GetTool(): string
	return self.tool
end

function DrawingCanvas:SetColor(color: Color3)
	self.color = color
end

function DrawingCanvas:GetColor(): Color3
	return self.color
end

function DrawingCanvas:SetThickness(thickness: number)
	self.thickness = math.clamp(thickness, Config.MIN_THICKNESS, Config.MAX_THICKNESS)
	-- 굵기를 끄는 동안 동그라미도 같이 커져야 얼마나 굵어졌는지 보인다.
	self:_updateCursorSize()
end

function DrawingCanvas:SetEraserThickness(thickness: number)
	self.eraserThickness =
		math.clamp(thickness, Config.MIN_ERASER_THICKNESS, Config.MAX_ERASER_THICKNESS)
	self:_updateCursorSize()
end

function DrawingCanvas:SetTransparency(transparency: number)
	self.transparency = math.clamp(transparency, 0, 1)
end

-- 그리기 잠금/해제 (라운드 시작·종료 때 쓸 것)
--
-- ⚠️ 이건 클라이언트 편의 기능일 뿐이다. 익스플로잇으로 우회된다.
--    서버는 스트로크를 받을 때마다 자격을 다시 검사해야 한다. (README §3.4)
function DrawingCanvas:SetEnabled(enabled: boolean)
	self.enabled = enabled
	if not enabled then
		-- ⚠️ 포인터를 **먼저** 돌려준다.
		--    _endStroke 는 그리던 선을 마무리하면서 서버로 보내기까지 한다.
		--    그쪽에서 실패하면 뒤에 있는 줄에는 영영 도달하지 못한다.
		--    그러면 마우스 포인터가 사라진 채로 남고, 사용자가 되돌릴 방법이 없다.
		--    (제출 버튼을 누를 때 실제로 그렇게 됐다)
		self:_setCursorVisible(false)
		self:_endStroke()
	end
end

-- 마우스 포인터를 **무조건** 되돌린다.
--
-- 경고창처럼 그림판 밖의 UI 를 쓸 때 부른다.
-- 상태를 따지지 않고 그냥 되돌리는 것이 핵심이다.
-- 상태를 보고 판단하면, 그 상태가 어긋나 있을 때 영영 안 돌아온다.
function DrawingCanvas:ShowPointer()
	self.cursorShown = false
	self.cursor.Visible = false
	UserInputService.MouseIconEnabled = true
end

-- 지금 상태에 맞게 포인터와 동그라미를 다시 맞춘다.
--
-- MouseIconEnabled 는 게임 전체에 하나뿐인 값이다.
-- 한 번 어긋나면 마우스가 사라진 채로 남고, 사용자가 되돌릴 길이 없다.
-- 바깥에서 주기적으로 불러 어긋남을 조용히 바로잡는다.
function DrawingCanvas:RefreshCursor()
	local show = self.cursorShown == true and self.enabled == true
	self.cursorShown = show
	self.cursor.Visible = show
	UserInputService.MouseIconEnabled = not show
end

--------------------------------------------------------------------
-- 그리기 (저수준)
--------------------------------------------------------------------

-- 화면에 그려진 것만 지운다. 스트로크 데이터는 건드리지 않는다.
-- (Redraw 가 이걸 재사용하기 때문에 Clear 와 분리해 둔다)
function DrawingCanvas:_clearSurface()
	if self.mode == "image" then
		self.image:DrawRectangle(
			Vector2.zero,
			Vector2.new(CANVAS_SIZE, CANVAS_SIZE),
			PAPER_COLOR,
			0,
			Enum.ImageCombineType.Overwrite
		)
	else
		self.strokeContainer:ClearAllChildren()
	end
end

-- 캔버스를 비운다 (그림 + 데이터 전부). 되돌리기 한 번으로 복구할 수 있다.
function DrawingCanvas:Clear()
	if self.strokes and #self.strokes > 0 then
		self.clearedSnapshot = self.strokes
	end
	self:_clearSurface()
	self:_clearPreview()
	self.strokes = {}
	self.currentStroke = nil
	self.lastPoint = nil
	self:_notifyHistoryChanged()
end

-- 선분 하나를 캔버스에 그린다. 모드에 따라 방법이 갈린다.
function DrawingCanvas:_stampSegment(
	from: Vector2,
	to: Vector2,
	color: Color3,
	thickness: number,
	transparency: number
)
	if self.mode == "image" then
		self:_stampSegmentImage(from, to, color, thickness, transparency)
	else
		self:_stampSegmentFrame(from, to, color, thickness, transparency, self.strokeContainer)
	end
end

-- [frame 방식] 선분 1개당 둥근 Frame 1개를 각도만큼 눕힌다.
-- 캔버스가 정사각형이라 Scale 로만 배치해도 가로세로 비율이 안 망가진다.
-- 덕분에 Rotation 을 써도 선 굵기가 찌그러지지 않는다.
--
-- 미리보기도 이 함수를 쓰기 때문에 parent 를 받는다.
-- (image 모드에서도 미리보기만큼은 Frame 으로 그린다)
function DrawingCanvas:_stampSegmentFrame(
	from: Vector2,
	to: Vector2,
	color: Color3,
	thickness: number,
	transparency: number,
	parent: Instance
)
	local delta = to - from
	local length = delta.Magnitude
	local mid = (from + to) / 2

	local segment = Instance.new("Frame")
	segment.Name = "Segment"
	segment.AnchorPoint = Vector2.new(0.5, 0.5)
	segment.Position = UDim2.fromScale(mid.X / CANVAS_SIZE, mid.Y / CANVAS_SIZE)

	-- 길이에 thickness 를 더하는 이유: 양 끝을 반원으로 덮어서
	-- 선이 꺾이는 지점이 각져 보이지 않게 하려는 것이다.
	segment.Size = UDim2.fromScale(
		(length + thickness) / CANVAS_SIZE,
		thickness / CANVAS_SIZE
	)
	segment.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	segment.BackgroundColor3 = color
	segment.BackgroundTransparency = transparency
	segment.BorderSizePixel = 0
	segment.ZIndex = parent.ZIndex

	-- CornerRadius 를 Scale 1 로 주면 짧은 변 기준 완전한 반원이 된다. = 둥근 끝
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = segment

	segment.Parent = parent
end

-- [image 방식] 두 점 사이를 원으로 촘촘히 찍어서 "굵은 선"을 만든다.
-- EditableImage:DrawLine 은 1픽셀 두께로만 그려지기 때문에 이 방법이 필요하다.
function DrawingCanvas:_stampSegmentImage(
	from: Vector2,
	to: Vector2,
	color: Color3,
	thickness: number,
	transparency: number
)
	local radius = math.max(1, math.floor(thickness / 2))
	local delta = to - from
	local distance = delta.Magnitude

	-- 원 사이 간격. 반지름의 1/3 정도면 선이 끊겨 보이지 않는다.
	local step = math.max(1, radius / 3)
	local count = math.max(1, math.ceil(distance / step))

	for i = 0, count do
		local point = from + delta * (i / count)
		self.image:DrawCircle(
			point,
			radius,
			color,
			transparency,
			Enum.ImageCombineType.AlphaBlend,
			Enum.AntiAliasing.Enabled
		)
	end
end

-- 스트로크 하나를 통째로 그린다. (되돌리기 후 다시 그릴 때, 관전자가 재생할 때 쓴다)
function DrawingCanvas:DrawStroke(stroke: Stroke)
	local color, thickness, transparency = renderParams(stroke)
	for _, segment in segmentsOf(stroke) do
		self:_stampSegment(segment[1], segment[2], color, thickness, transparency)
	end
end

-- 저장된 스트로크 전체를 처음부터 다시 그린다.
function DrawingCanvas:Redraw()
	self:_clearSurface()
	for _, stroke in self.strokes do
		self:DrawStroke(stroke)
	end
end

--------------------------------------------------------------------
-- 미리보기 (직선 / 도형을 끄는 동안)
--------------------------------------------------------------------

function DrawingCanvas:_clearPreview()
	if self.previewLayer then
		self.previewLayer:ClearAllChildren()
	end
end

function DrawingCanvas:_drawPreview(stroke: Stroke)
	self:_clearPreview()
	local color, thickness, transparency = renderParams(stroke)
	for _, segment in segmentsOf(stroke) do
		self:_stampSegmentFrame(
			segment[1], segment[2], color, thickness, transparency, self.previewLayer
		)
	end
end

--------------------------------------------------------------------
-- 되돌리기 / 다시하기
--------------------------------------------------------------------

function DrawingCanvas:_notifyHistoryChanged()
	if self.onHistoryChanged then
		self.onHistoryChanged()
	end
end

function DrawingCanvas:CanUndo(): boolean
	return #self.strokes > 0 or self.clearedSnapshot ~= nil
end

function DrawingCanvas:CanRedo(): boolean
	return #self.redoStack > 0
end

-- 마지막 선 하나 되돌리기. 스트로크를 저장했기 때문에 공짜로 얻는 기능이다.
function DrawingCanvas:Undo()
	-- 전체지우기 직후라면 지우기 자체를 취소한다.
	if #self.strokes == 0 and self.clearedSnapshot then
		self.strokes = self.clearedSnapshot
		self.clearedSnapshot = nil
		self:Redraw()
		self:_notifyHistoryChanged()
		return
	end

	local stroke = table.remove(self.strokes)
	if not stroke then
		return
	end
	table.insert(self.redoStack, stroke)
	self:Redraw()
	self:_notifyHistoryChanged()
end

function DrawingCanvas:Redo()
	local stroke = table.remove(self.redoStack)
	if not stroke then
		return
	end
	table.insert(self.strokes, stroke)
	-- 맨 위에 하나 더 얹는 것뿐이라 전체를 다시 그릴 필요가 없다.
	self:DrawStroke(stroke)
	self:_notifyHistoryChanged()
end

--------------------------------------------------------------------
-- 스포이드
--------------------------------------------------------------------

-- 그 자리에 있는 선의 색을 돌려준다. 아무것도 없으면 종이색.
--
-- 캔버스 픽셀을 읽는 대신 스트로크 데이터를 뒤에서부터 훑는다.
-- (1) image / frame 두 모드에서 똑같이 동작하고
-- (2) 픽셀 읽기 API 에 의존하지 않기 때문이다. (README §7-4)
-- 선 위를 눌러야 집힌다. 선이 없는 곳을 누르면 종이색이 나온다.
function DrawingCanvas:PickColorAt(point: Vector2): Color3
	for i = #self.strokes, 1, -1 do
		local stroke = self.strokes[i]
		local color, thickness = renderParams(stroke)
		local hitRadius = math.max(1, thickness / 2)
		for _, segment in segmentsOf(stroke) do
			if distanceToSegment(point, segment[1], segment[2]) <= hitRadius then
				return color
			end
		end
	end
	return PAPER_COLOR
end

--------------------------------------------------------------------
-- 입력 처리
--------------------------------------------------------------------

-- 화면 좌표 → 캔버스 픽셀 좌표
--
-- clampToCanvas 가 true 면 캔버스 밖이어도 가장자리 값으로 붙여서 돌려준다.
-- 도형을 그릴 때 마우스가 잠깐 밖으로 나가도 미리보기가 멈추지 않게 하려는 것이다.
function DrawingCanvas:_toCanvasPosition(screenPosition: Vector3, clampToCanvas: boolean?): Vector2?
	local absPos = self.imageLabel.AbsolutePosition
	local absSize = self.imageLabel.AbsoluteSize
	if absSize.X <= 0 or absSize.Y <= 0 then
		return nil
	end

	local relativeX = (screenPosition.X - absPos.X) / absSize.X
	local relativeY = (screenPosition.Y - absPos.Y) / absSize.Y

	if clampToCanvas then
		relativeX = math.clamp(relativeX, 0, 1)
		relativeY = math.clamp(relativeY, 0, 1)
	elseif relativeX < 0 or relativeX > 1 or relativeY < 0 or relativeY > 1 then
		return nil -- 캔버스 밖이면 무시
	end

	return Vector2.new(relativeX * CANVAS_SIZE, relativeY * CANVAS_SIZE)
end

function DrawingCanvas:_beginStroke(point: Vector2)
	local isEraser = self.tool == "eraser"
	local stroke: Stroke = {
		tool = self.tool,
		color = self.color,
		thickness = if isEraser then self.eraserThickness else self.thickness,
		transparency = self.transparency,
		points = { point },
	}
	self.currentStroke = stroke
	self.lastPoint = point

	-- 손으로 긋는 도구는 누르는 즉시 점이 찍혀야 반응이 좋다.
	-- 직선/도형은 아직 끝점을 모르므로 여기서는 아무것도 안 그린다.
	if FREEHAND_TOOLS[stroke.tool] then
		local color, thickness, transparency = renderParams(stroke)
		self:_stampSegment(point, point, color, thickness, transparency)
	end
end

function DrawingCanvas:_continueStroke(point: Vector2)
	local stroke = self.currentStroke
	if not stroke then
		return
	end

	if not FREEHAND_TOOLS[stroke.tool] then
		-- 직선/도형은 점이 늘어나는 게 아니라 끝점이 갱신되는 것이다.
		stroke.points[2] = point
		self:_drawPreview(stroke)
		return
	end

	local last = self.lastPoint
	if not last then
		return
	end

	-- 너무 가까운 점은 버린다. 데이터 양이 몇 배 차이난다.
	if (point - last).Magnitude < MIN_POINT_DISTANCE then
		return
	end
	if #stroke.points >= MAX_POINTS_PER_STROKE then
		return
	end

	table.insert(stroke.points, point)
	local color, thickness, transparency = renderParams(stroke)
	self:_stampSegment(last, point, color, thickness, transparency)
	self.lastPoint = point
end

function DrawingCanvas:_endStroke()
	local stroke = self.currentStroke
	self.currentStroke = nil
	self.lastPoint = nil
	self:_clearPreview()

	if not stroke then
		return
	end

	-- 직선/도형인데 끌지 않고 그냥 클릭만 한 경우는 실수로 본다.
	if not FREEHAND_TOOLS[stroke.tool] and #stroke.points < 2 then
		return
	end

	-- 미리보기로만 있던 것을 진짜 캔버스에 한 번 옮겨 그린다.
	if not FREEHAND_TOOLS[stroke.tool] then
		self:DrawStroke(stroke)
	end

	table.insert(self.strokes, stroke)

	-- 새로 그렸으면 "다시하기" 기록은 의미가 없어진다. 일반적인 편집기 동작이다.
	table.clear(self.redoStack)
	self.clearedSnapshot = nil
	self:_notifyHistoryChanged()

	-- 나중에 이 자리에 "서버로 전송" 을 붙이면 멀티플레이가 된다.
	if self.onStrokeFinished then
		self.onStrokeFinished(stroke)
	end
end

function DrawingCanvas:_bindInput()
	local label = self.imageLabel

	-- 캔버스가 입력을 **삼키게** 한다.
	--
	-- 이게 없으면 캔버스를 끄는 동작이 그림 그리기로도 쓰이고
	-- 동시에 카메라 조작으로도 전달된다. 그림을 그릴 때마다 화면이 같이 돌아간다.
	-- 모바일에서는 캐릭터까지 움직인다. (터치가 조이스틱 입력으로도 해석되기 때문)
	--
	-- Active = true 면 이 영역의 터치·클릭이 여기서 멈추고 3D 쪽으로 내려가지 않는다.
	-- InputBegan 같은 신호는 그대로 오므로 그리기에는 아무 영향이 없다.
	label.Active = true

	label.InputBegan:Connect(function(input)
		if not self.enabled then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local point = self:_toCanvasPosition(input.Position)
		if not point then
			return
		end

		-- 스포이드는 선을 남기지 않는다. 색만 집고 끝.
		if self.tool == "eyedropper" then
			local picked = self:PickColorAt(point)
			self.color = picked
			if self.onColorPicked then
				self.onColorPicked(picked)
			end
			return
		end

		self:_beginStroke(point)
	end)

	label.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		-- 지우개 동그라미는 그리는 중이 아니어도 따라다녀야 한다.
		-- 그래서 아래의 "그리는 중인가" 검사보다 먼저 처리한다.
		local hover = self:_toCanvasPosition(input.Position)
		self:_setCursorVisible(hover ~= nil)
		if hover then
			self:_moveCursor(hover)
		end

		if not self.enabled or not self.currentStroke then
			return
		end

		local stroke = self.currentStroke
		local clamp = not FREEHAND_TOOLS[stroke.tool]
		local point = self:_toCanvasPosition(input.Position, clamp)
		if point then
			self:_continueStroke(point)
		end
	end)

	-- 마우스가 캔버스를 벗어나면 동그라미를 끄고 포인터를 돌려준다.
	label.MouseLeave:Connect(function()
		self:_setCursorVisible(false)
	end)

	-- 캔버스 밖에서 손을 떼도 스트로크가 끝나도록 전역에서도 잡는다.
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			self:_endStroke()
		end
	end)

	-- 마우스가 캔버스 밖으로 나간 뒤에도 도형 미리보기가 따라오게 하려면
	-- 캔버스가 아니라 전역 입력에서도 좌표를 받아야 한다.
	UserInputService.InputChanged:Connect(function(input)
		if not self.enabled or not self.currentStroke then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local stroke = self.currentStroke
		if FREEHAND_TOOLS[stroke.tool] then
			return -- 손그림은 캔버스 밖으로 나가면 안 그리는 게 맞다
		end
		local point = self:_toCanvasPosition(input.Position, true)
		if point then
			self:_continueStroke(point)
		end
	end)
end

--------------------------------------------------------------------
-- 직렬화 (3단계 네트워킹 준비)
--------------------------------------------------------------------

-- 스트로크를 서버로 보낼 수 있는 가벼운 형태로 바꾼다.
-- Vector2 를 그대로 보내는 것보다 숫자 배열이 훨씬 작다.
--
-- ⚠️ 서버는 이 데이터를 절대 믿으면 안 된다. 점 개수, 좌표 범위, 굵기를
--    받는 쪽에서 전부 다시 검사해야 한다. (README §3.4, §7-7)
function DrawingCanvas.SerializeStroke(stroke: Stroke): { any }
	local flat = table.create(#stroke.points * 2)
	for _, p in stroke.points do
		table.insert(flat, math.floor(p.X))
		table.insert(flat, math.floor(p.Y))
	end
	return {
		math.floor(stroke.color.R * 255),
		math.floor(stroke.color.G * 255),
		math.floor(stroke.color.B * 255),
		stroke.thickness,
		flat,
		stroke.tool,
		stroke.transparency,
	}
end

function DrawingCanvas.DeserializeStroke(data: { any }): Stroke
	local flat = data[5] :: { number }
	local points = table.create(#flat // 2)
	for i = 1, #flat - 1, 2 do
		table.insert(points, Vector2.new(flat[i], flat[i + 1]))
	end
	return {
		color = Color3.fromRGB(data[1] :: number, data[2] :: number, data[3] :: number),
		thickness = data[4] :: number,
		points = points,
		-- 예전 형식(도구 개념이 없던 시절)도 읽을 수 있게 기본값을 둔다.
		tool = (data[6] :: string?) or "pen",
		transparency = (data[7] :: number?) or 0,
	}
end

return DrawingCanvas
