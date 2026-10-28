--!strict
--[[
	RoundService.server.lua  —  라운드를 굴리는 서버 스크립트

	배치 위치: ServerScriptService. (.server.lua 라서 Rojo 가 Script 로 만든다)

	§1 의 라운드 흐름 중 2단계 몫만 담당한다.

		대기(WAITING)        3명이 안 모이면 여기서 멈춰 있는다
		  ↓
		인터미션(INTERMISSION) 15초
		  ↓
		그리기(DRAWING)      뽑힌 2명을 의자에 앉힌다
		  ↓                  서버 종류에 따라 3분 또는 5분
		  ↓                  둘 다 제출하면 시간이 남아도 끝난다
		심사(RATING)         관전자가 두 그림에 별 1~5개, 20초
		  ↓
		결과(RESULTS)        누가 이겼는지 5초 동안 보여준다
		  ↓                  별점 합산 → 승자 +5 (동점이면 무승부)
		다시 인터미션         일으켜 세우고 스폰으로

	**그림판은 의자에 앉은 사람에게만 뜬다.**
	뽑히는 것과 앉아 있는 것을 따로 보는 이유:
	뽑힌 뒤에 의자에서 일어나 돌아다니면서 그리면 이상하기 때문이다.
	일어나면 붓을 놓게 되고, 다시 앉으면 그리던 그림 그대로 이어서 그린다.

	심사(별점)와 정산은 4단계에서 그리기와 인터미션 사이에 끼워 넣는다.

	⚠️ 서버 권위 원칙 (README §3.4, §7-7)
	   누가 그릴 자격이 있는지, 제출을 했는지는 **전부 서버가 정한다.**
	   클라이언트의 `canvas:SetEnabled(false)` 는 편의 기능일 뿐이고
	   익스플로잇으로 우회된다. 3단계에서 스트로크를 받기 시작하면
	   받을 때마다 여기 있는 state.drawers 로 자격을 다시 검사해야 한다.
]]

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DrawerPicker = require(script.Parent.DrawerPicker)
local DrawSeats = require(script.Parent.DrawSeats)
local StrokeStore = require(script.Parent.StrokeStore)
local RatingStore = require(script.Parent.RatingStore)
local PlayerStats = require(script.Parent.PlayerStats)
local PurchaseService = require(script.Parent.PurchaseService)

local PHASE = Config.PHASE

local roundState = Remotes.event(Remotes.ROUND_STATE)
local submitDrawing = Remotes.event(Remotes.SUBMIT_DRAWING)
local requestState = Remotes.event(Remotes.REQUEST_STATE)
local sendStroke = Remotes.event(Remotes.SEND_STROKE)
local strokeAdded = Remotes.event(Remotes.STROKE_ADDED)
local requestCanvas = Remotes.event(Remotes.REQUEST_CANVAS)
local canvasSync = Remotes.event(Remotes.CANVAS_SYNC)
local sendRating = Remotes.event(Remotes.SEND_RATING)
local setOptOut = Remotes.event(Remotes.SET_OPT_OUT)
local submitPrompt = Remotes.event(Remotes.SUBMIT_PROMPT)
local promptResult = Remotes.event(Remotes.PROMPT_RESULT)
local toast = Remotes.event(Remotes.TOAST)

--------------------------------------------------------------------
-- 이 서버는 어떤 서버인가
--------------------------------------------------------------------

-- 3분 서버인지 5분 서버인지 프로 서버인지는 Workspace 의 "ServerMode" 속성으로 정한다.
-- 스튜디오에서 Workspace 를 고르고 속성 창 아래 '속성 추가' → 문자열 → ServerMode.
-- 값을 안 넣으면 Config.DEFAULT_SERVER_MODE 를 쓴다.
local function resolveMode()
	local name = Workspace:GetAttribute("ServerMode")
	if typeof(name) == "string" and Config.SERVER_MODES[name] then
		return Config.SERVER_MODES[name], name
	end
	return Config.SERVER_MODES[Config.DEFAULT_SERVER_MODE], Config.DEFAULT_SERVER_MODE
end

local mode, modeName = resolveMode()
-- 빌드 태그를 여기에 같이 찍는다.
-- 화면의 디버그 줄(Config.UI.SHOW_DEBUG)은 평소에 꺼두므로, 이게 없으면
-- "고쳤는데 안 고쳐졌다"의 원인이 코드인지 동기화인지 가릴 방법이 없다. (§5.5-7)
print(string.format(
	"[RoundService] build=%s | server mode = %s (%s, %d seconds to draw)",
	Config.BUILD_TAG, modeName, mode.label, mode.drawSeconds
))

--------------------------------------------------------------------
-- 상태
--------------------------------------------------------------------

local picker = DrawerPicker.new()
local strokes = StrokeStore.new()
local ratings = RatingStore.new()

local state = {
	phase = PHASE.WAITING,
	-- 이 단계가 언제 끝나는지. Workspace:GetServerTimeNow() 와 같은 시계를 쓴다.
	-- "남은 초" 대신 "끝나는 시각" 을 보내는 이유:
	-- 남은 초를 보내면 1초마다 계속 보내야 하지만, 끝나는 시각은 한 번만 보내면
	-- 클라이언트가 알아서 세어 내려간다. 네트워크를 훨씬 덜 쓴다.
	endsAt = 0,
	prompt = nil :: string?,
	drawers = {} :: { number }, -- 이번 라운드에 뽑힌 사람 (userId)
	-- 관전 버튼에 이름을 띄워야 하므로 같이 보낸다. drawers 와 순서가 같다.
	drawerNames = {} :: { string },
	-- 지금 실제로 의자에 앉아 있는 사람. drawers 와 다를 수 있다.
	-- 뽑혔는데 일어나서 돌아다니는 경우가 그렇다.
	seated = {} :: { number },
	submitted = {} :: { [number]: boolean },
	-- 직전 라운드 결과. 인터미션 동안 화면에 띄운다.
	results = nil :: any,
	-- "나는 안 그리겠다" 를 선언한 사람. [userId] = true
	--
	-- 서버에만 둔다. 클라이언트가 보낸 값을 그대로 믿지 않는다.
	-- 남의 선언을 대신 켜고 끄는 것도 여기서 막힌다. (§3.4)
	optedOut = {} :: { [number]: boolean },
	-- 이번 라운드에 엿보기를 쓴 사람. 라운드마다 비운다.
	peeking = {} :: { [number]: boolean },
	-- 다음 라운드에 쓸 주제. 누군가 작성권으로 정해두면 여기 들어온다.
	--
	-- 작성권은 **여기 넣는 순간** 깎인다. (§2, submitPrompt 참고)
	-- 이름(authorName)도 그때 같이 적어둔다. 라운드가 시작될 때 찾으면
	-- 그 사이에 나간 사람의 이름은 알 수가 없다.
	nextPrompt = nil :: { userId: number, text: string, authorName: string }?,
	-- 이번 라운드 주제를 누가 정했는가. 딕셔너리에서 뽑았으면 nil.
	-- 화면이 이걸 보고 "뽑기 연출" 과 "누구의 주제" 연출 중 하나를 고른다.
	promptAuthor = nil :: string?,
}

