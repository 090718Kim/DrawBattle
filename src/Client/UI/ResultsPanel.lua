--!strict
--[[
	ResultsPanel.lua  —  직전 라운드 결과

	배치 위치: StarterPlayerScripts.UI 안의 ModuleScript.

	인터미션 동안 화면 가운데에 뜬다.
	두 사람의 이름, 받은 별점 합산, 몇 명이 매겼는지, 최종 점수를 보여준다.

	§2 확정
	  라운드 승패는 별점 **합산**. 승자는 합산 + 5, 패자는 합산 그대로.
	  합산이 같으면 **무승부** — 보너스는 아무도 못 받는다.

	점수를 "18 (+5)" 처럼 나눠 적는 이유:
	  왜 이 점수가 나왔는지 한눈에 보이게 하려는 것이다.
	  23 이라고만 적으면 별을 23개 받은 줄 안다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UIHelper = require(script.Parent.UIHelper)

local UI = Config.UI

local ResultsPanel = {}
ResultsPanel.__index = ResultsPanel

local PADDING = 18
local ROW_HEIGHT = 58

function ResultsPanel.new(parent: Instance)
	local self = setmetatable({}, ResultsPanel)

	local panel = UIHelper.panel("ResultsPanel", parent)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(UI.RESULTS_WIDTH, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 0
	panel.Active = true
	-- 캔버스(1)·패널(10)·주제 연출(39~40) 보다 위, 경고창(50) 아래.
	-- 결과는 라운드의 결말이라 무엇에도 가리면 안 된다.
	panel.ZIndex = 45
	panel.Visible = false
	self.instance = panel

	UIHelper.padding(panel, PADDING)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = panel

	local title = UIHelper.label("", panel)
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 30)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.LayoutOrder = 1
	title.ZIndex = 46
	self.title = title

	-- 사람 수만큼 미리 만들어둔다. 라운드마다 만들고 지우지 않는다.
	self.rows = {}
	for index = 1, Config.DRAWERS_PER_ROUND do
		self.rows[index] = self:_buildRow(panel, index)
	end

	return self
end

function ResultsPanel:_buildRow(parent: Instance, index: number)
	local row = Instance.new("Frame")
	row.Name = "Row" .. index
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = UI.HEADER_COLOR
	row.BorderSizePixel = 0
	row.LayoutOrder = index + 1
	row.ZIndex = 46
	row.Parent = parent
	UIHelper.corner(row, 10)

	local name = UIHelper.label("", row)
	name.Name = "Name"
	name.Position = UDim2.fromOffset(14, 0)
	name.Size = UDim2.new(0.5, 0, 1, 0)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 17
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 47

	local detail = UIHelper.label("", row)
	detail.Name = "Detail"
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, -14, 0, 0)
	detail.Size = UDim2.new(0.5, -14, 1, 0)
	detail.TextXAlignment = Enum.TextXAlignment.Right
	detail.Font = Enum.Font.GothamMedium
	detail.TextSize = 15
	detail.ZIndex = 47

	return { frame = row, name = name, detail = detail }
end

-- 서버가 보낸 결과를 화면에 옮긴다. results 가 없으면 패널을 감춘다.
function ResultsPanel:Update(results)
	if not results or not results.entries or #results.entries == 0 then
		self.instance.Visible = false
		return
	end

	self.instance.Visible = true
	self.title.Text = if results.draw then "Draw" else "Round Result"

	for index, row in self.rows do
		local entry = results.entries[index]
		row.frame.Visible = entry ~= nil
		if not entry then
			continue
		end

		row.name.Text = entry.name
		-- 승자만 테두리를 강조색으로 바꿔서 눈에 띄게 한다.
		row.name.TextColor3 = if entry.winner then UI.ACCENT_COLOR else UI.TEXT_COLOR

		if entry.count == 0 then
			-- 아무도 안 매긴 경우. 0 점이라고만 적으면 고장으로 보인다.
			row.detail.Text = "no ratings"
		elseif entry.winner then
			row.detail.Text = string.format(
				"⭐ %d  (%d votes)   →  %d  (+%d)",
				entry.total, entry.count, entry.score, Config.WINNER_BONUS
			)
		else
			row.detail.Text = string.format(
				"⭐ %d  (%d votes)   →  %d",
				entry.total, entry.count, entry.score
			)
		end
	end
end

function ResultsPanel:Hide()
	self.instance.Visible = false
end

return ResultsPanel
