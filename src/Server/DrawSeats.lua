--!strict
--[[
	DrawSeats.lua  —  맵에 놓인 그리기용 의자를 찾고, 앉히고, 일으킨다

	배치 위치: ServerScriptService 안의 ModuleScript. **서버 전용.**

	왜 코드에 의자 위치를 안 적는가
	  맵은 스튜디오에서 손으로 만든다. (§2 확정)
	  Rojo 는 디스크에서 스튜디오 한 방향으로만 동기화하므로,
	  맵에 뭘 놓았는지는 코드 쪽에서 알 수 없다.
	  그래서 좌표를 적어두는 대신 **실행할 때 찾는다.**
	  의자를 옮기거나 새로 놓아도 코드는 그대로다.

	찾는 순서
	  1) "DrawSeat" 태그가 붙은 Seat 를 먼저 쓴다.
	  2) 하나도 없으면 Workspace 안의 Seat 를 전부 쓴다.

	  2번 덕분에 아무 설정 없이도 바로 동작한다.
	  나중에 맵에 관중석 의자 같은 게 생기면 그것까지 그리기용으로 잡아버리므로,
	  그때는 그리기용 의자에만 태그를 붙이면 된다.
	  (스튜디오에서 의자 선택 → 태그 편집기 → DrawSeat)

	앉은 사람은 점프를 못 한다
	  로블록스에서 의자를 빠져나오는 방법은 점프뿐이다.
	  점프를 막아두면 그리다가 스페이스바를 눌러 일어나 버리는 일이 없어진다.

	  ⚠️ 막았으면 **반드시 되돌려야 한다.** 안 그러면 라운드가 끝난 뒤에도
	     그 사람은 영영 점프를 못 하게 된다. standUp 이 그 일을 한다.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local DrawSeats = {}

