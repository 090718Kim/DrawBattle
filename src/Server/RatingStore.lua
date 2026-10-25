--!strict
--[[
	RatingStore.lua  —  별점을 모으고, 라운드 결과를 계산한다

	배치 위치: ServerScriptService 안의 ModuleScript. **서버 전용.**

	별점은 게임의 승패를 정하는 값이다. 클라이언트가 보낸 숫자를
	그대로 받으면 별 999개를 주는 사람이 나온다. (README §3.4, §7-7)

	검사하는 것
	  - 관전자인가 (그리는 사람은 심사하지 않는다, §1)
	  - 대상이 이번 라운드에 그린 사람인가
	  - 별 개수가 1~5 사이의 정수인가

	점수 계산 (§2 확정)
	  라운드 승패는 별점 **합산**. 승자는 합산 + 5, 패자는 합산 그대로.
	  합산이 같으면 **무승부** — 둘 다 합산만 받고 보너스는 아무도 못 받는다.

	  등급 산정은 합산이 아니라 **평균**을 쓴다. 그래서 평균도 같이 내둔다.
	  합산을 쓰면 관전자 많은 서버에서 논 사람이 무조건 유리해져서
	  "실력" 이 아니라 "서버 인원수" 를 재게 된다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local RatingStore = {}
RatingStore.__index = RatingStore

function RatingStore.new()
	local self = setmetatable({}, RatingStore)
	-- [매긴 사람 userId] = { [그린 사람 userId] = 별 개수 }
	--
	-- 매긴 사람을 바깥 열쇠로 두는 이유: "한 사람이 한 그림에 하나만" 을
	-- 표 구조 자체로 보장할 수 있다. 따로 세어볼 필요가 없다.
	self.byRater = {} :: { [number]: { [number]: number } }
	return self
end

function RatingStore:Reset()
	self.byRater = {}
end

-- 별점을 기록한다. 통과하면 true.
--
-- 이미 준 별점을 바꾸는 것은 허용한다.
-- 한 사람 그림을 보고 별을 준 뒤 다른 사람 그림을 보면 생각이 바뀌는데,
-- 그때 못 고치면 먼저 본 쪽이 손해다. 어차피 남의 별점은 결과가 나올 때까지
-- 아무도 못 보므로 눈치 싸움이 될 여지도 없다.
function RatingStore:Rate(raterUserId: number, targetUserId: number, stars: any, drawers: { number }): boolean
	-- 그리는 사람은 심사하지 않는다. 자기 그림에 주는 것도 여기서 같이 막힌다.
	if table.find(drawers, raterUserId) then
		return false
	end
	if not table.find(drawers, targetUserId) then
		return false
	end

	if typeof(stars) ~= "number" then
		return false
	end
	if stars ~= stars then
		return false -- NaN
	end
	-- 정수여야 한다. 3.7 개를 주면 합산이 이상해진다.
	if stars % 1 ~= 0 then
		return false
	end
	if stars < Config.MIN_STARS or stars > Config.MAX_STARS then
		return false
	end

	local given = self.byRater[raterUserId]
	if not given then
		given = {}
		self.byRater[raterUserId] = given
	end
	given[targetUserId] = stars
	return true
end

-- 이 사람이 저 그림에 준 별점. 아직 안 줬으면 nil.
function RatingStore:Get(raterUserId: number, targetUserId: number): number?
	local given = self.byRater[raterUserId]
	return given and given[targetUserId]
end

-- 한 그림이 받은 별점을 모은다.
local function collect(self, targetUserId: number): (number, number)
	local total = 0
	local count = 0
	for _, given in self.byRater do
		local stars = given[targetUserId]
		if stars then
			total += stars
			count += 1
		end
	end
	return total, count
end

-- 라운드 결과를 낸다.
--
-- 돌려주는 것:
--   {
--     draw = boolean,           -- 무승부인가
--     entries = {               -- drawers 순서 그대로
--       { userId, name, total, count, average, score, winner }
--     }
--   }
--   total   받은 별점 합산
--   count   몇 명이 매겼나
--   average 평균 (등급 산정용, §2)
--   score   합산 + 승자 보너스
function RatingStore:Results(drawers: { number }, names: { string })
	local entries = {}
	local best = -1

	for index, userId in drawers do
		local total, count = collect(self, userId)
		table.insert(entries, {
			userId = userId,
			name = names[index] or ("Player " .. index),
			total = total,
			count = count,
			-- 아무도 안 매겼으면 0 으로 나눈다. 그건 0 으로 둔다.
			average = if count > 0 then total / count else 0,
			score = total,
			winner = false,
		})
		if total > best then
			best = total
		end
	end

	-- 최고점이 몇 명인지 세어 무승부를 가린다.
	local topCount = 0
	for _, entry in entries do
		if entry.total == best then
			topCount += 1
		end
	end
	local draw = topCount ~= 1

	-- 확정: 동점이면 무승부. 보너스는 아무도 못 받는다.
	if not draw then
		for _, entry in entries do
			if entry.total == best then
				entry.winner = true
				entry.score = entry.total + Config.WINNER_BONUS
			end
		end
	end

	-- 별점을 많이 받은 사람이 위로 오게 한다.
	-- 결과표는 위에서부터 읽으므로, 순위가 곧 줄 순서여야 한눈에 들어온다.
	table.sort(entries, function(a, b)
		return a.total > b.total
	end)

	return { draw = draw, entries = entries }
end

return RatingStore
