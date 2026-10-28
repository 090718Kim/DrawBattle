--!strict
--[[
	PurchaseService.lua  —  로벅스 결제를 받아서 물건을 준다

	배치 위치: ServerScriptService 안의 ModuleScript. **서버 전용.**

	여기는 **진짜 돈이 걸린 곳**이다. 다른 파일과 조심하는 정도가 다르다.
	틀리면 둘 중 하나가 일어나고, 둘 다 나쁘다.
	  돈은 받고 물건을 안 준다  → 유저가 30로벅스를 잃는다. 되돌릴 방법이 없다.
	  한 번 받고 두 번 준다     → 게임 경제가 망가진다.

	로블록스가 일하는 방식
	  결제가 끝나면 로블록스가 ProcessReceipt 를 부른다.
	  우리가 PurchaseGranted 를 돌려주면 거래가 끝난다.
	  NotProcessedYet 을 돌려주면 **나중에 다시 부른다.** 서버를 옮겨서라도 부른다.
	  그래서 "이미 준 것" 을 기억해두지 않으면 두 번 주게 된다.

	순서를 이렇게 잡은 이유

	  1) 이미 처리한 영수증인가 확인한다 — 못 읽으면 NotProcessedYet (나중에 다시)
	  2) 이미 처리했으면 그냥 PurchaseGranted (두 번 주지 않는다)
	  3) 물건을 준다 — 실패하면 NotProcessedYet (나중에 다시)
	  4) 처리했다고 적어둔다 — **실패해도 PurchaseGranted**
	  5) PurchaseGranted

	  4번에서 실패해도 그냥 넘어가는 것이 핵심이다.
	  적어두는 것은 "다시 부를 때 두 번 주지 않으려고" 하는 일인데,
	  우리가 PurchaseGranted 를 돌려주면 로블록스는 다시 부르지 않는다.
	  그러니 못 적었다고 NotProcessedYet 을 돌려주면, 이미 준 물건을
	  한 번 더 주게 된다. 거꾸로다.

	  반대로 3번에서 실패하면 반드시 NotProcessedYet 이어야 한다.
	  여기서 PurchaseGranted 를 돌려주면 돈만 받고 끝난다.

	⚠️ 물건을 주는 곳은 **접속해 있는 사람** 기준이다.
	   결제 도중에 나가버리면 줄 곳이 없다. 그때는 NotProcessedYet 을 돌려주고,
	   로블록스가 다음에 들어왔을 때 다시 불러준다.
]]

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerStats = require(script.Parent.PlayerStats)

local PurchaseService = {}

-- 처리한 영수증 번호를 적어두는 곳.
-- 플레이어 기록과 따로 두는 이유: 이건 사람이 아니라 거래에 딸린 값이다.
local receipts = DataStoreService:GetDataStore(Config.RECEIPT_STORE_NAME)

local function log(...)
	print("[Purchase]", ...)
end

-- 지금 처리 중인 영수증 번호.
--
-- ⚠️ 1번(이미 줬나 확인)과 4번(줬다고 적기) 사이에 **멈추는 구간**이 있다.
--    같은 영수증으로 두 번 불리면 둘 다 "아직 안 줬다" 를 읽고 둘 다 줘버린다.
--    로블록스가 대답이 늦으면 다시 부르므로 실제로 겹칠 수 있다.
--    저장소에 적히기 전까지는 메모리에서 막는다. (README §5.5-14)
local inFlight: { [string]: boolean } = {}

--------------------------------------------------------------------
-- 물건을 주는 곳
--------------------------------------------------------------------

-- 상품 하나에 함수 하나. true 를 돌려주면 "줬다" 는 뜻이다.
--
-- ⚠️ 여기서 하는 일은 **되돌릴 수 없어야 한다.**
--    절반만 주고 false 를 돌려주면, 다시 불렸을 때 절반이 또 들어간다.
local handlers: { [string]: (Player) -> boolean } = {}

-- 주제 작성권 한 장. 21분 놀아서 받는 것과 **완전히 같은 물건**이다.
--
-- 갈라두지 않은 이유: 쓰는 길이 하나면 된다.
-- "산 주제" 와 "무료 주제" 를 나누면 만들 것도 두 배, 틀릴 곳도 두 배다.
handlers.CUSTOM_PROMPT = function(player: Player): boolean
	PlayerStats.GrantToken(player, 1)
	return true
end

-- 다음 라운드에 그릴 자리 예약.
--
-- 여기서는 **예약만** 한다. 실제로 자리를 쓰는 것은 라운드가 시작될 때다.
-- 그래서 지금 산 뒤에 서버가 닫혀도 예약은 그대로 남아 다음에 쓰인다.
handlers.DRAW_NEXT = function(player: Player): boolean
	PlayerStats.GrantDrawNext(player)
	return true
end