-- 맵에 놓인 그리기용 의자. 라운드마다 다시 찾는다.
-- 개발 중에 맵을 고쳐도 서버를 껐다 켤 필요가 없다.
local seats: { Seat } = {}

local function enoughPlayers(): boolean
	return #Players:GetPlayers() >= Config.MIN_PLAYERS_TO_START
end

-- 지금 그릴 수 있는 사람들. 안 그리기를 선언한 사람은 빠진다.
local function drawCandidates(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if not state.optedOut[player.UserId] then
			table.insert(list, player)
		end
	end
	return list
end

-- 실제로 뽑기를 돌릴 후보.
--
-- **직전 라운드에 그린 사람은 뺀다.** 연달아 두 판을 그리면
-- 옆에서 기다리던 사람은 이유를 알 수 없이 계속 밀린다.
-- 가중치만으로는 이걸 못 막는다. 뽑힌 사람이 1로 돌아갈 뿐 0 이 되지는 않아서,
-- 3명·2자리면 방금 그린 사람이 다음 판에도 58% 로 뽑힌다.
--
-- 다만 빼고 나서 자리를 채울 만큼 남지 않으면 도로 넣는다.
-- 3명뿐인 서버에서 둘을 빼면 한 명만 남아 라운드가 영영 안 열린다.
-- 그때는 연달아 그리는 것이 "덜 나쁜 쪽" 이다.
--
-- ⚠️ state.drawers 는 다음 라운드가 시작될 때까지 안 비워진다.
--    그래서 이 함수는 부르는 때에 따라 알아서 맞는 답을 준다.
--      라운드 중  — 지금 그리는 사람을 뺀 목록 (= 다음 판 후보)
--      startRound — 직전에 그린 사람을 뺀 목록 (아직 안 비웠으므로)
--    화면에 보여주는 확률과 실제 뽑기가 **같은 함수**를 쓰게 하려는 것이다.
--    두 곳에 따로 적으면 반드시 어긋난다. (README §5.5-3)
local function pickPool(): { Player }
	local all = drawCandidates()
	local fresh: { Player } = {}
	for _, player in all do
		if not table.find(state.drawers, player.UserId) then
			table.insert(fresh, player)
		end
	end
	if #fresh >= Config.DRAWERS_PER_ROUND then
		return fresh
	end
	return all
end

-- 확정: 안 그리기 선언 때문에 그릴 사람이 모자라면 라운드를 시작하지 않는다. (§2)
-- 선언을 무시하고 뽑으면 버튼이 거짓말을 하는 셈이 된다.
local function enoughDrawers(): boolean
	return #drawCandidates() >= Config.MIN_AVAILABLE_DRAWERS
end

-- 사람마다 다른 값이라 한 덩어리로 묶어서 같이 보낸다.
--   chance   다음 라운드에 뽑힐 확률 (0~1). 막대와 숫자 둘 다 이 값을 쓴다.
--   optedOut 안 그리기를 선언했는가
--
-- 모두에게 같은 내용을 보내는 FireAllClients 하나로 끝내려고 전원 몫을 다 싣는다.
-- 사람당 숫자 두 개라 인원이 늘어도 부담이 안 된다.
-- 사람마다 다른 값이라 한 덩어리로 묶어서 같이 보낸다.
--   progress 차례 진행도 (0~1). 막대와 숫자 둘 다 이 값을 쓴다.
--   optedOut 안 그리기를 선언했는가
--   booked   "다음 라운드에 내가 그리기" 자리 주인으로 세는가 (품절 계산용, 최대 DRAW_NEXT_SEATS 명)
--   hasDrawNext 예약을 들고 있는가 (게이지 100%, Sit out 잠금)
--   peeking  이번 라운드에 엿보기를 쓰고 있는가
--
-- 모두에게 같은 내용을 보내는 FireAllClients 하나로 끝내려고 전원 몫을 다 싣는다.
-- 사람당 숫자 하나라 인원이 늘어도 부담이 안 된다.
--
-- ⚠️ 여기 오는 값은 **확률이 아니라 진행도다.** (DrawerPicker.ProgressFor 참고)
--    확률은 몇 명이 다투느냐에 따라 달라져서, 아무것도 안 했는데
--    누가 들어왔다는 이유로 숫자가 떨어진다. 진행도는 인원과 상관없다.
local function drawInfo()
	-- 상점의 "품절" 을 정할 자리 주인. **DRAW_NEXT_SEATS 명까지만** 찍는다.
	-- 뽑는 쪽(startRound)이 그만큼만 받기 때문이다. 같은 규칙은 같은 숫자를 봐야 한다.
	--
	-- 예약자는 쉴 수 없으니(SET_OPT_OUT) 전원을 훑어도 후보를 훑는 것과 같다.
	-- 예약이 정원보다 많으면(다른 서버에서 사 온 사람) 누가 그릴지는 startRound 가 무작위로 정한다.
	-- 여기 찍히는 두 명은 "품절인가" 를 세는 용도일 뿐, 그 두 명이 그린다는 뜻이 아니다.
	local booked: { [Player]: boolean } = {}
	local count = 0
	for _, player in Players:GetPlayers() do
		if count >= Config.DRAW_NEXT_SEATS then
			break
		end
		if PlayerStats.HasDrawNext(player) then
			booked[player] = true
			count += 1
		end
	end

	local info = {}
	for _, player in Players:GetPlayers() do
		local hasDrawNext = PlayerStats.HasDrawNext(player)
		info[tostring(player.UserId)] = {
			-- 예약이 있으면 게이지는 **무조건 100%** 다. (확정 2026-10-27)
			-- 나갔다 들어와도 그대로다. 예약은 DataStore 에 남기 때문이다.
			-- 실제로 그리고 나면 예약이 차감되어 원래 진행도(방금 그렸으니 0%)로 돌아간다.
			--
			-- 위의 booked 가 아니라 HasDrawNext 를 직접 본다. 정원을 넘친 사람도
			-- 예약은 들고 있으므로 똑같이 100% 다. 그 셋 중 누가 그릴지는 무작위다.
			--
			-- 예약이 없으면 평소 진행도다. 안 그리기를 선언한 사람에게도 그대로 보여준다.
			-- 쉬는 동안에도 가중치는 오르므로 이 값도 계속 오른다.
			-- 0 으로 만들면 그동안 쌓인 것이 사라진 것처럼 보인다.
			progress = if hasDrawNext then 1 else picker:ProgressFor(player.UserId),
			optedOut = state.optedOut[player.UserId] == true,
			booked = booked[player] == true,
			-- 예약을 들고 있는가. 화면은 이걸 보고 Sit out 버튼을 잠근다.
			-- 클라이언트도 DrawNextBooked 특성으로 알 수 있지만, 게이지 100% 와 **같은 소식에**
			-- 실어 보내야 "게이지는 100% 인데 버튼은 안 잠긴" 순간이 안 생긴다.
			-- 특성과 이벤트는 따로 도착해서 순서가 보장되지 않는다.
			hasDrawNext = hasDrawNext,
			peeking = state.peeking[player.UserId] == true,
		}
	end
	return info
end

local function isDrawer(userId: number): boolean
	return table.find(state.drawers, userId) ~= nil
end

-- viewer 가 author 의 그림을 볼 수 있는가.
--
-- ⚠️ 이 판단을 **서버가** 해야 한다.
--    예전에는 모든 선을 FireAllClients 로 전원에게 뿌리고 화면에서만 가렸다.
--    그러면 엿보기가 "가려둔 것을 걷어내는" 일이 되어, 익스플로잇으로
--    **공짜로 볼 수 있다.** 돈 받는 기능이라 더더욱 그러면 안 된다. (§3.4)
--
-- 규칙
--   내 그림은 언제나 본다.
--   관전자는 다 본다. (원래 그러라고 있는 사람들이다)
--   그리는 사람은 **그리는 동안** 상대 그림을 못 본다. 엿보기를 산 사람만 본다.
--   심사(RATING)부터는 그린 사람도 상대 그림을 본다. (§1)
local function canSee(viewerUserId: number, authorUserId: number): boolean
	if viewerUserId == authorUserId then
		return true
	end
	if state.phase ~= PHASE.DRAWING then
		return true
	end
	if not isDrawer(viewerUserId) then
		return true
	end
	return state.peeking[viewerUserId] == true
end

local function submittedList(): { number }
	local list = {}
	for userId in state.submitted do
		table.insert(list, userId)
	end
	return list
end

local function snapshot()
	return {
		phase = state.phase,
		endsAt = state.endsAt,
		prompt = state.prompt,
		-- 이번 주제를 누가 정했는가. nil 이면 딕셔너리에서 뽑은 것이다.
		-- ⚠️ 다음 라운드 주제(nextPrompt)의 낱말은 여전히 안 보낸다.
		--    이건 **지금 그리는** 주제의 주인이라 이미 공개된 정보다.
		promptAuthor = state.promptAuthor,
		drawers = table.clone(state.drawers),
		drawerNames = table.clone(state.drawerNames),
		seated = table.clone(state.seated),
		submitted = submittedList(),
		results = state.results,
		modeLabel = mode.label,
		playerCount = #Players:GetPlayers(),
		minPlayers = Config.MIN_PLAYERS_TO_START,
		drawInfo = drawInfo(),
		-- 그릴 사람이 모자라서 못 여는 상태인가. 화면에 이유를 띄우려고 같이 보낸다.
		-- ⚠️ "그릴 사람이 없다" 는 **사람이 충분할 때만** 맞는 말이다.
		--    혼자 접속하면 후보도 1명이라 enoughDrawers 가 거짓이 되는데,
		--    그때 "Waiting for someone to draw" 를 띄우면 사람이 모자란 것을
		--    다들 안 그리겠다고 한 것처럼 보여준다. 실제로 그렇게 떴다.
		waitingForDrawers = enoughPlayers() and not enoughDrawers(),
		-- 다음 라운드 주제가 이미 정해졌는가. 상점에서 "이미 임자가 있다" 를 보여준다.
		-- 글자 자체는 안 보낸다. 미리 알면 혼자 연습하고 들어올 수 있다. (§3.1)
		nextPromptOwner = if state.nextPrompt then state.nextPrompt.userId else nil,
	}
end

local function broadcast()
	roundState:FireAllClients(snapshot())
end

-- 의자에 누가 앉아 있는지 다시 읽는다. 바뀌었을 때만 알린다.
local function refreshSeated()
	local current: { number } = {}
	for _, seat in seats do
		local player = DrawSeats.occupant(seat)
		if player then
			table.insert(current, player.UserId)
		end
	end

	-- 목록이 그대로면 아무것도 하지 않는다.
	-- 앉고 일어나는 신호는 자주 오는데, 그때마다 전원에게 보낼 이유가 없다.
	local same = #current == #state.seated
	if same then
		for i, userId in current do
			if state.seated[i] ~= userId then
				same = false
				break
			end
		end
	end
	if same then
		return
	end

	state.seated = current
	broadcast()
end

-- 의자를 다시 찾고, 앉고 일어나는 것을 지켜본다.
local function bindSeats()
	for _, seat in seats do
		if seat:GetAttribute("DrawBattleBound") then
			continue -- 이미 지켜보고 있다
		end
		seat:SetAttribute("DrawBattleBound", true)
		seat:GetPropertyChangedSignal("Occupant"):Connect(refreshSeated)
	end
end

local function refreshSeats()
	seats = DrawSeats.find()
	bindSeats()
end

local function setPhase(phase: string, duration: number?)
	state.phase = phase
	state.endsAt = if duration then Workspace:GetServerTimeNow() + duration else 0
	broadcast()
end

--------------------------------------------------------------------
-- 클라이언트가 보내오는 것
--------------------------------------------------------------------

submitDrawing.OnServerEvent:Connect(function(player: Player)
	-- 클라이언트가 보낸 것은 전부 의심한다. 세 가지를 전부 서버가 확인한다.
	if state.phase ~= PHASE.DRAWING then
		return -- 그리는 중이 아닌데 제출
	end
	if not isDrawer(player.UserId) then
		return -- 그리는 사람이 아닌데 제출
	end
	if state.submitted[player.UserId] then
		return -- 이미 제출했다. 취소도 재제출도 없다. (§2 확정)
	end

	state.submitted[player.UserId] = true
	broadcast()
end)

requestState.OnServerEvent:Connect(function(player: Player)
	roundState:FireClient(player, snapshot())
end)

sendStroke.OnServerEvent:Connect(function(player: Player, data: any)
	-- 자격을 먼저 본다. 검사에 드는 비용이 훨씬 크기 때문이다.
	if state.phase ~= PHASE.DRAWING then
		return
	end
	if not isDrawer(player.UserId) then
		return -- 관전자가 보낸 선. 화면에 뿌리면 안 된다.
	end
	if state.submitted[player.UserId] then
		return -- 제출한 뒤에 몰래 더 그리는 것도 막는다.
	end

	-- 여기서 값 자체를 검사한다. 통과 못 하면 조용히 버린다.
	if not strokes:Add(player.UserId, data) then
		return
	end

	-- 통과한 것만, 그것도 서버가 새로 담은 표를 넘긴다.
	--
	-- ⚠️ FireAllClients 가 아니다. 상대 그림을 볼 자격이 없는 사람에게는
	--    **데이터 자체를 안 보낸다.** 안 그러면 엿보기가 공짜가 된다.
	local stroke = strokes:Get(player.UserId)[strokes:Count(player.UserId)]
	for _, viewer in Players:GetPlayers() do
		if canSee(viewer.UserId, player.UserId) then
			strokeAdded:FireClient(viewer, player.UserId, stroke)
		end
	end
end)

sendRating.OnServerEvent:Connect(function(player: Player, targetUserId: any, stars: any)
	if state.phase ~= PHASE.RATING then
		return -- 심사 시간이 아닐 때 보낸 것
	end
	if typeof(targetUserId) ~= "number" then
		return
	end
	-- 나머지 검사(관전자인가, 대상이 그린 사람인가, 별이 1~5 정수인가)는
	-- RatingStore 가 한다. 판정에 쓰이는 값이라 한곳에 모아둔다.
	ratings:Rate(player.UserId, targetUserId, stars, state.drawers)
end)

-- 사둔 엿보기가 있으면 지금 열어준다. 열어준 뒤에 차감한다.
--
-- ⚠️ 순서가 중요하다. 먼저 빼고 열다가 실패하면 돈만 없어진다.
--    반대로 두면 최악의 경우 한 번 더 보여주고 마는데, 그쪽이 훨씬 낫다.
local function applyPeek(player: Player)
	if state.phase ~= PHASE.DRAWING then
		return -- 지금은 쓸 때가 아니다. 다음에 그릴 때 쓴다.
	end
	if not isDrawer(player.UserId) then
		return -- 관전자는 원래 공짜로 본다. 쓸 이유가 없다.
	end
	if state.peeking[player.UserId] then
		return -- 이번 라운드에 이미 열려 있다
	end
	if not PlayerStats.HasPeek(player) then
		return
	end

	state.peeking[player.UserId] = true
	-- 지금까지 그려진 것을 한꺼번에 보내준다.
	-- 여는 순간부터의 선만 보내면 빈 종이에서 시작하게 된다.
	for _, targetUserId in state.drawers do
		if targetUserId ~= player.UserId then
			canvasSync:FireClient(player, targetUserId, strokes:Get(targetUserId))
		end
	end
	PlayerStats.UsePeek(player)
	broadcast()
end

-- 그리는 도중에 산 사람도 그 자리에서 열리게 한다.
-- PlayerStats 가 살 때마다 이 특성을 고치므로, 그걸 신호로 쓴다.
local function watchPeek(player: Player)
	applyPeek(player)
	player:GetAttributeChangedSignal("PeekPending"):Connect(function()
		applyPeek(player)
	end)
end

for _, player in Players:GetPlayers() do
	watchPeek(player)
end
Players.PlayerAdded:Connect(watchPeek)

-- "다음 라운드에 내가 그리기" 예약이 생기거나 쓰이면 **바로 전원에게 다시 알린다.**
--
-- 예약은 게이지(100%)와 상점의 "품절" 을 바꾼다. 둘 다 drawInfo 로 간다.
-- 그런데 drawInfo 는 broadcast 할 때만 나간다. 구매는 라운드 단계와 상관없이
-- 아무 때나 일어나므로, 여기서 안 보내면 **다음 단계가 바뀔 때까지** 옛 화면이 남는다.
--
-- ⚠️ 실제로 그랬다. 두 번째로 산 사람의 게이지가 100% 로 안 찼다. (2026-10-27 테스트)
--    서버는 제대로 예약을 받아서 다음 판에 그 사람을 앉혔다. **화면만 옛날 것이었다.**
--    예전 함수는 "Sit out 중일 때만" 보냈다. 첫 번째 사람이 멀쩡해 보였던 것은
--    그 사람이 그때 Sit out 중이었거나, 마침 다른 일로 broadcast 가 나갔기 때문으로 보인다.
--    **가끔 맞는 버그가 제일 늦게 잡힌다.**
--
-- 그리고 **쉬는 중에 샀으면 쉬기를 푼다.** (2026-10-27)
-- 예약이 있는 동안은 쉬기가 금지라서(SET_OPT_OUT), 둘이 겹친 채로 두면 규칙이 깨진다.
-- 산 것 자체가 "그리겠다" 는 뜻이므로 그 뜻을 따른다.
-- (구매 버튼을 쉬는 동안 막는 방법도 있었지만, 로벅스 결제는 서버가 중간에 못 끊는다.
--  화면에서 막아도 결제가 되어버리는 틈이 있으니 서버에서 정리하는 쪽이 확실하다)
--
-- PurchaseService 가 broadcast 를 직접 부르지 않는 이유:
--   구매 모듈이 라운드 모듈을 알게 되면 둘이 서로 얽힌다.
--   PlayerStats 는 특성(DrawNextBooked)만 바꾸고, 그걸 보고 싶은 쪽이 알아서 본다.
--   나중에 예약을 넣는 길이 또 생겨도(보상, 운영자 지급 등) 여기 하나로 다 잡힌다.
local function watchBooking(player: Player)
	player:GetAttributeChangedSignal("DrawNextBooked"):Connect(function()
		if PlayerStats.HasDrawNext(player) then
			state.optedOut[player.UserId] = nil
		end
		broadcast()
	end)
end

for _, player in Players:GetPlayers() do
	watchBooking(player)
end
Players.PlayerAdded:Connect(watchBooking)

-- 유저가 친 글자를 로블록스 필터에 통과시킨다.
--
-- ⚠️ **선택이 아니라 정책 의무다.** (§3.1)
--    필터를 안 거친 유저 글자를 남의 화면에 띄우면 게임이 내려갈 수 있다.
--
-- 걸러진 결과에 # 이 섞이면 아예 거절한다.
-- 로블록스는 걸리는 낱말을 # 으로 바꿔주는데, 주제가 "###" 이 되면
-- 그림을 그릴 수가 없다. 통과한 것만 쓴다.
local function filterPrompt(player: Player, text: string): (string?, string)
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		-- 필터가 대답을 안 하면 **통과시키지 않는다.**
		-- 못 걸렀는데 그냥 쓰는 것보다 한 번 더 해달라고 하는 편이 낫다.
		warn("[RoundService] 주제 필터 실패: " .. tostring(filtered))
		return nil, "Could not check that word. Try again."
	end
	-- ⚠️ 필터가 실제로 무엇을 돌려줬는지 찍어둔다.
	--    스튜디오와 게시된 게임에서 결과가 다를 수 있어서,
	--    안 걸러진 것이 **코드 탓인지 환경 탓인지** 구분할 데가 필요하다.
	print(string.format("[RoundService] 필터: \"%s\" -> \"%s\"", text, tostring(filtered)))

	if typeof(filtered) ~= "string" or filtered:find("#") then
		return nil, "That word is not allowed."
	end
	return filtered, ""
end

-- 지금 주제를 보내는 중인 사람. 연타와 끼어들기를 막는다.
--
-- ⚠️ 이게 왜 필요한가
--    filterPrompt 는 로블록스에 물어보는 일이라 **중간에 멈춘다.**
--    멈춘 사이에 다른 사람이 들어와서 같은 검사를 통과해버린다.
--    그러면 둘 다 티켓을 내고 나중 사람이 덮어써서, 먼저 낸 사람은
--    티켓도 주제도 잃는다. 오류 한 줄 못 받고 사라진다.
--    같은 사람이 두 번 누르면 한 자리에 두 장이 나가기도 했다.
--
--    검사하고 나서 반영하기까지 멈추는 구간이 있으면,
--    그 구간을 **미리 잠가야** 한다. (README §5.5-14)
local promptBusy: { [number]: boolean } = {}
local promptClaim: number? = nil

submitPrompt.OnServerEvent:Connect(function(player: Player, raw: any)
	local function reply(ok: boolean, message: string)
		-- 기다리는 사이에 나갔을 수 있다. 나간 사람에게 보내면 오류가 난다.
		if player.Parent then
			promptResult:FireClient(player, ok, message)
		end
	end

	if typeof(raw) ~= "string" then
		return -- 글자가 아니면 조용히 버린다
	end
	if promptBusy[player.UserId] then
		return -- 아직 앞의 것을 처리하는 중이다. 연타는 버린다.
	end

	-- 앞뒤 공백을 떼고, 사이의 연속 공백은 하나로 줄인다.
	local text = raw:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")

	-- ⚠️ 글자 수는 utf8.len 으로 센다. **# 은 바이트를 센다.**
	--    # 로 재면 한글 한 글자가 3으로 잡혀서, 24자 제한이 한글 8자가 된다.
	--    utf8.len 은 깨진 글자에 nil 을 돌려주므로 그것도 같이 걸러진다.
	local length = utf8.len(text)
	if not length then
		reply(false, "That text can't be used.")
		return
	end
	if length < Config.PROMPT_MIN_LENGTH or length > Config.PROMPT_MAX_LENGTH then
		reply(false, string.format(
			"Theme must be %d-%d characters.",
			Config.PROMPT_MIN_LENGTH, Config.PROMPT_MAX_LENGTH
		))
		return
	end

	-- 확정: **한 번 정하면 못 고친다.** 라운드당 한 자리이고, 그 자리는 한 번만 팔린다.
	--
	-- 본인이 정한 것도 못 고친다. 고칠 수 있게 두면
	-- "티켓 없이 몇 번이고 바꾸는" 길이 생기고, 그 길마다 규칙을 또 세워야 한다.
	-- 한 번으로 끝내면 설명할 것이 한 줄이다.
	if state.nextPrompt then
		local mine = state.nextPrompt.userId == player.UserId
		reply(false, if mine
			then "You already set the next theme."
			else "Someone already set the next theme.")
		return
	end
	if promptClaim ~= nil then
		reply(false, "Someone is setting the theme right now.")
		return
	end

	if PlayerStats.GetTokens(player) <= 0 then
		reply(false, "You need a theme ticket.")
		return
	end

	-- 여기서부터 멈출 수 있다. 자리를 잠그고 들어간다.
	promptBusy[player.UserId] = true
	promptClaim = player.UserId

	local clean, why = filterPrompt(player, text)

	promptBusy[player.UserId] = nil
	promptClaim = nil

	if not clean then
		-- 걸러져서 거절당한 낱말에는 티켓을 안 물린다.
		reply(false, why)
		return
	end

	-- ⚠️ 멈췄다 돌아왔으므로 **한 번 더 본다.**
	--    잠가두긴 했지만, 그 사이에 라운드가 시작되면서 주제가 쓰였을 수도 있고
	--    다른 경로로 상태가 바뀌었을 수도 있다. 값을 깎기 직전에 다시 확인한다.
	if state.nextPrompt then
		reply(false, "Someone already set the next theme.")
		return
	end

	-- 확정: 티켓은 **주제를 넣는 순간** 깎는다. (§2)
	if not PlayerStats.SpendToken(player) then
		reply(false, "You need a theme ticket.")
		return
	end

	state.nextPrompt = { userId = player.UserId, text = clean, authorName = player.DisplayName }
	reply(true, clean)

	-- 낱말은 안 보낸다. 미리 알면 혼자 연습하고 들어올 수 있다. (§3.1)
	-- 누가 정했는지는 알려도 된다. 티켓을 쓴 사람이라 드러나는 편이 낫다.
	--
	-- 고치기가 없으므로 이 알림은 라운드당 한 번뿐이다. 도배될 수가 없다.
	toast:FireAllClients(string.format("%s set the next theme!", player.DisplayName))

	broadcast()
end)

setOptOut.OnServerEvent:Connect(function(player: Player, wantsOut: any)
	-- 보낸 사람 본인의 것만 바꾼다. userId 를 받지 않는 이유가 이것이다.
	-- 받으면 남의 선언을 대신 켜고 끌 수 있게 된다. (§3.4)
	if typeof(wantsOut) ~= "boolean" then
		return
	end

	-- 지금 **그리고 있는 중인** 사람만 못 바꾼다.
	-- 눌러도 이번 판이 취소되지는 않으므로 버튼이 거짓말을 하게 되기 때문이다.
	--
	-- ⚠️ isDrawer 만 보면 안 된다. state.drawers 는 **다음 라운드가 시작될 때까지
	--    안 비워진다.** 그래서 인터미션 동안에도 방금 그린 두 사람은 여전히
	--    isDrawer 로 잡히고, 그 사이에 누른 것이 여기서 조용히 버려졌다.
	--    하필 "방금 그렸으니 이제 쉬자" 고 누르는 순간이라 제일 눌리고 싶을 때다.
	--    화면에는 버튼이 멀쩡히 보이는데 아무 일도 안 일어났다.
	--
	--    단계까지 같이 봐야 한다. 인터미션에 누르는 것은 다음 판 이야기라 정상이다.
	if state.phase == PHASE.DRAWING and isDrawer(player.UserId) then
		return
	end

	-- "다음 판 그리기" 를 사둔 사람은 쉬러 갈 수 없다. (확정 2026-10-27 개발자 결정)
	-- 돈을 내고 "그리겠다" 고 한 사람이다. 예약과 쉬기가 겹치면
	-- 예약은 안 쓰인 채 남고, 그 사이 남들은 품절이라 못 사는 이상한 상태가 생긴다.
	-- 화면 버튼도 잠기지만 그건 편의일 뿐이고, 진짜 잠금은 여기다. (§3.4)
	--
	-- 돌아오는 쪽(wantsOut == false)은 막지 않는다. 어떤 이유로든 둘이 겹치면
	-- 돌아올 길까지 막혀서 갇힌다.
	if wantsOut and PlayerStats.HasDrawNext(player) then
		return
	end

	if state.optedOut[player.UserId] == wantsOut then
		return -- 바뀐 게 없다. 괜히 다시 뿌리지 않는다.
	end
	state.optedOut[player.UserId] = if wantsOut then true else nil

	-- 이 선언 하나로 라운드를 열 수 있는지가 바뀔 수 있다.
	-- 화면의 게이지와 안내 문구도 같이 바뀌므로 바로 알린다.
	broadcast()
end)

requestCanvas.OnServerEvent:Connect(function(player: Player, targetUserId: any)
	-- 아무 숫자나 넣어 남의 그림을 뒤지지 못하도록, 이번 라운드에
	-- 그리는 사람의 것만 내준다.
	if typeof(targetUserId) ~= "number" or not isDrawer(targetUserId) then
		return
	end
	-- 선 하나하나를 막아놓고 여기를 열어두면 아무 소용이 없다. 같은 규칙을 쓴다.
	if not canSee(player.UserId, targetUserId) then
		return
	end
	canvasSync:FireClient(player, targetUserId, strokes:Get(targetUserId))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	picker:Forget(player.UserId)
	state.submitted[player.UserId] = nil
	-- 안 지우면 서버가 도는 내내 쌓이고, 같은 userId 로 다시 들어온 사람이
	-- 누른 적도 없는 "안 그리기" 상태로 시작하게 된다.
	state.optedOut[player.UserId] = nil
	-- 주제를 보내다 나간 사람의 표식을 안 지우면, 같은 자리에 다시 들어온
	-- 사람이 "처리 중" 으로 잡혀서 영영 못 보낸다.
	promptBusy[player.UserId] = nil
	if promptClaim == player.UserId then
		promptClaim = nil
	end

	local index = table.find(state.drawers, player.UserId)
	if index then
		-- 그리던 사람이 나갔다. 남은 사람만으로 계속 진행한다.
		table.remove(state.drawers, index)
		table.remove(state.drawerNames, index)
	end
	broadcast()
end)

--------------------------------------------------------------------
-- 라운드 진행
--------------------------------------------------------------------

-- 라운드가 끝나면 전원을 스폰 지점으로 되돌린다.
--
-- 한 점에 그대로 놓으면 캐릭터끼리 겹쳐서 서로 밀어낸다.
-- 원을 그리며 조금씩 흩어 놓으면 그런 일이 없다.
local function sendEveryoneToSpawn()
	local spawnPart: BasePart? = nil
	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") then
			spawnPart = instance
			break
		end
	end
	if not spawnPart then
		warn("[RoundService] No SpawnLocation found in Workspace. Skipping return-to-spawn.")
		return
	end

	local players = Players:GetPlayers()
	for index, player in players do
		local character = player.Character
		if not character or not character.PrimaryPart then
			continue -- 아직 캐릭터가 없거나 죽은 사람
		end
		local angle = (index / #players) * math.pi * 2
		local offset = Vector3.new(
			math.cos(angle) * Config.SPAWN_SPREAD_RADIUS,
			3, -- 바닥에 끼지 않도록 살짝 띄운다
			math.sin(angle) * Config.SPAWN_SPREAD_RADIUS
		)
		pcall(function()
			character:PivotTo(CFrame.new(spawnPart.Position + offset))
		end)
	end
end


local function allDrawersSubmitted(): boolean
	if #state.drawers == 0 then
		return false
	end
	for _, userId in state.drawers do
		if not state.submitted[userId] then
			return false
		end
	end
	return true
end

-- 사람이 모자라거나, 그릴 사람이 모자라면 여기서 기다린다.
--
-- 둘은 다른 조건이다. 다섯 명이 있어도 넷이 안 그리기를 선언했으면
-- 그릴 사람은 하나뿐이라 라운드를 열 수 없다.
local function canStart(): boolean
	return enoughPlayers() and enoughDrawers()
end

local function waitForPlayers()
	if canStart() then
		return
	end

	state.prompt = nil
	state.promptAuthor = nil
	table.clear(state.drawers)
	table.clear(state.drawerNames)
	table.clear(state.submitted)
	strokes:Reset()
	refreshSeats()
	setPhase(PHASE.WAITING)

	while not canStart() do
		task.wait(1)
		-- 몇 명 모였는지 화면에 보여주려면 인원이 바뀔 때마다 알려야 한다.
		broadcast()
	end
end

-- 지금 단계가 끝날 때까지 기다린다.
-- shouldStopEarly 가 true 를 돌려주면 시간이 남아도 그만둔다.
local function waitForPhase(shouldStopEarly: (() -> boolean)?)
	while Workspace:GetServerTimeNow() < state.endsAt do
		if not enoughPlayers() then
			return
		end
		if shouldStopEarly and shouldStopEarly() then
			return
		end
		task.wait(0.2)
	end
end

local function startRound()
	refreshSeats()
	if #seats < Config.DRAWERS_PER_ROUND then
		warn(string.format(
			"[RoundService] Found %d drawing seat(s) but need %d. "
				.. "Place Seat parts in Workspace (optionally tag them '%s').",
			#seats, Config.DRAWERS_PER_ROUND, Config.DRAW_SEAT_TAG
		))
	end

	-- "다음 라운드에 내가 그리기" 를 사둔 사람에게 자리를 먼저 준다.
	--
	-- **DRAW_NEXT_SEATS 명까지.** (§3.2) 지금은 2명이라 두 자리를 다 살 수 있다.
	--    정해진 수보다 많이 사뒀으면 넘친 사람은 예약이 남아 그다음 판에 쓴다.
	--    (쓸 때 차감하므로 그냥 남아 있다)
	--
	-- ⚠️ 예약자는 pickPool 이 아니라 drawCandidates 에서 찾는다.
	--    pickPool 은 "직전에 그린 사람" 을 빼는데, 그러면 그리는 도중에 산 사람이
	--    **자기가 방금 그렸다는 이유로 한 판 밀린다.** "다음 라운드" 라고 하고 팔았으니
	--    그건 약속을 어긴 것이다. 돈을 낸 쪽이 이겨야 한다.
	local bookers: { Player } = {}
	for _, player in drawCandidates() do
		if PlayerStats.HasDrawNext(player) then
			table.insert(bookers, player)
		end
	end

	-- 예약이 정원보다 많으면 **그 안에서 무작위로** 고른다. (확정 2026-10-27 개발자 결정)
	--
	-- 한 서버 안에서는 품절 때문에 정원을 못 넘지만, 예약은 DataStore 에 남아서
	-- **다른 서버에서 산 사람이 들고 들어올 수 있다.** 그러면 100% 가 셋이 된다.
	--
	-- 예전에는 들어온 순서(GetPlayers 순서)로 잘랐다. 그러면 **늘 먼저 온 사람이 이긴다.**
	-- 화면에는 셋 다 똑같이 100% 로 보이니, 같은 확률로 고르는 것이 화면과 맞다.
	-- 가중치 뽑기(picker)를 안 쓰는 이유도 같다. 가중치는 화면에 안 보이는 값이라
	-- 똑같이 100% 인데 누구는 더 잘 뽑히는 것처럼 된다.
	--
	-- 떨어진 사람의 예약은 **안 쓰였으므로 그대로 남는다.** 다음 판에 또 100% 로 다툰다.
	-- 하나씩 무작위로 빼는 것은 남은 사람 모두에게 같은 확률을 준다.
	local bookerSeats = math.min(Config.DRAW_NEXT_SEATS, Config.DRAWERS_PER_ROUND)
	while #bookers > bookerSeats do
		table.remove(bookers, math.random(#bookers))
	end

	local chosen: { Player } = {}
	local seatsLeft = Config.DRAWERS_PER_ROUND
	for _, player in bookers do
		table.insert(chosen, player)
		seatsLeft -= 1
	end

	-- 남은 자리는 평범하게 뽑는다.
	-- 여기서는 안 그리기를 선언한 사람과 직전에 그린 사람이 빠진다.
	-- (state.drawers 를 아직 안 비웠으므로 pickPool 이 알아서 걸러준다)
	local pool: { Player } = {}
	for _, player in pickPool() do
		if not table.find(chosen, player) then
			table.insert(pool, player)
		end
	end
	for _, player in picker:Pick(pool, seatsLeft) do
		table.insert(chosen, player)
	end

	-- 실제로 자리를 받은 뒤에 예약을 차감한다.
	-- 미리 빼면 여기서 오류가 났을 때 돈만 내고 못 그린 사람이 생긴다.
	--
	-- 그리고 **그리게 된 사람 전원**의 게이지를 0 으로 돌린다.
	-- ⚠️ 예약으로 들어온 사람은 뽑기(Pick)를 안 거쳐서, 여기서 안 돌리면 게이지가 그대로 남는다.
	--    두 자리를 다 예약자가 차지하는 판에서는 아무도 리셋되지 않는다.
	for _, player in chosen do
		PlayerStats.UseDrawNext(player)
		picker:ResetAfterDrawing(player.UserId)
	end

	-- 이번에 안 그린 사람 **전원**의 가중치를 올린다.
	--
	-- ⚠️ 후보(candidates)가 아니라 접속자 전체를 훑는다.
	--    안 그리기를 선언한 사람은 후보에 없지만 가중치는 올라야 하기 때문이다.
	--    선언했다는 이유로 줄 맨 뒤로 밀리면 아무도 그 버튼을 안 누른다. (§2)
	local notChosen: { number } = {}
	for _, player in Players:GetPlayers() do
		local drew = false
		for _, picked in chosen do
			if picked == player then
				drew = true
				break
			end
		end
		if not drew then
			table.insert(notChosen, player.UserId)
		end
	end
	picker:Gain(notChosen)

	strokes:Reset()
	ratings:Reset()
	-- 새 라운드가 시작되면 직전 결과는 치운다.
	state.results = nil
	table.clear(state.drawers)
	table.clear(state.drawerNames)
	for index, player in chosen do
		table.insert(state.drawers, player.UserId)
		table.insert(state.drawerNames, player.DisplayName)
		-- 뽑힌 순서대로 의자에 앉힌다. 의자가 모자라면 남는 사람은 못 앉는다.
		local seat = seats[index]
		if seat then
			DrawSeats.sit(seat, player)
		end
	end
	table.clear(state.submitted)
	-- 엿보기는 라운드마다 새로 산다. 지난 판 것이 남아 있으면 안 된다.
	table.clear(state.peeking)

	-- 확정: 고정 딕셔너리에서 고른다. AI 생성은 쓰지 않는다. (§2)
	-- 누가 작성권으로 주제를 정해뒀으면 그것을 쓴다. 없으면 딕셔너리에서 고른다. (§2)
	state.prompt = nil
	state.promptAuthor = nil
	local booked = state.nextPrompt
	if booked then
		-- 티켓은 넣을 때 이미 깎였다. 여기서는 쓰기만 한다.
		--
		-- 정한 사람이 나갔어도 그대로 쓴다. 값은 이미 치렀고,
		-- 남은 사람들에게는 주제가 있는 편이 없는 편보다 낫다.
		-- 이름은 넣을 때 적어둔 것을 쓴다. 나간 사람도 이름은 남는다.
		state.prompt = booked.text
		state.promptAuthor = booked.authorName
		print(string.format("[RoundService] 주제를 %s 가 정했다: %s", booked.authorName, booked.text))
		state.nextPrompt = nil
	end
	if not state.prompt then
		state.prompt = Config.PROMPTS[math.random(#Config.PROMPTS)]
	end

	setPhase(PHASE.DRAWING, mode.drawSeconds)

	-- 라운드 전에 사둔 엿보기가 있으면 지금 연다.
	-- setPhase 뒤에 하는 이유: applyPeek 이 "지금 그리는 중인가" 를 보기 때문이다.
	for _, player in chosen do
		applyPeek(player)
	end
end

-- 라운드 한 판. 아래에서 pcall 로 감싸서 부른다.
local function runOneRound()
	waitForPlayers()

	setPhase(PHASE.INTERMISSION, Config.INTERMISSION_TIME)
	waitForPhase()
	if not canStart() then
		-- 기다리는 사이에 사람이 빠졌거나, 안 그리기를 선언해서 그릴 사람이 모자라다.
		-- 이 판은 접고 처음부터 다시.
		-- (이제 반복문이 아니라 함수 안이므로 continue 가 아니라 return 이다)
		return
	end

	startRound()
	-- 앉히자마자 한 번 읽어둔다. Sit 이 곧바로 반영되지 않을 수 있다.
	task.wait(0.2)
	refreshSeated()

	waitForPhase(function()
		-- 둘 다 제출했으면 시간이 남아도 끝낸다. (§2 확정)
		if Config.ALLOW_EARLY_SUBMIT and allDrawersSubmitted() then
			return true
		end
		-- 그리던 사람이 전부 나가버렸다. 빈 화면을 3분씩 볼 이유가 없다.
		return #state.drawers == 0
	end)

	-- 심사. 관전자가 두 그림에 별점을 매긴다.
	setPhase(PHASE.RATING, Config.RATING_TIME)
	waitForPhase()

	-- 정산. 계산은 RatingStore 가 하고 여기서는 결과를 붙들어둔다.
	state.results = ratings:Results(state.drawers, state.drawerNames)

	-- 리더보드에 올리고 저장 대기줄에 넣는다. (§2, 4b)
	--
	-- ⚠️ 결과 화면을 **띄우기 전에** 여기서 한다.
	--    결과 화면이 뜬 7초 사이에 나가는 사람이 있는데,
	--    그 뒤에 올리면 그 사람 점수가 사라진다.
	--
	-- ⚠️ 저장이 실패해도 라운드는 굴러가야 한다. (§3.9)
	--    pcall 로 감싸는 이유는 이 한 줄 때문에 반복문이 죽으면
	--    서버가 통째로 멈추기 때문이다.
	pcall(function()
		for _, entry in state.results.entries do
			local player = Players:GetPlayerByUserId(entry.userId)
			if player then
				PlayerStats.AddRound(player, {
					score = entry.score,
					average = entry.average,
					raters = entry.count,
					won = entry.winner,
				})
			end
		end
	end)

	-- 결과 화면. 심사가 끝나자마자 다음 라운드로 넘어가면
	-- 누가 이겼는지 볼 새가 없다.
	setPhase(PHASE.RESULTS, Config.RESULTS_TIME)
	waitForPhase()

	-- 자리를 비워야 다음 라운드에 다른 사람이 앉을 수 있다.
	for _, seat in seats do
		DrawSeats.standUp(seat)
	end
	-- 의자 밖에서 점프가 막힌 채로 남은 사람이 없는지 확인한다.
	-- (라운드 도중 의자가 지워지는 등으로 위 반복문이 놓칠 수 있다)
	DrawSeats.unlockAll()

	-- ⚠️ 순서가 중요하다. 용접이 실제로 풀릴 때까지 기다린 뒤에 옮겨야
	--    의자가 캐릭터를 따라 맵 한가운데로 끌려가지 않는다.
	DrawSeats.waitUntilEmpty(seats, 1)
	sendEveryoneToSpawn()
	-- 그래도 조금 밀렸을 수 있으니 원래 자리로 되돌린다.
	DrawSeats.restore(seats)

	-- 저장은 PlayerStats 가 알아서 한다. 여기서 부르지 않는다.
	-- (나갈 때 / 서버가 닫힐 때 / 주기적으로, 늘어난 만큼만)
end

-- 리더보드를 붙이고 저장을 시작한다.
-- 라운드 반복문보다 **먼저** 불러야 한다.
-- 첫 판이 끝났는데 아직 leaderstats 가 없으면 그 판 점수가 갈 곳이 없다.
PlayerStats.Start()

-- 결제를 받기 시작한다.
--
-- ⚠️ MarketplaceService.ProcessReceipt 는 서버에 **하나만** 걸 수 있다.
--    다른 곳에서 또 걸면 조용히 덮어써져서 지급이 통째로 멈춘다.
--    거는 곳은 여기 한 줄뿐이어야 한다.
PurchaseService.Start()

-- 접속해 있는 시간을 센다. 기준 시간이 차면 주제 작성권이 하나 생긴다. (§2)
--
-- **대기 중인 시간도 센다.** 단계를 안 본다. (개발자 결정)
-- 예전에는 빈 서버 방치로 벌 수 없게 대기 중을 뺐는데,
-- "한 장까지만" 규칙이 생기면서 그럴 필요가 없어졌었다. 방치해서 얻을 수 있는 게 최대 한 장이었기 때문이다.
--
-- ⚠️ 2026-10-28 부터 무료 작성권이 **쌓인다(상한 없음).** 그래서 그 보호가 사라졌다.
--    빈 서버에 켜두기만 해도 21분마다 한 장씩 계속 모인다. (로블록스의 20분 자리 비움 퇴장이 있지만
--    시간은 저장되므로 다시 들어오면 이어서 센다)
--    막으려면 Config.MAX_FREE_TOKENS 에 상한을 건다. 개발자가 정할 일이다. (README §2 작성권)
task.spawn(function()
	while true do
		-- task.wait 은 부탁한 만큼 정확히 쉬지 않는다. 실제로 쉰 시간을 쓴다.
		-- 서버가 한 번 크게 밀리면 값이 튈 수 있으므로 위로 막아둔다.
		local elapsed = math.min(task.wait(Config.PLAYTIME_TICK), Config.PLAYTIME_TICK * 2)
		for _, player in Players:GetPlayers() do
			PlayerStats.AddPlayTime(player, elapsed)
		end
	end
end)

task.spawn(function()
	while true do
		-- ⚠️ 한 판을 통째로 pcall 로 감싼다.
		--
		--    여기서 오류가 **한 번만** 나도 이 반복문이 죽는다.
		--    그러면 서버는 영영 다음 단계로 넘어가지 않고,
		--    클라이언트는 마지막으로 받은 화면에 갇힌다.
		--    (실제로 "Rate: ... 0:00" 에서 멈추는 증상이 있었다)
		--
		--    한 판이 잘못되는 것과 게임이 통째로 멈추는 것은 무게가 다르다.
		local ok, err = pcall(runOneRound)
		if not ok then
			warn("[RoundService] Round failed: " .. tostring(err))
			-- 다음 판을 위해 자리라도 정리해둔다.
			pcall(function()
				for _, seat in seats do
					DrawSeats.standUp(seat)
				end
				DrawSeats.unlockAll()
			end)
			task.wait(1)
		end
	end
end)
