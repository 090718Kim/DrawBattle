--!strict
--[[
	PlayerStats.lua  —  리더보드와 저장

	배치 위치: ServerScriptService 안의 ModuleScript. **서버 전용.**

	로블록스 기본 리더보드에 올린다.
	  Wins   이긴 판 수
	  Score  **받은 점수를 그대로 누적한다.** 평균이나 보정값이 아니다.
	         한 판에 14점 받았으면 14 오른다. 결과 화면에서 본 숫자와 같다.

	프로 서버 자격도 이 Score 로 건다. (§2 확정, 기준 점수는 미정)

	recent (최근 판 별점 평균) 도 같이 쌓지만 **아무 데도 안 쓴다.**
	화면에 안 나오고 자격 판정에도 안 쓴다. 비용이 없어서 지우지 않았을 뿐이다.

	⚠️ 저장이 실패했을 때 **기본값으로 덮어쓰면 안 된다.**
	   불러오기에 실패한 사람을 0점으로 저장해버리면 기록이 영영 사라진다.
	   그래서 "불러오기에 성공한 사람"만 저장한다.

	⚠️ 저장은 절대값이 아니라 **늘어난 만큼(delta)**을 더한다.
	   재접속할 때 옛 서버가 아직 안 죽어서 나중에 저장하는 일이 있다.
	   절대값을 쓰면 그때 한쪽 판이 통째로 날아간다.
	   "old + 늘어난 만큼"으로 쓰면 양쪽이 다 더해진다.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PlayerStats = {}

local store = DataStoreService:GetDataStore(Config.STATS_STORE_NAME)

-- 저장이 어디서 끊기는지 보려고 한 줄씩 찍는다.
-- 라운드당 몇 줄뿐이라 출력창을 어지럽히지 않는다.
-- 저장은 눈에 안 보이는 일이라, 안 찍으면 틀렸을 때 알 방법이 없다. (§5.5-8)
local function log(...)
	print("[PlayerStats]", ...)
end

-- 저장소에 들어가는 모양.
type Stored = {
	wins: number,
	score: number,
	recent: { number },
	-- ⚠️ 아래 값은 **전부 늘기만 한다. 남은 개수를 저장하지 않는다.**
	--    저장이 "늘어난 만큼을 더하는" 방식이라, 줄어드는 값이 섞이면
	--    두 서버가 겹쳤을 때 셈이 어긋난다. (§3.11-2)
	--
	-- ⚠️ 주제 작성권은 **무료와 유료를 따로 센다.**
	--    지금은 둘 다 쌓이지만(2026-10-28 부터), 무료에는 상한(Config.MAX_FREE_TOKENS)을 걸 수 있다.
	--    규칙이 다를 수 있으므로 지갑도 둘이다.
	--    한 통으로 세면 상한을 걸었을 때 유료로 한 장 산 사람이 그동안 무료를 못 받게 된다.
	--
	--      무료 남은 수 = tokensEarned - tokensSpent
	--      유료 남은 수 = tokensBought - paidSpent
	--      다음 무료가 나오는 시각 = tokenClockBase + PLAY_SECONDS_PER_TOKEN
	--
	-- ⚠️ 다음 장까지를 (tokensEarned + 1) × 기준시간 으로 재면 안 된다.
	--    playSeconds 는 "총 논 시간" 이고 tokensEarned 는 "받은 장수" 인데,
	--    둘은 **반드시 어긋난다.** 15초마다 세니까 매번 조금씩 넘겨서 받고,
	--    기준시간을 바꾸거나 옛 데이터가 있으면 한 번에 크게 벌어진다.
	--    실제로 그래서 쓰자마자 다시 지급되는 일이 있었다.
	--    (playSeconds=885, tokensEarned=1, 기준 30초 -> 900 >= 60 이라 즉시)
	--
	--    그래서 "이번 판이 언제부터 세기 시작했나" 를 따로 들고 있는다.
	--
	--    쓸 때는 **무료부터** 쓴다. 무료는 써야 다시 차기 때문이다.
	--
	-- playSeconds 는 접속해 있던 총 시간(초)이다. 늘 오른다. 다음 작성권 시계의 기준이 된다.
	-- (2026-10-28 전에는 무료 한 장을 들고 있는 동안 멈췄다. AddPlayTime 참고)
	playSeconds: number,
	tokensSpent: number, -- 무료를 쓴 수
	paidSpent: number, -- 유료를 쓴 수
	-- 지금 세고 있는 판이 시작된 시점 (playSeconds 기준).
	-- 한 장 받을 때마다 그 순간의 playSeconds 로 옮긴다. 넘긴 만큼이 흡수된다.
	tokenClockBase: number,
	-- 놀아서 받은 주제 작성권 수. 위 식의 기준선 역할을 한다.
	tokensEarned: number,
	-- 로벅스로 산 주제 작성권 수, 그리고 "다음에 내가 그리기" 산 수 / 쓴 수.
	--
	-- ⚠️ 여기 있는 값은 **전부 늘기만 한다.** 남은 개수를 저장하지 않는다.
	--    저장이 "늘어난 만큼을 더하는" 방식이라, 줄어드는 값이 섞이면
	--    두 서버가 겹쳤을 때 셈이 어긋난다.
	tokensBought: number,
	drawNextBought: number,
	drawNextUsed: number,
	peekBought: number,
	peekUsed: number,
}

-- 접속해 있는 동안만 들고 있는 것. 저장되지 않는다.
type Session = {
	wins: number,
	score: number,
	recent: { number },
	playSeconds: number,
	tokensSpent: number,
	paidSpent: number,
	tokenClockBase: number,
	tokensEarned: number,
	tokensBought: number,
	drawNextBought: number,
	drawNextUsed: number,
	peekBought: number,
	peekUsed: number,
	-- 마지막 저장 이후로 늘어난 만큼. 저장에 성공하면 0 으로 돌아간다.
	pendingWins: number,
	pendingScore: number,
	pendingRecent: { number },
	pendingSeconds: number,
	pendingSpent: number,
	pendingPaidSpent: number,
	pendingClockBase: number,
	pendingEarned: number,
	pendingBought: number,
	pendingDrawBought: number,
	pendingDrawUsed: number,
	pendingPeekBought: number,
	pendingPeekUsed: number,
	loaded: boolean, -- 불러오기에 성공했나. 실패했으면 저장하지 않는다.
	saving: boolean, -- 지금 저장 중인가. 주기 저장과 퇴장 저장이 겹칠 수 있다.
	winsValue: IntValue?,
	scoreValue: IntValue?,
}

local sessions: { [number]: Session } = {}

local function keyFor(userId: number): string
	return "p_" .. userId
end

local function blank(): Stored
	return {
		wins = 0,
		score = 0,
		recent = {},
		playSeconds = 0,
		tokensSpent = 0,
		paidSpent = 0,
		tokenClockBase = 0,
		tokensEarned = 0,
		tokensBought = 0,
		drawNextBought = 0,
		drawNextUsed = 0,
		peekBought = 0,
		peekUsed = 0,
	}
end

-- 저장된 값이 우리가 기대하는 모양인지 확인한다.
-- 형식을 바꾸다 보면 옛 데이터가 남아 있는데, 그걸 그대로 믿으면 여기서 터진다.
-- 여기서 터지면 그 사람은 영영 게임에 못 들어온다.
local function sanitize(raw: any): Stored
	local data = blank()
	if typeof(raw) ~= "table" then
		return data
	end

	if typeof(raw.wins) == "number" and raw.wins == raw.wins and raw.wins >= 0 then
		data.wins = math.floor(raw.wins)
	end
	if typeof(raw.score) == "number" and raw.score == raw.score and raw.score >= 0 then
		data.score = math.floor(raw.score)
	end
	-- 늘기만 하는 값들. 검사가 전부 같아서 한 번에 훑는다.
	for _, key in
		{
			"playSeconds",
			"tokensSpent",
			"paidSpent",
			"tokenClockBase",
			"tokensEarned",
			"tokensBought",
			"drawNextBought",
			"drawNextUsed",
			"peekBought",
			"peekUsed",
		}
	do
		local value = (raw :: any)[key]
		if typeof(value) == "number" and value == value and value >= 0 then
			(data :: any)[key] = math.floor(value)
		end
	end
	-- ⚠️ 옛 기록에는 tokenClockBase 가 없다.
	--    없는 것을 0 으로 두면 "지금까지 논 시간 전부" 가 이번 판으로 잡혀서
	--    들어오자마자 한 장이 튀어나온다. 지금 시각부터 세기 시작한 것으로 본다.
	if (raw :: any).tokenClockBase == nil then
		data.tokenClockBase = data.playSeconds
	end

	if typeof(raw.recent) == "table" then
		for _, value in raw.recent do
			if
				typeof(value) == "number"
				and value == value -- NaN 거르기
				and value >= 0
				and value <= Config.MAX_STARS
			then
				table.insert(data.recent, value)
			end
		end
	end
	return data
end

--------------------------------------------------------------------
-- 불러오기
--------------------------------------------------------------------

--------------------------------------------------------------------
-- 남은 개수 세기
--------------------------------------------------------------------
--
-- ⚠️ 이 함수들은 load 보다 **위에** 있어야 한다.
--    load 가 불러온 값을 찍을 때 tokensOf 를 쓰는데,
--    Lua 의 local 은 선언한 줄 아래에서만 보인다.
--    아래에 두면 load 안에서는 전역(nil)으로 잡혀 그 자리에서 터지고,
--    **리더보드와 티켓 속성이 통째로 안 붙는다.** (README §5.5-13)

-- 남은 주제 작성권 개수. 저장된 두 값에서 계산해서 낸다.
-- 무료로 받아 아직 안 쓴 수. 상한(Config.MAX_FREE_TOKENS)은 여기에만 걸린다. 지금은 상한이 없다.
local function freeTokensOf(session: Session): number
	return math.max(0, session.tokensEarned - session.tokensSpent)
end

-- 로벅스로 사서 아직 안 쓴 수. 제한 없이 쌓인다.
local function paidTokensOf(session: Session): number
	return math.max(0, session.tokensBought - session.paidSpent)
end

-- 화면에 보여주는 총 개수.
local function tokensOf(session: Session): number
	return freeTokensOf(session) + paidTokensOf(session)
end

-- 남은 "다음에 내가 그리기" 예약 수. 보통 0 아니면 1 이다.
local function drawNextOf(session: Session): number
	return math.max(0, session.drawNextBought - session.drawNextUsed)
end

-- 아직 안 쓴 엿보기 수.
local function peekOf(session: Session): number
	return math.max(0, session.peekBought - session.peekUsed)
end

-- 작성권·예약·엿보기 개수를 클라이언트에 알린다.
--
-- 특성(Attribute)을 쓰는 이유: 로블록스가 알아서 모든 클라이언트로 복제해준다.
-- 통로(RemoteEvent)를 새로 파고 들어올 때마다 보내주는 것보다 훨씬 싸다.
-- leaderstats 에 넣지 않는 이유: 그건 공개 순위표라 남들에게도 보인다.
--
-- (예전 이름은 pushTokens 였다. 개수가 셋으로 늘어서 하는 일에 맞게 바꿨다)
-- 화면 ⏱️ 칸은 여기서 안 보낸다. 그건 저장된 총 시간이 아니라 "이번 접속 시간" 이라
-- 화면이 스스로 센다. (DrawBattleUI._buildStats)
local function pushAttributes(player: Player, session: Session)
	player:SetAttribute("PromptTokens", tokensOf(session))
	player:SetAttribute("DrawNextBooked", drawNextOf(session) > 0)
	-- RoundService 가 이 특성이 바뀌는 것을 보고 있다가,
	-- 그리는 중에 산 것이면 그 자리에서 상대 그림을 열어준다.
	player:SetAttribute("PeekPending", peekOf(session))
end

local function newSession(): Session
	return {
		wins = 0,
		score = 0,
		recent = {},
		playSeconds = 0,
		tokensSpent = 0,
		paidSpent = 0,
		tokenClockBase = 0,
		tokensEarned = 0,
		tokensBought = 0,
		drawNextBought = 0,
		drawNextUsed = 0,
		peekBought = 0,
		peekUsed = 0,
		pendingWins = 0,
		pendingScore = 0,
		pendingRecent = {},
		pendingSeconds = 0,
		pendingSpent = 0,
		pendingPaidSpent = 0,
		pendingClockBase = 0,
		pendingEarned = 0,
		pendingBought = 0,
		pendingDrawBought = 0,
		pendingDrawUsed = 0,
		pendingPeekBought = 0,
		pendingPeekUsed = 0,
		loaded = false,
		saving = false,
		winsValue = nil,
		scoreValue = nil,
	}
end

local function load(player: Player): Session
	local session = newSession()
	sessions[player.UserId] = session

	-- 몇 번 다시 시도한다. 한 번 실패했다고 기록이 없는 사람 취급하면 안 된다.
	for attempt = 1, Config.STATS_LOAD_TRIES do
		local ok, result = pcall(function()
			return store:GetAsync(keyFor(player.UserId))
		end)
		if ok then
			local data = sanitize(result)
			session.wins = data.wins
			session.score = data.score
			session.recent = data.recent
			session.playSeconds = data.playSeconds
			session.tokensSpent = data.tokensSpent
			session.paidSpent = data.paidSpent
			session.tokenClockBase = data.tokenClockBase
			session.tokensEarned = data.tokensEarned
			session.tokensBought = data.tokensBought
			session.drawNextBought = data.drawNextBought
			session.drawNextUsed = data.drawNextUsed
			session.peekBought = data.peekBought
			session.peekUsed = data.peekUsed
			session.loaded = true
			-- 주제 작성권까지 같이 찍는다.
			--
			-- 안 찍었더니 "🎟️ 가 왜 안 보이지" 를 알 방법이 없었다.
			-- 21분을 채워야 나오는데, 지금 몇 분인지 볼 데가 없으면
			-- 고장인지 아직 이른 건지 구분이 안 된다. (README §5.5-8)
			local held = tokensOf(session)
			local waited = session.playSeconds - session.tokenClockBase
			log(string.format(
				"LOAD %s -> wins=%d score=%d | 주제권 %d개, 이번 판 %d분%d초 / %d분 (raw=%s)",
				player.Name,
				data.wins,
				data.score,
				held,
				math.floor(waited / 60),
				math.floor(waited % 60),
				math.floor(Config.PLAY_SECONDS_PER_TOKEN / 60),
				if result == nil then "nil(첫 접속)" else "table"
			))
			return session
		end
		warn(string.format(
			"[PlayerStats] Load failed for %s (try %d/%d): %s",
			player.Name, attempt, Config.STATS_LOAD_TRIES, tostring(result)
		))
		task.wait(attempt) -- 조금씩 더 기다렸다 다시
	end

	-- 끝내 실패했다. 이 사람은 이번 접속 동안 **저장하지 않는다.**
	-- 리더보드에는 0 으로 보이지만, 저장된 기록은 그대로 남아 있다.
	warn(string.format(
		"[PlayerStats] Giving up on %s. Nothing will be saved this session. "
			.. "(Studio라면 대시보드에서 API 서비스 액세스를 켰는지 확인할 것)",
		player.Name
	))
	return session
end

--------------------------------------------------------------------
-- 저장
--------------------------------------------------------------------


local function hasPending(session: Session): boolean
	return session.pendingWins > 0
		or session.pendingScore > 0
		or #session.pendingRecent > 0
		or session.pendingSeconds > 0
		or session.pendingSpent > 0
		or session.pendingPaidSpent > 0
		or session.pendingClockBase > 0
		or session.pendingEarned > 0
		or session.pendingBought > 0
		or session.pendingDrawBought > 0
		or session.pendingDrawUsed > 0
		or session.pendingPeekBought > 0
		or session.pendingPeekUsed > 0
end

local function save(player: Player)
	local session = sessions[player.UserId]
	if not session then
		return
	end
	if not session.loaded then
		-- ⚠️ 불러오기에 실패한 사람은 저장하지 않는다.
		--    지금 값(0)으로 덮어쓰면 원래 기록이 영영 사라진다.
		return
	end
	if not hasPending(session) then
		return -- 늘어난 게 없다
	end
	if session.saving then
		return -- 주기 저장과 퇴장 저장이 겹칠 수 있다
	end
	session.saving = true

	-- 지금 시점의 delta 를 떼어둔다.
	-- 저장하는 동안 라운드가 끝나서 또 늘어날 수 있는데,
	-- 그건 다음 저장에 실려야 한다.
	local wins = session.pendingWins
	local score = session.pendingScore
	local recent = session.pendingRecent
	local seconds = session.pendingSeconds
	local spent = session.pendingSpent
	local paidSpent = session.pendingPaidSpent
	local clockBase = session.pendingClockBase
	local earned = session.pendingEarned
	local bought = session.pendingBought
	local drawBought = session.pendingDrawBought
	local drawUsed = session.pendingDrawUsed
	local peekBought = session.pendingPeekBought
	local peekUsed = session.pendingPeekUsed
	session.pendingWins = 0
	session.pendingScore = 0
	session.pendingRecent = {}
	session.pendingSeconds = 0
	session.pendingSpent = 0
	session.pendingPaidSpent = 0
	session.pendingClockBase = 0
	session.pendingEarned = 0
	session.pendingBought = 0
	session.pendingDrawBought = 0
	session.pendingDrawUsed = 0
	session.pendingPeekBought = 0
	session.pendingPeekUsed = 0

	local merged: Stored? = nil
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player.UserId), function(old)
			-- ⚠️ 이 함수는 충돌이 나면 여러 번 불릴 수 있다.
			--    그래서 매번 old 로부터 새로 계산한다. 바깥 값을 고치면 안 된다.
			local previous = sanitize(old)
			local result = {
				wins = previous.wins + wins,
				score = previous.score + score,
				recent = previous.recent,
				playSeconds = previous.playSeconds + seconds,
				tokensSpent = previous.tokensSpent + spent,
				paidSpent = previous.paidSpent + paidSpent,
				tokenClockBase = previous.tokenClockBase + clockBase,
				tokensEarned = previous.tokensEarned + earned,
				tokensBought = previous.tokensBought + bought,
				drawNextBought = previous.drawNextBought + drawBought,
				drawNextUsed = previous.drawNextUsed + drawUsed,
				peekBought = previous.peekBought + peekBought,
				peekUsed = previous.peekUsed + peekUsed,
			}
			for _, value in recent do
				table.insert(result.recent, value)
			end
			while #result.recent > Config.RATING_WINDOW do
				table.remove(result.recent, 1) -- 오래된 것부터 버린다
			end
			merged = result
			return result
		end)
	end)

	session.saving = false

	if not ok then
		-- 실패했으면 떼어뒀던 delta 를 되돌려서 다음에 다시 시도한다.
		session.pendingWins += wins
		session.pendingScore += score
		session.pendingSeconds += seconds
		session.pendingSpent += spent
		session.pendingPaidSpent += paidSpent
		session.pendingClockBase += clockBase
		session.pendingEarned += earned
		session.pendingBought += bought
		session.pendingDrawBought += drawBought
		session.pendingDrawUsed += drawUsed
		session.pendingPeekBought += peekBought
		session.pendingPeekUsed += peekUsed
		for _, value in recent do
			table.insert(session.pendingRecent, value)
		end
		warn("[PlayerStats] Save failed for " .. player.Name .. ": " .. tostring(err))
		return
	end

	log(string.format(
		"SAVE %s: +%d wins, +%d score -> 저장됨 wins=%d score=%d",
		player.Name, wins, score,
		if merged then merged.wins else -1,
		if merged then merged.score else -1
	))

	-- 저장된 값으로 맞춘다. 다른 서버에서 올린 점수가 있었다면 여기서 반영된다.
	if merged then
		session.wins = merged.wins
		session.score = merged.score
		session.recent = merged.recent
		session.playSeconds = merged.playSeconds
		session.tokensSpent = merged.tokensSpent
		session.paidSpent = merged.paidSpent
		session.tokenClockBase = merged.tokenClockBase
		session.tokensEarned = merged.tokensEarned
		session.tokensBought = merged.tokensBought
		session.drawNextBought = merged.drawNextBought
		session.drawNextUsed = merged.drawNextUsed
		session.peekBought = merged.peekBought
		session.peekUsed = merged.peekUsed
		pushAttributes(player, session)
		if session.winsValue then
			session.winsValue.Value = session.wins
		end
		if session.scoreValue then
			session.scoreValue.Value = session.score
		end
	end
