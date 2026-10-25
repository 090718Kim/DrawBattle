--!strict
--[[
	DrawerPicker.lua  —  이번 라운드에 그릴 사람 뽑기

	배치 위치: ServerScriptService 안의 ModuleScript.
	**서버 전용이다.** 누가 뽑히는지는 클라이언트가 정할 일이 아니다. (README §7-7)

	§1 확정: "서버 인원 중 랜덤 2명. 안 뽑힐수록 확률 상승 (가중치 방식)"

	왜 그냥 랜덤이 아닌가
	  모두 같은 확률로 뽑으면 운 나쁜 사람은 열 판을 내리 구경만 하게 된다.
	  한 번 그러면 그 사람은 게임을 끄고 나간다.
	  안 뽑힐 때마다 가중치를 올려두면 언젠가는 반드시 차례가 온다.

	왜 상한을 두는가
	  상한이 없으면 오래 있던 사람의 가중치가 끝없이 올라서
	  나중에는 그 사람만 계속 뽑힌다. 방금 들어온 사람이 영영 못 그리게 된다.
	  이번에는 "안 뽑힌 사람" 이 독점하는 반대 방향의 불공평이 생기는 것이다.

	5단계에서 붙은 것 두 가지

	  1) 안 그리기 선언 — 뽑기에서 빼되 **가중치는 계속 올린다.**
	     잠깐 쉬었다고 줄 맨 뒤로 밀리면 선언 자체를 아무도 안 하게 된다.
	     빼는 일은 여기서 하지 않는다. 부르는 쪽이 후보에서 미리 걸러 보내고,
	     가중치만 올려달라고 따로 알려준다. (Gain)

	  2) 진행도 계산 (ProgressFor) — 화면 아래 게이지에 쓴다.
	     "언젠가 차례가 온다" 는 약속이 눈에 보여야 기다릴 수 있다.
	     **확률이 아니라 진행도다.** 이유는 그 함수 위에 적어뒀다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DrawerPicker = {}
DrawerPicker.__index = DrawerPicker

function DrawerPicker.new()
	local self = setmetatable({}, DrawerPicker)
	-- [userId] = 가중치. 클수록 뽑힐 확률이 높다.
	self.weights = {} :: { [number]: number }
	return self
end

-- 나간 사람의 기록을 지운다. 안 지우면 서버가 도는 내내 쌓인다.
function DrawerPicker:Forget(userId: number)
	self.weights[userId] = nil
end

-- 가중치를 그대로 돌려준다. 확인용.
function DrawerPicker:GetWeight(userId: number): number
	return self.weights[userId] or Config.PICK_BASE_WEIGHT
end

-- 뽑히지 않은 사람들의 가중치를 올린다.
--
-- Pick 안에서 같이 하지 않고 따로 떼어둔 이유:
-- **안 그리기를 선언한 사람은 후보에 아예 없지만 가중치는 올라야 한다.**
-- Pick 은 후보만 보므로 그 사람들을 알 수가 없다.
function DrawerPicker:Gain(userIds: { number })
	for _, userId in userIds do
		local weight = (self.weights[userId] or Config.PICK_BASE_WEIGHT) + Config.PICK_WEIGHT_GAIN
		self.weights[userId] = math.min(weight, Config.PICK_MAX_WEIGHT)
	end
end

-- 게이지에 쓸 값 (0~1). "내 차례가 얼마나 가까운가" 다.
--
-- ⚠️ **확률이 아니다. 일부러 확률을 안 쓴다.**
--
--    처음에는 진짜 확률(가중치와 인원으로 계산한 값)을 보여줬다.
--    그런데 확률은 **몇 명이 다투느냐에 달려 있다.**
--    3명 서버에 막 들어오면 자리가 2개라 67% 로 시작하고,
--    10명 서버면 같은 사람이 20% 로 시작한다.
--    아무것도 안 했는데 누가 들어오면 숫자가 떨어지기도 한다.
--
--    그러면 이 값이 "내가 얼마나 기다렸나" 가 아니라
--    "지금 서버가 얼마나 붐비나" 를 재게 된다. 기다린 보람이 안 보인다.
--
--    가중치 진행도는 인원과 상관없다.
--      새로 들어오면 0%,  판마다 오르고,  그리면 다시 0%.
--    어느 서버에서든 같은 뜻이다.
function DrawerPicker:ProgressFor(userId: number): number
	local weight = self.weights[userId] or Config.PICK_BASE_WEIGHT
	local span = Config.PICK_MAX_WEIGHT - Config.PICK_BASE_WEIGHT
	if span <= 0 then
		return 1
	end
	return math.clamp((weight - Config.PICK_BASE_WEIGHT) / span, 0, 1)
end

-- 후보 중 count 명을 가중치에 따라 뽑는다.
-- 같은 사람이 두 번 뽑히지 않도록, 뽑은 사람은 후보에서 빼고 다시 돌린다.
function DrawerPicker:Pick(candidates: { Player }, count: number): { Player }
	-- 처음 보는 사람에게 기본 가중치를 준다.
	for _, player in candidates do
		if self.weights[player.UserId] == nil then
			self.weights[player.UserId] = Config.PICK_BASE_WEIGHT
		end
	end

	local pool = table.clone(candidates)
	local chosen: { Player } = {}

	for _ = 1, math.min(count, #pool) do
		-- 가중치를 전부 더한 뒤, 0~합계 사이의 수를 하나 뽑는다.
		-- 그 수가 어느 사람의 몫에 떨어지는지 앞에서부터 더해가며 찾는다.
		-- 가중치가 큰 사람일수록 몫이 넓어서 걸릴 확률이 높다.
		local total = 0
		for _, player in pool do
			total += self.weights[player.UserId]
		end

		local roll = math.random() * total
		local index = #pool -- 부동소수점 오차로 아무도 안 걸릴 때를 대비한 기본값
		local running = 0
		for i, player in pool do
			running += self.weights[player.UserId]
			if roll <= running then
				index = i
				break
			end
		end

		table.insert(chosen, table.remove(pool, index) :: Player)
	end

	-- 뽑힌 사람은 처음으로 돌아간다.
	--
	-- 안 뽑힌 사람을 올리는 일은 여기서 하지 않는다.
	-- 안 그리기를 선언한 사람은 후보(pool)에 아예 없는데 그 사람들도 올라야 하므로,
	-- 부르는 쪽이 "이번에 안 그린 사람" 전체를 모아 Gain 으로 넘긴다.
	for _, player in chosen do
		self.weights[player.UserId] = Config.PICK_BASE_WEIGHT
	end

	return chosen
end

return DrawerPicker