-- 의자를 처음 봤을 때의 자리를 기억해둔다.
--
-- ⚠️ 앉은 사람을 옮기면 의자가 딸려간다.
--    캐릭터와 의자는 SeatWeld 로 묶여 있고, 그 용접이 사라지는 데 몇 프레임 걸린다.
--    그 사이에 캐릭터를 순간이동시키면 의자가 맵 한가운데로 끌려간다.
--
--    아래 WaitUntilEmpty 로 용접이 풀릴 때까지 기다리는 것이 1차 방어고,
--    이 표로 원래 자리에 되돌리는 것이 2차 방어다.
--    맵이 망가지는 종류의 버그라 두 겹으로 막는다.
local homeCFrames: { [Seat]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

-- 점프를 막기 전의 원래 값을 기억해둔다. 되돌릴 때 쓴다.
--
-- __mode = "k" 는 "열쇠가 사라지면 이 칸도 같이 버려라" 는 뜻이다.
-- 캐릭터가 죽거나 나가서 Humanoid 가 사라져도 이 표에 찌꺼기가 남지 않는다.
local lockedJumps: { [Humanoid]: { power: number, height: number } } =
	(setmetatable({}, { __mode = "k" }) :: any)

local function lockJump(humanoid: Humanoid)
	if not Config.LOCK_JUMP_WHILE_SEATED then
		return
	end
	if lockedJumps[humanoid] then
		return -- 이미 막아둔 사람
	end

	lockedJumps[humanoid] = {
		power = humanoid.JumpPower,
		height = humanoid.JumpHeight,
	}

	-- 둘 다 0 으로 둔다. 어느 쪽이 쓰이는지는 UseJumpPower 에 달려 있어서
	-- 하나만 막으면 설정에 따라 새어나간다.
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

local function unlockJump(humanoid: Humanoid)
	local saved = lockedJumps[humanoid]
	if not saved then
		return
	end
	lockedJumps[humanoid] = nil

	-- 캐릭터가 이미 사라졌으면 되돌릴 대상도 없다.
	if not humanoid.Parent then
		return
	end
	humanoid.JumpPower = saved.power
	humanoid.JumpHeight = saved.height
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
end

-- 순서를 고정한다.
--
-- 의자 두 개의 이름이 똑같을 수 있어서(둘 다 "Seat") 이름으로는 순서가 안 잡힌다.
-- 위치로 줄을 세우면 항상 같은 의자가 1번, 같은 의자가 2번이 된다.
-- 나중에 "왼쪽 사람 / 오른쪽 사람" 을 화면에 나눠 보여줄 때 이 순서가 기준이 된다.
local function sortByPosition(seats: { Seat })
	table.sort(seats, function(a, b)
		if a.Position.X ~= b.Position.X then
			return a.Position.X < b.Position.X
		end
		return a.Position.Z < b.Position.Z
	end)
end

function DrawSeats.find(): { Seat }
	local tagged: { Seat } = {}
	for _, instance in CollectionService:GetTagged(Config.DRAW_SEAT_TAG) do
		-- 태그는 남아 있는데 의자가 지워졌을 수 있으므로 확인한다.
		if instance:IsA("Seat") and instance:IsDescendantOf(Workspace) then
			table.insert(tagged, instance)
		end
	end
	if #tagged > 0 then
		sortByPosition(tagged)
		DrawSeats.remember(tagged)
		return tagged
	end

	local found: { Seat } = {}
	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("Seat") then
			table.insert(found, instance)
		end
	end
	sortByPosition(found)
	DrawSeats.remember(found)
	return found
end

-- 처음 보는 의자의 자리를 적어둔다. 이미 아는 의자는 건드리지 않는다.
-- (이미 끌려간 뒤에 덮어쓰면 잘못된 자리를 "원래 자리" 로 기억하게 된다)
function DrawSeats.remember(seats: { Seat })
	for _, seat in seats do
		if homeCFrames[seat] == nil then
			homeCFrames[seat] = seat.CFrame
		end
	end
end

-- 의자를 원래 자리로 되돌린다. 안 움직였으면 아무 일도 일어나지 않는다.
function DrawSeats.restore(seats: { Seat })
	for _, seat in seats do
		local home = homeCFrames[seat]
		if not home then
			continue
		end
		-- 라운드 도중 의자가 지워졌을 수 있다. 그때 여기서 오류가 나면
		-- 라운드 반복문 전체가 죽는다. 한 의자 문제로 게임이 멈추면 안 된다.
		pcall(function()
			if seat.CFrame ~= home then
				seat.CFrame = home
				seat.AssemblyLinearVelocity = Vector3.zero
				seat.AssemblyAngularVelocity = Vector3.zero
			end
		end)
	end
end

-- 의자가 전부 빌 때까지 기다린다. 최대 timeout 초.
--
-- humanoid.Sit = false 는 곧바로 반영되지 않는다. 용접이 실제로 사라지는 것은
-- 다음 물리 단계다. 그 전에 캐릭터를 옮기면 의자가 딸려간다.
function DrawSeats.waitUntilEmpty(seats: { Seat }, timeout: number)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local occupied = false
		for _, seat in seats do
			-- 지워진 의자를 건드리면 오류가 난다.
			local ok, humanoid = pcall(function()
				return seat.Occupant
			end)
			if ok and humanoid then
				occupied = true
				break
			end
		end
		if not occupied then
			return
		end
		task.wait()
	end
end

-- 이 의자에 앉아 있는 사람. 아무도 없으면 nil.
function DrawSeats.occupant(seat: Seat): Player?
	local humanoid = seat.Occupant
	if not humanoid then
		return nil
	end
	local character = humanoid.Parent
	if not character then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

-- 앉히기. 캐릭터가 아직 없거나 죽어 있으면 실패하고 false 를 돌려준다.
-- Seat:Sit 은 캐릭터를 의자 위치로 옮겨주기까지 하므로 따로 이동시킬 필요가 없다.
function DrawSeats.sit(seat: Seat, player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local ok = pcall(function()
		seat:Sit(humanoid)
	end)
	if ok then
		lockJump(humanoid)
	end
	return ok
end

-- 일으켜 세우기. 라운드가 끝나면 자리를 비워야 다음 사람이 앉을 수 있다.
function DrawSeats.standUp(seat: Seat)
	local humanoid = seat.Occupant
	if not humanoid then
		return
	end
	-- 푸는 것이 먼저다. 앉은 채로 점프가 막혀 있는 상태에서
	-- 일으키다가 중간에 실패하면 점프가 막힌 채로 남는다.
	unlockJump(humanoid)
	-- 캐릭터가 그 사이에 사라졌을 수 있다.
	pcall(function()
		humanoid.Sit = false
	end)
end

-- 만약을 대비한 안전장치. 라운드가 어떤 이유로 꼬여도
-- 이걸 부르면 점프가 막힌 사람이 아무도 남지 않는다.
function DrawSeats.unlockAll()
	for humanoid in lockedJumps do
		unlockJump(humanoid)
	end
end

return DrawSeats