end

--------------------------------------------------------------------
-- 리더보드
--------------------------------------------------------------------

-- 값 하나를 만들거나, 이미 있으면 그것을 그대로 쓴다.
local function ensureStat(folder: Instance, name: string, value: number): IntValue
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("IntValue") then
		existing.Value = value
		return existing
	end
	if existing then
		-- 이름은 같은데 종류가 다르다. 남의 것이므로 치우고 새로 만든다.
		existing:Destroy()
	end
	local stat = Instance.new("IntValue")
	stat.Name = name
	stat.Value = value
	stat.Parent = folder
	return stat
end

local function buildLeaderstats(player: Player, session: Session)
	-- ⚠️ 폴더를 무조건 새로 만들면 안 된다.
	--    다른 스크립트(예전에 넣어둔 것, 플러그인이 넣은 것)가 이미
	--    leaderstats 를 만들어뒀으면 같은 이름의 폴더가 두 개가 된다.
	--    로블록스는 그중 하나만 보여주므로, 우리가 올린 점수가
	--    화면에 아예 안 나타나는 일이 생긴다. 찾기 매우 어려운 종류의 버그다.
	local folder = player:FindFirstChild("leaderstats")
	if folder then
		warn(string.format(
			"[PlayerStats] %s 에게 leaderstats 가 이미 있다. "
				.. "다른 스크립트가 만든 것이므로 그것을 이어서 쓴다. "
				.. "ServerScriptService 에 남의 리더보드 스크립트가 없는지 확인할 것.",
			player.Name
		))
	else
		local created = Instance.new("Folder")
		created.Name = "leaderstats" -- 이 이름이어야 로블록스가 리더보드로 인식한다
		created.Parent = player
		folder = created
	end

	session.winsValue = ensureStat(folder, "Wins", session.wins)
	session.scoreValue = ensureStat(folder, "Score", session.score)
