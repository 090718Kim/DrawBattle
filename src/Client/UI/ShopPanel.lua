--!strict
--[[
	ShopPanel.lua  —  상점 창

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	들어 있는 것 셋
	  1) 주제 쓰는 칸 — 작성권이 있어야 쓸 수 있다
	  2) 주제 작성권 사기 (Robux)
	  3) 다음 라운드에 내가 그리기 사기 (Robux)

	**엿보기는 여기 없다.** 그건 그리는 도중에만 쓸 수 있는 물건이라
	캔버스 옆 눈 버튼으로 따로 뺐다. 그릴 때 상점을 열게 만들면
	그 사이에 시간이 가고 그림이 밀린다.

	왜 창으로 만드는가
	  버튼 세 개를 화면에 늘 붙여두면 자리가 없다. 아래쪽은 이미
	  툴바·관전 줄·차례 게이지가 나눠 쓰고 있고, 양쪽 구석도 임자가 있다.
	  평소에는 아이콘 하나만 두고, 누를 때만 펼친다.

	**이 파일은 아무것도 결정하지 않는다. 받아서 그리기만 한다.** (§5.5-1)
	  티켓이 몇 장인지, 주제를 이미 누가 정했는지는 DrawBattleUI 가 넘겨준다.

	⚠️ 여기서 친 글자는 **서버가 반드시 걸러야 한다.** (§3.1)
	   이 파일은 글자를 보내기만 하고, 통과 여부는 서버가 정해서 돌려준다.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local ShopPanel = {}
ShopPanel.__index = ShopPanel

local PADDING = 14
local GAP = 10

function ShopPanel.new(parent: Instance, callbacks: {
	onSubmitPrompt: (string) -> (),
	onClose: () -> (),
})
	local self = setmetatable({}, ShopPanel)
	self.callbacks = callbacks
	self.tokens = 0
	self.promptTaken = false
	self.prices = {}
	self.drawNext = "available"

	local panel = UIHelper.panel("ShopPanel", parent)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(UI.SHOP_WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 0
	-- 창이 떠 있는 동안 뒤 캔버스에 그려지면 안 된다. (§3.8)
	panel.Active = true
	-- 경고창(50)보다는 아래, 주제 뽑기 연출(40)보다는 위.
	panel.ZIndex = 45
	panel.Visible = false
	self.instance = panel

	UIHelper.padding(panel, PADDING)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, GAP)
	layout.Parent = panel

	self:_buildHeader(panel)
	self:_buildPromptRow(panel)
	self:_buildBuyButtons(panel)

	self:_fetchPrices()
	self:Update(0, false)

	return self
end

function ShopPanel:_buildHeader(parent: Instance)
	local row = Instance.new("Frame")
	row.Name = "Header"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 30)
	row.LayoutOrder = 1
	row.ZIndex = 46
	row.Parent = parent

	local title = UIHelper.label("Shop", row)
	title.Size = UDim2.new(1, -34, 1, 0)
	title.TextSize = 20
	title.Font = Enum.Font.GothamBold
	title.ZIndex = 47

	-- ⚠️ 글자는 대문자 X 다. ✕ 나 ✖ 이 아니다.
	--    ✕ 는 로블록스 기본 글꼴에 없어서 **빈 네모로 나온다.** 실제로 그렇게 나왔다.
	--    ★ ↶ ↷ 때와 같은 함정이다. (README §5.2)
	--    이모지(❌)는 크고 빨개서 닫기 버튼치고 너무 시끄럽다.
	--    평범한 X 는 어느 기기에서나 나오고 뜻도 분명하다.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, 0, 0.5, 0)
	close.Size = UDim2.fromOffset(30, 30)
	close.BackgroundColor3 = UI.HEADER_COLOR
	close.BackgroundTransparency = 0
	close.BorderSizePixel = 0
	close.Text = "X"
	close.TextSize = 16
	close.Font = Enum.Font.GothamBold
	close.TextColor3 = UI.MUTED_TEXT_COLOR
	close.ZIndex = 47
	close.Parent = row
	UIHelper.corner(close, 8)
	close.Activated:Connect(function()
		self.callbacks.onClose()
	end)

	-- 가진 작성권 수. 살지 말지 정하는 데 필요한 값이라 제목 바로 밑에 둔다.
	local held = UIHelper.label("", parent)
	held.Name = "Held"
	held.Size = UDim2.new(1, 0, 0, 20)
	held.TextSize = 14
	held.TextColor3 = UI.MUTED_TEXT_COLOR
	held.LayoutOrder = 2
	held.ZIndex = 46
	self.heldLabel = held
end

