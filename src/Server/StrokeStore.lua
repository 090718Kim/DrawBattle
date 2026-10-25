--!strict
--[[
	StrokeStore.lua  —  그림을 보관하고, 들어온 선을 검사한다

	배치 위치: ServerScriptService 안의 ModuleScript. **서버 전용.**

	여기가 이 프로젝트에서 **가장 의심이 많아야 하는 파일**이다.
	클라이언트가 보낸 선을 그대로 다른 사람에게 넘기면,
	익스플로잇 하나로 관전자 전원의 화면을 멎게 만들 수 있다. (README §3.4, §7-7)

	검사하는 것
	  - 생김새: 표가 맞는지, 칸이 다 있는지
	  - 숫자: 숫자가 맞는지, NaN 이나 무한대가 아닌지, 범위 안인지
	  - 양: 점 개수, 라운드당 선 개수
	  - 도구 이름: Config.TOOLS 에 있는 것인지

	NaN 을 따로 보는 이유
	  NaN 은 자기 자신과도 같지 않은 이상한 값이라 x < 0 도 x > 512 도 전부 false 다.
	  그래서 범위 검사만 하면 그냥 통과해버리고, 화면에 그릴 때 터진다.

	보관 형태는 **직렬화된 그대로**다. 서버는 이걸 해석할 필요가 없고,
	관전자에게 넘기거나 신고 대응으로 저장할 때(§3.10) 그대로 쓰면 된다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local StrokeStore = {}
StrokeStore.__index = StrokeStore

-- Config.TOOLS 를 이름으로 찾아볼 수 있는 표로 바꿔둔다.
-- 도구를 추가하거나 지워도 Config 만 고치면 여기가 따라온다.
local KNOWN_TOOLS: { [string]: boolean } = {}
for _, tool in Config.TOOLS do
	KNOWN_TOOLS[tool.id] = true
end

-- 지우개가 가장 굵으므로 굵기 상한은 그쪽에 맞춘다.
local MAX_THICKNESS = math.max(Config.MAX_THICKNESS, Config.MAX_ERASER_THICKNESS)

-- 숫자이고, NaN 도 무한대도 아니고, 범위 안인가.
local function isNumberInRange(value: any, min: number, max: number): boolean
	if typeof(value) ~= "number" then
		return false
	end
	if value ~= value then
		return false -- NaN. 자기 자신과 같지 않은 유일한 값이다.
	end
	if value == math.huge or value == -math.huge then
		return false
	end
	return value >= min and value <= max
end

function StrokeStore.new()
	local self = setmetatable({}, StrokeStore)
	-- [userId] = { 직렬화된 스트로크, ... }
	self.byUser = {} :: { [number]: { any } }
	return self
end

-- 새 라운드가 시작될 때 전부 비운다.
function StrokeStore:Reset()
	self.byUser = {}
end

function StrokeStore:Get(userId: number): { any }
	return self.byUser[userId] or {}
end

function StrokeStore:Count(userId: number): number
	local list = self.byUser[userId]
	return if list then #list else 0
end

-- 검사를 통과하면 보관하고 true, 아니면 아무것도 안 하고 false.
--
-- 통과하지 못한 것을 경고로 남기지 않는 이유:
-- 공격자가 일부러 틀린 값을 쏟아부으면 출력창이 그것으로 가득 차서
-- 정작 봐야 할 오류를 못 보게 된다. 조용히 버리는 것이 맞다.
function StrokeStore:Add(userId: number, data: any): boolean
	if typeof(data) ~= "table" then
		return false
	end

	-- 양 먼저 본다. 나머지 검사를 하기도 전에 걸러내는 것이 싸다.
	if self:Count(userId) >= Config.MAX_STROKES_PER_ROUND then
		return false
	end

	-- 색 (0~255)
	for index = 1, 3 do
		if not isNumberInRange(data[index], 0, 255) then
			return false
		end
	end

	-- 굵기
	if not isNumberInRange(data[4], Config.MIN_THICKNESS, MAX_THICKNESS) then
		return false
	end

	-- 점 좌표. {x1, y1, x2, y2, ...} 형태라 개수가 반드시 짝수여야 한다.
	local flat = data[5]
	if typeof(flat) ~= "table" then
		return false
	end
	local count = #flat
	if count < 2 or count % 2 ~= 0 then
		return false
	end
	if count // 2 > Config.MAX_POINTS_PER_STROKE then
		return false
	end
	for _, value in flat do
		if not isNumberInRange(value, 0, Config.CANVAS_SIZE) then
			return false
		end
	end

	-- 도구 이름
	local tool = data[6]
	if typeof(tool) ~= "string" or not KNOWN_TOOLS[tool] then
		return false
	end

	-- 투명도. 없으면 0 으로 본다 (예전 형식 대비).
	local transparency = data[7]
	if transparency ~= nil and not isNumberInRange(transparency, 0, 1) then
		return false
	end

	-- 여기까지 왔으면 안전하다.
	-- 클라이언트가 보낸 표를 그대로 두지 않고 필요한 칸만 새로 담는다.
	-- 표에 몰래 끼워 넣은 다른 칸까지 관전자에게 넘어가는 것을 막는다.
	local clean = {
		data[1], data[2], data[3],
		data[4],
		table.clone(flat),
		tool,
		transparency or 0,
	}

	local list = self.byUser[userId]
	if not list then
		list = {}
		self.byUser[userId] = list
	end
	table.insert(list, clean)
	return true
end

return StrokeStore