end

--------------------------------------------------------------------
-- 바깥에서 쓰는 것
--------------------------------------------------------------------

export type RoundResult = {
	score: number, -- 이번 라운드에서 받은 점수 (별점 합산 + 승자 보너스)
	average: number, -- 이번 라운드 별점 평균
	raters: number, -- 몇 명이 매겼나
	won: boolean,
}

-- 라운드 결과 한 명분을 기록한다. 화면과 저장 대기줄에 동시에 반영된다.
function PlayerStats.AddRound(player: Player, result: RoundResult)
	local session = sessions[player.UserId]
	if not session then
		return -- 결과가 나오기 전에 나갔다
	end

	local gained = math.max(0, math.floor(result.score))
	session.score += gained
	session.pendingScore += gained

	if result.won then
		session.wins += 1
		session.pendingWins += 1
	end

	-- ⚠️ 아무도 안 매긴 판은 평균에 넣지 않는다.
	--    관전자가 없어서 0점이 된 것을 "못 그렸다"로 기록하면
	--    한산한 서버에서 논 사람만 등급이 떨어진다.
	if result.raters > 0 then
		table.insert(session.recent, result.average)
		table.insert(session.pendingRecent, result.average)
		while #session.recent > Config.RATING_WINDOW do
			table.remove(session.recent, 1)
		end
	end

	if session.scoreValue then
		session.scoreValue.Value = session.score
	end
	if session.winsValue then
		session.winsValue.Value = session.wins
	end

	log(string.format(
		"ROUND %s: +%d score, won=%s -> wins=%d score=%d (대기: +%d wins, +%d score)",
		player.Name, gained, tostring(result.won),
		session.wins, session.score,
		session.pendingWins, session.pendingScore
	))
