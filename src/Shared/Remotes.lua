--!strict
--[[
	Remotes.lua  —  서버와 클라이언트가 주고받는 통로

	배치 위치: ReplicatedStorage.Shared 안의 ModuleScript.

	RemoteEvent 를 스튜디오에서 손으로 만들지 않고 코드로 만드는 이유는
	GUI 를 코드로 만드는 이유와 같다. (README §6.6)
	손으로 만들면 Rojo/Git 관리 밖에 놓이고, 이름을 하나 바꿀 때마다
	스튜디오에서도 똑같이 고쳐야 한다. 이름의 출처를 이 파일 하나로 둔다.

	쓰는 법
		local Remotes = require(ReplicatedStorage.Shared.Remotes)
		local roundState = Remotes.event(Remotes.ROUND_STATE)

	서버에서 부르면 없을 때 만들고, 클라이언트에서 부르면 생길 때까지 기다린다.
	그래서 양쪽이 똑같은 한 줄을 쓰면 된다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

-- 서버 → 클라이언트: 지금 라운드가 어떤 상태인가
Remotes.ROUND_STATE = "RoundState"

-- 클라이언트 → 서버: 그림 제출 (취소 불가)
Remotes.SUBMIT_DRAWING = "SubmitDrawing"

-- 클라이언트 → 서버: "나 방금 들어왔으니 지금 상태 좀 알려달라"
--
-- 이게 없으면 중간에 들어온 사람은 다음 단계로 넘어갈 때까지
-- 빈 화면을 보게 된다. 서버가 1초마다 계속 뿌리는 방법도 있지만,
-- 필요할 때 한 번 묻는 쪽이 훨씬 싸다.
Remotes.REQUEST_STATE = "RequestRoundState"

-- 클라이언트 → 서버: 방금 그은 선 하나
--
-- ⚠️ 서버는 이 값을 절대 믿지 않는다. 점 개수, 좌표 범위, 굵기, 도구 이름을
--    전부 다시 검사한 뒤에야 다른 사람에게 넘긴다. (README §3.4, §7-7)
Remotes.SEND_STROKE = "SendStroke"

-- 서버 → 클라이언트: 누군가 선을 하나 그었다 (검사를 통과한 것만)
Remotes.STROKE_ADDED = "StrokeAdded"

-- 클라이언트 → 서버: "이 사람 그림 처음부터 다 보내달라"
-- 관전을 시작하거나 도중에 들어왔을 때 쓴다.
Remotes.REQUEST_CANVAS = "RequestCanvas"

-- 서버 → 클라이언트: 그림 전체 (위 요청에 대한 답)
Remotes.CANVAS_SYNC = "CanvasSync"

-- 클라이언트 → 서버: 이 사람 그림에 별 몇 개
--
-- ⚠️ 서버가 다시 검사한다. 관전자인지, 대상이 이번 라운드에 그린 사람인지,
--    별 개수가 1~5 인지, 자기 그림에 주는 건 아닌지. (README §3.4, §7-7)
Remotes.SEND_RATING = "SendRating"

-- 클라이언트 → 서버: "나는 다음 라운드에 안 그리겠다" / "다시 그리겠다"
--
-- 선언해도 가중치는 계속 오른다. 잠깐 쉬었다고 줄 맨 뒤로 밀리면 안 된다.
Remotes.SET_OPT_OUT = "SetOptOut"

-- 클라이언트 → 서버: "다음 라운드 주제를 이걸로 하겠다"
--
-- ⚠️ 서버가 TextService 로 **반드시 걸러야 한다.** 로블록스 정책 의무다. (§3.1)
--    유저가 친 글자를 그대로 남의 화면에 띄우는 자리다.
Remotes.SUBMIT_PROMPT = "SubmitPrompt"

-- 서버 → 클라이언트: 주제가 받아들여졌는지, 안 됐으면 왜인지
Remotes.PROMPT_RESULT = "PromptResult"

-- 서버 → 클라이언트: 화면에 잠깐 띄울 한 줄
--
-- 모두가 알아야 하는 일에 쓴다. 지금은 "다음 주제가 정해졌다" 하나뿐이다.
-- 본인만 알면 되는 것(내 티켓이 늘었다)은 이걸 안 쓴다.
Remotes.TOAST = "Toast"

local function container(): Instance
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Remotes.event(name: string): RemoteEvent
	local folder = container()

	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		return remote :: RemoteEvent
	end

	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