-- 주제를 쓰는 칸과 보내기 버튼.
function ShopPanel:_buildPromptRow(parent: Instance)
	local box = Instance.new("TextBox")
	box.Name = "PromptInput"
	box.Size = UDim2.new(1, 0, 0, UI.SHOP_ROW_HEIGHT)
	box.BackgroundColor3 = UI.HEADER_COLOR
	box.BorderSizePixel = 0
	box.Text = ""
	box.PlaceholderText = "Write the next theme..."
	box.TextColor3 = UI.TEXT_COLOR
	box.PlaceholderColor3 = UI.MUTED_TEXT_COLOR
	box.Font = Enum.Font.GothamMedium
	box.TextSize = 16
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	-- 서버도 다시 검사하지만, 여기서 막아두면 애초에 못 넘긴다.
	box.TextEditable = false
	box.LayoutOrder = 3
	box.ZIndex = 46
	box.Parent = parent
	UIHelper.corner(box, 8)
	UIHelper.stroke(box)
	UIHelper.padding(box, 10)
	self.promptBox = box

	local send = Instance.new("TextButton")
	send.Name = "SendPrompt"
	send.Size = UDim2.new(1, 0, 0, UI.SHOP_ROW_HEIGHT)
	send.BackgroundColor3 = UI.ACCENT_COLOR
	send.BackgroundTransparency = 0
	send.BorderSizePixel = 0
	send.Text = "Set next theme"
	send.TextColor3 = Color3.new(1, 1, 1)
	send.Font = Enum.Font.GothamBold
	send.TextSize = 15
	send.LayoutOrder = 4
	send.ZIndex = 46
	send.Parent = parent
	UIHelper.corner(send, 8)
	self.sendButton = send

	send.Activated:Connect(function()
		local text = self.promptBox.Text
		if text ~= "" then
			self.callbacks.onSubmitPrompt(text)
		end
	end)

	-- 서버가 왜 안 됐는지 알려주면 여기에 띄운다.
	local note = UIHelper.label("", parent)
	note.Name = "Note"
	note.Size = UDim2.new(1, 0, 0, 18)
	note.TextSize = 13
	note.TextWrapped = true
	note.AutomaticSize = Enum.AutomaticSize.Y
	note.LayoutOrder = 5
	note.ZIndex = 46
	note.Visible = false
	self.noteLabel = note
end

function ShopPanel:_buildBuyButtons(parent: Instance)
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.BackgroundColor3 = UI.PANEL_STROKE_COLOR
	divider.BorderSizePixel = 0
	divider.LayoutOrder = 6
	divider.ZIndex = 46
	divider.Parent = parent

	self.promptBuyButton = self:_buyButton(parent, "BuyPrompt", 7, "CUSTOM_PROMPT", "Theme ticket")
	self.drawBuyButton = self:_buyButton(parent, "BuyDrawNext", 8, "DRAW_NEXT", "Draw next round")
end

-- 로벅스로 사는 버튼 하나.
--
-- 상품 ID 가 0 이면 아직 크리에이터 대시보드에서 안 만든 것이다.
-- 그 상태로 결제창을 부르면 오류가 나므로 흐리게 두고 못 누르게 한다.
function ShopPanel:_buyButton(
	parent: Instance,
	name: string,
	order: number,
	product: string,
	label: string
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(1, 0, 0, UI.SHOP_ROW_HEIGHT)
	button.BackgroundColor3 = UI.PANEL_COLOR
	button.BackgroundTransparency = UI.PANEL_TRANSPARENCY
	button.BorderSizePixel = 0
	button.Text = label
	button.TextColor3 = UI.TEXT_COLOR
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 15
	button.LayoutOrder = order
	button.ZIndex = 46
	button.Parent = parent
	UIHelper.corner(button, 8)
	UIHelper.stroke(button)

	button:SetAttribute("Product", product)
	button:SetAttribute("Label", label)

	button.Activated:Connect(function()
		local productId = Config.PRODUCT_IDS[product]
		if productId == 0 then
			return -- 아직 상품이 없다
		end
		-- ⚠️ 흐린 버튼도 눌린다. 모양을 믿지 말고 **지금 살 수 있는지 여기서 다시 본다.**
		--    이게 없어서 "다음 판 그리기" 를 산 사람이 같은 버튼으로 또 살 수 있었다.
		if button:GetAttribute("Disabled") then
			return
		end
		if product == "DRAW_NEXT" and self.drawNext ~= "available" then
			return -- 이미 샀거나 품절이다
		end
		-- 결제 성사 여부는 **서버가 판단한다.** (ProcessReceipt)
		-- 여기서는 창을 띄우기만 하고 아무 상태도 안 바꾼다. (§3.4)
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
	end)

	return button
end

-- 대시보드에 설정된 진짜 가격을 물어본다.
--
-- Config 의 숫자는 못 읽었을 때 쓰는 예비값이다.
-- Config 에만 기대면 대시보드에서 가격을 고쳤을 때 버튼이 거짓말을 한다.
function ShopPanel:_fetchPrices()
	for _, button in { self.promptBuyButton, self.drawBuyButton } do
		local product = button:GetAttribute("Product") :: string
		self.prices[product] = Config.PRODUCT_PRICES[product]

		local productId = Config.PRODUCT_IDS[product]
		if productId ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
				end)
				if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
					self.prices[product] = info.PriceInRobux
					self:_paintBuyButtons()
				end
			end)
		end
	end