end

-- 접속해 있는 시간을 더한다. 기준 시간이 차면 주제 작성권이 하나 생긴다.
--
-- **대기 중인 시간도 센다.** 접속해 있으면 그냥 올라간다. (§2)
--
-- **무료 작성권은 쌓인다.** (확정 2026-10-28 개발자 결정)
--   21분마다 한 장. 안 쓰고 있어도 다음 21분을 또 세서 또 준다.
--   예전에는 한 장 가지고 있으면 시간이 아예 안 쌓였다(한 장 제한).
--
-- ⚠️ playSeconds 는 이제 **진짜 총 플레이 시간**이다. (화면 ⏱️ 칸은 이걸 안 쓴다. 그건 이번 접속 시간이다)
--    예전에는 한 장 들고 있는 동안 이 값도 같이 멈췄다. 그 규칙의 목적은 "다음 장을 안 센다" 였는데,
--    시계를 멈추는 방법으로 했더니 **총 시간까지 같이 멈췄다.** 두 가지 일을 한 숫자에 맡긴 탓이다.
--    이제 총 시간은 늘 세고, "다음 장" 시계(playSeconds - tokenClockBase)만 따로 붙잡는다.
--    그래서 예전부터 하던 사람의 총 시간은 한 장 들고 있던 동안만큼 실제보다 적다. (출시 전이라 테스트 계정뿐)
function PlayerStats.AddPlayTime(player: Player, seconds: number)
	local session = sessions[player.UserId]
	if not session or seconds <= 0 then
		return
	end

	-- ⚠️ 저장소에서 아직 못 읽어왔으면 세지 않는다.
	--
	--    불러오기는 몇 초 걸리는데, 그동안 session 은 전부 0 이다.
	--    그 상태로 세면 "15초 놀았다" 를 기준으로 지급 여부를 따지게 되고,
	--    기준시간이 짧으면 **있지도 않은 티켓이 한 장 나온다.**
	--    불러온 뒤에 값이 덮어써져도 지급된 사실은 대기줄에 남아 저장된다.
	if not session.loaded then
		return
	end

	session.playSeconds += seconds
	session.pendingSeconds += seconds

	-- 무료 작성권이 상한에 닿았으면 **다음 장 시계만** 0 에 붙잡아 둔다. 총 시간은 위에서 이미 셌다.
	-- 지금은 상한이 없어서(Config.MAX_FREE_TOKENS = math.huge) 여기에 들어올 일이 없다.
	-- 다시 상한을 두고 싶으면 그 숫자만 바꾸면 된다.
	--
	-- ⚠️ **무료 지갑만** 본다. 총 개수를 보면 안 된다.
	--    로벅스로 한 장 산 사람이 그것을 들고 있는 동안
	--    무료 적립이 통째로 멈춰버린다. 돈 낸 사람이 손해를 보는 셈이다.
	--
	--    시계를 붙잡는 방법: 기준선(tokenClockBase)을 지금 시각으로 끌어온다.
	--    기준선은 늘기만 하는 값이라 delta 저장과도 맞는다. (§3.11-2)
	if freeTokensOf(session) >= Config.MAX_FREE_TOKENS then
		local held = session.playSeconds - session.tokenClockBase
		session.tokenClockBase += held
		session.pendingClockBase += held
		return
	end

	-- 이번 판을 시작한 시점(tokenClockBase)에서 기준시간만큼 지났는가.
	--
	-- ⚠️ 받는 순간 기준선을 **지금 시각으로 옮긴다.** 넘긴 만큼이 여기서 흡수된다.
	--    안 옮기고 장수로만 세면 넘긴 시간이 쌓여서, 언젠가 쓰자마자 또 나온다.
	if session.playSeconds - session.tokenClockBase >= Config.PLAY_SECONDS_PER_TOKEN then
		local advance = session.playSeconds - session.tokenClockBase
		session.tokenClockBase += advance
		session.pendingClockBase += advance

		session.tokensEarned += 1
		session.pendingEarned += 1
		pushAttributes(player, session)
		log(string.format(
			"TOKEN %s: 주제 작성권을 받았다 -> %d개 (누적 %d분)",
			player.Name, tokensOf(session), math.floor(session.playSeconds / 60)
		))
	end
