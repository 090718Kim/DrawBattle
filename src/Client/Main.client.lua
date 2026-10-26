--!strict
--[[
	Main.client.lua  —  클라이언트 진입점

	Rojo 가 이 파일을 StarterPlayerScripts 안의 LocalScript 로 만들어준다.
	(.client.lua 확장자가 그 뜻이다)

	이 파일은 일부러 짧게 유지한다.
	화면을 만드는 일은 UI/DrawBattleUI 가, 그리는 일은 Shared/DrawingCanvas 가 한다.
	여기서 하는 건 "누구를 언제 부를지" 뿐이다.

	GUI 를 스튜디오에서 손으로 만들지 않고 코드로 만드는 이유는 README §6.6 참고.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 캐릭터 재설정(Reset) 금지.
--
-- 재설정하면 캐릭터가 죽었다 살아나면서 의자에서 빠져나온다.
-- 그리는 도중에 그러면 라운드가 꼬이고, 점프를 막아둔 것도 무의미해진다.
--
-- SetCore 는 로블록스 UI 가 준비되기 전에 부르면 실패한다. 될 때까지 몇 번 시도한다.
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
	warn("[DrawBattle] Could not disable the reset button.")
end)

-- UI 폴더는 StarterPlayerScripts 와 함께 복사되어 들어온다.
-- 복사가 끝나기 전에 require 하면 실패하므로 WaitForChild 로 기다린다.
local uiFolder = script.Parent:WaitForChild("UI")
local DrawBattleUI = require(uiFolder:WaitForChild("DrawBattleUI"))

local ui = DrawBattleUI.new(playerGui)

-- 빌드 표식을 **클라이언트에서도** 찍는다. (README §5.5 의 빌드 표식 이야기)
-- 서버만 찍으면 "서버는 새 코드인데 화면은 옛 코드" 인 경우를 못 가린다.
-- 화면 쪽 기능이 안 될 때 코드가 틀린 건지, 옛 코드가 돌고 있는 건지부터 갈라야 한다.
-- 테스트 창(플레이어)마다 Output 이 따로 있으므로 각 창에서 확인한다.
print(string.format("[DrawBattle] client build=%s | canvas ready (render mode = %s)", Config.BUILD_TAG, tostring(ui.canvas.mode)))

-- 라운드가 생기면(2단계) 여기서 그리기를 잠그고 풀게 된다.
--   ui.canvas:SetEnabled(false)
--
-- ⚠️ 그 잠금은 클라이언트 편의 기능일 뿐이다. 서버가 따로 검사해야 한다. (README §3.4)