end

function ShopPanel:_paintBuyButtons()
	for _, button in { self.promptBuyButton, self.drawBuyButton } do
		local product = button:GetAttribute("Product") :: string
		local label = button:GetAttribute("Label") :: string
		local ready = Config.PRODUCT_IDS[product] ~= 0
		button.Text = string.format("%s   R$%d", label, self.prices[product] or 0)
		UIHelper.setDisabled(button, not ready)
	end

	-- "다음 판 그리기" 는 라운드당 정원(DRAW_NEXT_SEATS)이 있어서 상태가 셋이다. (§3.2)
	--
	-- ⚠️ 살 수 없을 때 버튼을 **꺼야** 한다. 켜두면 이미 산 사람이 또 사거나,
	--    품절인데 사버린다. 서버는 받은 돈은 돌려줄 수 없으니 그다음 판으로 미루는데,
	--    산 사람은 "다음 판" 이라고 알고 샀으니 약속을 어긴 게 된다.
	--    애초에 못 사게 막는 게 맞다.
	if self.drawNext == "mine" then
		-- ✓ 기호는 안 쓴다. ✕ 처럼 빈 네모로 나올 수 있다. (DrawChanceBar 참고)
		self.drawBuyButton.Text = "Booked for next round"
		UIHelper.setDisabled(self.drawBuyButton, true)
	elseif self.drawNext == "soldout" then
		self.drawBuyButton.Text = "Draw next round — sold out"
		UIHelper.setDisabled(self.drawBuyButton, true)
	end
end

-- 서버가 보낸 대답을 띄운다. 통과했으면 칸을 비운다.
function ShopPanel:ShowResult(ok: boolean, message: string)
	self.noteLabel.Visible = true
	self.noteLabel.TextColor3 = if ok then UI.ACCENT_COLOR else UI.DANGER_COLOR
	-- 라운드 도중에도 넣을 수 있다. 언제 넣든 **다음 라운드** 주제다.
	-- 그냥 "Next theme" 이라고만 쓰면 지금 판 것으로 오해할 수 있다.
	self.noteLabel.Text = if ok
		then ("This will be next round's theme: " .. message)
		else message
	if ok then
		self.promptBox.Text = ""
	end
end

-- tokens   가진 주제 작성권 수
-- taken    다음 라운드 주제가 이미 정해졌는가 (내가 정했든 남이 정했든)
-- mine     그것을 정한 사람이 나인가 — 안내 문구만 달라진다
-- drawNext "다음 판 그리기" 상태: "available" / "mine" / "soldout"
function ShopPanel:Update(tokens: number, taken: boolean, mine: boolean, drawNext: string?)
	self.tokens = tokens
	self.promptTaken = taken
	self.drawNext = drawNext or "available"

	self.heldLabel.Text = string.format("Theme tickets: %d", tokens)

	-- ⚠️ **한 번 정하면 못 고친다.** 내가 정한 것도 마찬가지다. (§2)
	--    서버가 그렇게 막으므로 화면도 똑같이 막아야 한다.
	--    화면만 열어두면 눌렀다가 거절당하고, 왜 안 되는지 알 수가 없다.
	local canWrite = not taken and tokens > 0
	self.promptBox.TextEditable = canWrite
	UIHelper.setDisabled(self.promptBox, not canWrite)
	UIHelper.setDisabled(self.sendButton, not canWrite)

	if taken then
		-- 누가 정했는지에 따라 말이 달라야 한다.
		-- 내가 정해놓고 "누가 이미 정했다" 를 보면 남이 가로챈 줄 안다.
		self.promptBox.PlaceholderText = if mine
			then "You set the next theme"
			else "Someone already set the next theme"
	elseif tokens <= 0 then
		self.promptBox.PlaceholderText = "You need a theme ticket"
	else
		self.promptBox.PlaceholderText = "Write the next theme..."
	end

	self:_paintBuyButtons()
end

return ShopPanel