end

-- 로벅스로 산 주제 작성권을 넣어준다. 21분 놀아서 받는 것과 같은 물건이다.
--
-- 같은 것으로 둔 이유: 쓰는 길이 하나면 된다.
-- "무료권으로 쓴 주제" 와 "산 주제" 를 갈라두면 두 배로 만들고 두 배로 틀린다.
function PlayerStats.GrantToken(player: Player, count: number)
	local session = sessions[player.UserId]
	if not session or count <= 0 then
		return
	end
	session.tokensBought += count
	session.pendingBought += count
	pushAttributes(player, session)
	log(string.format("GRANT %s: 주제 작성권 +%d -> %d개", player.Name, count, tokensOf(session)))
end

-- "다음 라운드에 내가 그리기" 예약을 넣어준다.
function PlayerStats.GrantDrawNext(player: Player)
	local session = sessions[player.UserId]
	if not session then
		return
	end
	session.drawNextBought += 1
	session.pendingDrawBought += 1
	pushAttributes(player, session)
	log(string.format("GRANT %s: 다음 판 그리기 예약 -> %d", player.Name, drawNextOf(session)))
end

-- 엿보기를 하나 넣어준다.
--
-- ⚠️ **항상 성공한다.** 지금 그리는 중이 아니어도 받아둔다.
--    "지금 못 쓰니까 안 받는다" 로 만들면, 라운드 끝나는 순간에 산 사람이
--    영영 못 받는다. 로블록스가 다시 물어봐도 계속 못 받으므로 돈만 잃는다.
--    받아뒀다가 다음에 그릴 때 쓰면 된다.
function PlayerStats.GrantPeek(player: Player)
	local session = sessions[player.UserId]
	if not session then
		return
	end
	session.peekBought += 1
	session.pendingPeekBought += 1
	pushAttributes(player, session)
	log(string.format("GRANT %s: 엿보기 -> %d개", player.Name, peekOf(session)))