-- 상대 그림 엿보기.
--
-- ⚠️ 여기서는 "한 장 받아둔다" 까지만 한다. 지금 그리는 중인지 보지 않는다.
--    "지금 못 쓰니까 못 준다" 로 만들면, 라운드가 끝나는 순간에 산 사람이
--    영영 못 받는다. 로블록스가 나중에 다시 물어봐도 그때도 라운드 밖이면
--    또 못 받고, 그렇게 돈만 잃는다.
--
--    실제로 상대 그림을 열어주는 것은 RoundService 다.
--    지금 누가 그리는지 아는 쪽이 거기이기 때문이다.
handlers.PEEK = function(player: Player): boolean
	PlayerStats.GrantPeek(player)
	return true
end

--------------------------------------------------------------------
-- 영수증 처리
--------------------------------------------------------------------

-- 상품 번호로 어떤 물건인지 찾는다.
local function handlerFor(productId: number): ((Player) -> boolean)?
	for name, id in Config.PRODUCT_IDS do
		if id ~= 0 and id == productId then
			return handlers[name]
		end
	end
	return nil
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local granted = Enum.ProductPurchaseDecision.PurchaseGranted
	local retry = Enum.ProductPurchaseDecision.NotProcessedYet

	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- 결제 도중에 나갔다. 줄 곳이 없으므로 다음에 들어왔을 때 다시 받는다.
		return retry
	end

	local handler = handlerFor(receipt.ProductId)
	if not handler then
		-- 우리가 모르는 상품이다. Config.PRODUCT_IDS 에 안 적었거나 오타다.
		--
		-- 여기서 PurchaseGranted 를 돌려주면 돈만 받고 아무것도 안 준 게 된다.
		-- 다시 부르게 두고, 그 사이에 우리가 ID 를 고치면 그때 제대로 준다.
		warn(string.format(
			"[Purchase] 모르는 상품 %d. Config.PRODUCT_IDS 를 확인할 것.",
			receipt.ProductId
		))
		return retry
	end

	local key = "receipt_" .. tostring(receipt.PurchaseId)

	if inFlight[key] then
		-- 같은 영수증을 지금 처리하는 중이다. 두 번 주지 않는다.
		-- 아직 못 끝냈으므로 "다시 물어봐 달라" 고 답한다.
		return retry
	end
	inFlight[key] = true

	-- 여기서부터는 어디로 빠져나가든 표식을 지워야 한다.
	-- 안 지우면 그 영수증은 영영 다시 처리되지 못한다.
	local function finish(decision: Enum.ProductPurchaseDecision): Enum.ProductPurchaseDecision
		inFlight[key] = nil
		return decision
	end

	-- 1) 이미 처리한 영수증인가
	local readOk, alreadyDone = pcall(function()
		return receipts:GetAsync(key)
	end)
	if not readOk then
		-- 확인을 못 했으면 주면 안 된다. 두 번 줄 수 있다.
		warn("[Purchase] 영수증 확인 실패. 나중에 다시 시도한다: " .. tostring(alreadyDone))
		return finish(retry)
	end
	if alreadyDone then
		-- 2) 전에 이미 줬다. 또 주지 않고 거래만 끝낸다.
		log(string.format("%s 의 %d 는 이미 처리됨. 다시 주지 않는다.", player.Name, receipt.ProductId))
		return finish(granted)
	end

	-- 3) 물건을 준다
	local giveOk, gave = pcall(handler, player)
	if not giveOk or not gave then
		warn(string.format(
			"[Purchase] %s 에게 상품 %d 를 못 줬다: %s",
			player.Name, receipt.ProductId, tostring(gave)
		))
		return finish(retry)
	end

	-- 4) 처리했다고 적어둔다.
	--
	--    ⚠️ 여기서 실패해도 PurchaseGranted 로 간다.
	--       적어두는 것은 "다시 불렸을 때 두 번 주지 않으려고" 하는 일인데,
	--       PurchaseGranted 를 돌려주면 로블록스는 다시 부르지 않는다.
	--       못 적었다고 NotProcessedYet 을 내면 **이미 준 물건을 또 주게 된다.**
	local writeOk, writeErr = pcall(function()
		receipts:SetAsync(key, os.time())
	end)
	if not writeOk then
		warn("[Purchase] 영수증 기록 실패(물건은 이미 줬다): " .. tostring(writeErr))
	end

	log(string.format("%s -> 상품 %d 지급 완료", player.Name, receipt.ProductId))
	return finish(granted)
end

function PurchaseService.Start()
	-- ⚠️ 이 함수는 서버 전체에 **하나만** 있을 수 있다.
	--    다른 스크립트에서 또 등록하면 나중 것이 이걸 덮어써서
	--    여기 있는 지급 코드가 통째로 안 돌게 된다. 그런데 오류는 안 난다.
	MarketplaceService.ProcessReceipt = processReceipt

	local missing = {}
	for name, id in Config.PRODUCT_IDS do
		if id == 0 then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		warn(string.format(
			"[Purchase] 상품 ID 가 아직 0 인 것: %s "
				.. "— 크리에이터 대시보드에서 만든 뒤 Config.PRODUCT_IDS 에 적을 것.",
			table.concat(missing, ", ")
		))
	end
end

return PurchaseService