end

function PlayerStats.HasPeek(player: Player): boolean
	local session = sessions[player.UserId]
	return session ~= nil and peekOf(session) > 0
end

-- 엿보기를 하나 쓴다. **실제로 열어준 뒤에** 부를 것.
function PlayerStats.UsePeek(player: Player): boolean
	local session = sessions[player.UserId]
	if not session or peekOf(session) <= 0 then
		return false
	end
	session.peekUsed += 1
	session.pendingPeekUsed += 1
	pushAttributes(player, session)
	return true
end

-- 예약해둔 것이 있는가.
function PlayerStats.HasDrawNext(player: Player): boolean
	local session = sessions[player.UserId]
	return session ~= nil and drawNextOf(session) > 0
end

-- 예약을 하나 쓴다. 없으면 false.
--
-- ⚠️ **실제로 뽑힌 뒤에** 부를 것. 미리 빼면 서버가 그 사이에 닫혔을 때
--    돈만 내고 못 그린 사람이 생긴다. 안 빼면 다음에 들어와서 그대로 쓴다.
function PlayerStats.UseDrawNext(player: Player): boolean
	local session = sessions[player.UserId]
	if not session or drawNextOf(session) <= 0 then
		return false
	end
	session.drawNextUsed += 1
	session.pendingDrawUsed += 1
	pushAttributes(player, session)
	return true
end

-- 남은 주제 작성권 개수.
function PlayerStats.GetTokens(player: Player): number
	local session = sessions[player.UserId]
	return if session then tokensOf(session) else 0
end

-- 작성권을 하나 쓴다. 없으면 false 를 돌려주고 아무것도 하지 않는다.
--
-- ⚠️ 있는지 보고 쓰는 일이 **한 함수 안에서** 끝나야 한다.
--    바깥에서 GetTokens 로 보고 따로 빼면, 그 사이에 또 부르는 것을 못 막는다.
function PlayerStats.SpendToken(player: Player): boolean
	local session = sessions[player.UserId]
	if not session then
		return false
	end

	-- **무료부터 쓴다.** 무료는 써야 다시 차기 시작하기 때문이다.
	-- 유료를 먼저 쓰면 무료가 손에 남아 그동안 적립이 멈춘다.
	local kind
	if freeTokensOf(session) > 0 then
		session.tokensSpent += 1
		session.pendingSpent += 1
		kind = "무료"
	elseif paidTokensOf(session) > 0 then
		session.paidSpent += 1
		session.pendingPaidSpent += 1
		kind = "유료"
	else
		return false
	end

	pushAttributes(player, session)
	log(string.format(
		"SPEND %s: %s 주제 작성권 -> 무료 %d / 유료 %d",
		player.Name, kind, freeTokensOf(session), paidTokensOf(session)
	))
	return true
end

-- 지금까지 쌓인 누적 점수. 리더보드에 보이는 그 값이다.
-- 5단계에서 프로 서버 자격을 볼 때 쓴다. (§2)
function PlayerStats.GetScore(player: Player): number
	local session = sessions[player.UserId]
	return if session then session.score else 0
end

-- 최근 판들의 별점 평균. 판수가 모자라면 nil.
-- ⚠️ 지금은 아무 데도 안 쓴다. 자격 판정은 GetScore 로 한다.
function PlayerStats.GetAverage(player: Player): number?
	local session = sessions[player.UserId]
	if not session or #session.recent < Config.PRO_MIN_ROUNDS then
		return nil
	end
	local total = 0
	for _, value in session.recent do
		total += value
	end
	return total / #session.recent
end

function PlayerStats.Start()
	local function onJoin(player: Player)
		local session = load(player)
		-- 불러오는 사이에 나갔을 수 있다. 그러면 붙일 곳이 없다.
		if player.Parent then
			buildLeaderstats(player, session)
			pushAttributes(player, session)
		end
	end

	-- 이 스크립트가 늦게 돌아도 이미 들어와 있는 사람을 놓치지 않는다.
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onJoin, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		-- ⚠️ 그냥 save(player) 한 번 부르고 지우면 안 된다.
		--    주기 저장이 진행 중이면 save 는 saving 검사에 걸려 **그냥 돌아간다.**
		--    그 상태에서 session 을 지우면, 진행 중인 저장이 떠간 뒤에 쌓인
		--    점수(마지막 라운드 결과일 가능성이 높다)가 통째로 사라진다.
		--
		--    그래서 진행 중인 저장이 끝날 때까지 기다렸다가 한 번 더 저장한다.
		local session = sessions[player.UserId]
		if session then
			for _ = 1, 100 do -- 최대 10초
				if not session.saving then
					break
				end
				task.wait(0.1)
			end
			save(player)
		end
		sessions[player.UserId] = nil
	end)

	-- 서버가 닫힐 때 마지막 판이 날아가지 않게 한다.
	-- 로블록스는 여기서 잠시 기다려준다.
	game:BindToClose(function()
		-- 한 명씩 차례로 저장하면 사람이 많을 때 주어진 시간을 다 못 쓴다.
		for _, player in Players:GetPlayers() do
			task.spawn(save, player)
		end
		-- spawn 한 저장이 끝날 틈을 준다.
		for _ = 1, 30 do
			local busy = false
			for _, player in Players:GetPlayers() do
				local session = sessions[player.UserId]
				if session and session.saving then
					busy = true
				end
			end
			if not busy then
				break
			end
			task.wait(0.1)
		end
	end)

	-- 서버가 죽는 방식은 여러 가지다. BindToClose 가 항상 불린다는 보장이 없으므로
	-- 주기적으로도 저장한다. 늘어난 게 없으면 아무 일도 하지 않는다.
	task.spawn(function()
		while true do
			task.wait(Config.STATS_AUTOSAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				task.spawn(save, player)
			end
		end
	end)
end

return PlayerStats
