--!strict
--[[
	Config.lua  —  게임 설정값 모음

	규칙: 코드 안에 숫자를 직접 박지 말고 전부 여기에 둘 것.
	나중에 "프로 서버가 텅 비었다" 같은 문제가 생겼을 때
	이 파일의 숫자 하나만 고치면 되도록 하기 위함이다.

	⚠️ 아래 값 중 상당수는 **아직 확정되지 않았다.**
	   `-- [미정]` 표시가 붙은 것은 임시값이며, 개발자와 상의 없이
	   이 값에 의존하는 로직을 확정적으로 짜지 말 것.
]]

local Config = {}

-- 빌드 표식. 화면 구석 상태 줄에 찍힌다.
-- 지금 돌고 있는 코드가 최신인지 스크린샷 한 장으로 알 수 있다.
--
-- 모바일은 게시(Ctrl+P)를 해야 반영되므로, 이게 없으면
-- 옛 코드를 보면서 "안 고쳐졌다" 를 되풀이하게 된다.
--
-- 날짜를 쓰다가 0826 을 0823 으로 잘못 읽는 일이 있었다.
-- 한 자만 달라도 뜻이 정반대가 되므로, 한눈에 구분되는 낱말을 쓴다.
-- 코드를 고칠 때마다 다음 낱말로 바꾼다: ALPHA → BRAVO → CHARLIE → DELTA ...
-- ZULU 다음은 ALPHA2 → BRAVO2 ... 로 한 바퀴 더 돈다.
Config.BUILD_TAG = "INDIA2"

--------------------------------------------------------------------
-- 캔버스
--------------------------------------------------------------------

-- EditableImage 최대치는 1024. 512 면 충분하고 훨씬 가볍다.
Config.CANVAS_SIZE = 512

-- 그리는 방식을 강제로 고정한다. 평소에는 nil 로 둘 것.
--
--   nil       자동. EditableImage 를 먼저 시도하고 안 되면 Frame 으로 내려간다.
--   "frame"   EditableImage 를 아예 시도하지 않는다.
--
-- ⚠️ "frame" 은 성능을 직접 비교해보기 위한 것이지, 호환성을 위한 것이 아니다.
--    Frame 방식은 선분 하나당 인스턴스 2개(Frame + UICorner)를 만든다.
--    그림 하나에 1만 개를 넘기기 쉽고, 되돌리기는 그걸 전부 지우고 다시 만든다.
--    저사양 기기에서 오히려 못 돌아가게 되므로 출시용으로 켜지 말 것.
--
-- 참고: 'Allow Mesh / Image APIs' 는 플레이어가 아니라 **경험(experience) 단위**
--       설정이다. 개발자가 한 번 켜두면 들어오는 사람은 아무 조건이 없다.
--       신원 인증이 필요한 쪽은 그 스위치를 켜는 개발자 계정이다.
Config.FORCE_RENDER_MODE = nil :: string?

-- 점을 이만큼(픽셀) 움직여야 새 점으로 기록. 데이터 양을 줄이는 장치.
Config.MIN_POINT_DISTANCE = 2

-- 스트로크 하나의 최대 점 개수 (악성 유저 방어)
Config.MAX_POINTS_PER_STROKE = 2000

-- 펜 기본값
Config.DEFAULT_THICKNESS = 6
Config.MIN_THICKNESS = 1
Config.MAX_THICKNESS = 64

--------------------------------------------------------------------
-- 라운드
--------------------------------------------------------------------

-- 확정: 서버를 세 가지로 나눈다. 그리기 시간이 서버마다 다르다.
--
-- 어느 서버인지는 Workspace 의 "ServerMode" 속성으로 정한다.
-- (스튜디오에서 Workspace 를 고르고 속성 창 맨 아래 '속성 추가' → 문자열)
-- 속성이 없으면 DEFAULT_SERVER_MODE 를 쓴다.
--
-- 지금은 플레이스 하나뿐이라 속성으로 바꿔가며 시험한다.
-- 실제로 서버를 셋으로 나누는 것(플레이스 분리, 이동)은 5단계에서 한다.
Config.SERVER_MODES = {
	casual3 = { label = "3 Minute", drawSeconds = 180, proOnly = false },
	casual5 = { label = "5 Minute", drawSeconds = 300, proOnly = false },
	-- 프로 서버는 5분 고정. 별점 미달자도 입장은 되지만 그리지는 못한다. (§2)
	pro = { label = "Pro", drawSeconds = 300, proOnly = true },
}
Config.DEFAULT_SERVER_MODE = "casual3"

-- 확정: 이만큼 모여야 라운드가 시작된다.
-- 그리는 사람 2명 + 심사할 관전자 1명 = 3명.
-- 별점이 하나도 없는 헛판이 기록에 남는 것을 막는 장치다.
Config.MIN_PLAYERS_TO_START = 3

-- 확정: 라운드 사이 대기 시간 (초)
Config.INTERMISSION_TIME = 15

-- 확정: 별점 매기는 시간 (초)
--
-- 심사 제출 버튼은 만들었다가 걷어냈다.
-- 관전 줄이 그만큼 길어져서 좁은 화면에서 그림과 겹쳤고,
-- 시간을 줄이는 편이 같은 목적(빨리 넘어가기)을 훨씬 싸게 이룬다.
Config.RATING_TIME = 20

-- 주제 단어가 뽑기 기계처럼 돌다가 멈추는 데 걸리는 시간 (초)
Config.PROMPT_ROLL_SECONDS = 3

-- 나타나서 사라질 때까지, 뽑기 연출 전체에 걸리는 시간 (초)
Config.PROMPT_REVEAL_SECONDS = 5

-- 확정: 누가 작성권으로 정한 주제는 **뽑기를 돌리지 않는다.**
-- 대신 "MrKim's theme / Apple" 을 이만큼 보여주고 사라진다. (초)
--
-- 돌리지 않는 이유: 정해진 답을 놓고 뽑기 기계를 돌리면 연기다.
-- 사람들은 결과가 이미 정해졌다는 걸 안다. 알림으로 미리 들었기 때문이다.
-- 돌아가는 2초는 기다림만 늘린다. 누가 정했는지를 보여주는 편이 낫다.
Config.PROMPT_CHOSEN_SECONDS = 3

-- 확정: 결과 화면을 보여주는 시간 (초)
-- 심사가 끝나자마자 다음 라운드가 시작되면 누가 이겼는지 볼 새가 없다.
Config.RESULTS_TIME = 7

-- 확정: 별점 합산이 같으면 무승부.
-- 둘 다 합산만 받고 승자 보너스는 아무도 못 받는다.
-- 규칙이 가장 단순하고, 등급은 어차피 평균으로 내므로 손해가 없다.
Config.TIE_IS_DRAW = true

Config.DRAWERS_PER_ROUND = 2 -- 확정: 1대1

-- 그리기용 의자에 붙이는 태그.
-- 태그가 붙은 의자가 하나도 없으면 Workspace 의 Seat 를 전부 그리기용으로 본다.
-- 그래서 아무 설정 없이도 바로 동작하고, 나중에 관중석 의자 같은 게 생기면
-- 그리기용 의자에만 이 태그를 붙이면 된다.
Config.DRAW_SEAT_TAG = "DrawSeat"

-- 의자에 앉은 사람은 점프를 못 한다.
--
-- 로블록스에서 의자를 빠져나오는 방법은 점프뿐이다. 그래서 점프를 막으면
-- 라운드 도중에 실수로 일어나 버리는 일이 없어진다.
-- 그리다가 스페이스바를 누르는 일은 생각보다 자주 일어난다.
--
-- 게임 느낌이 답답하면 false 로 바꾸면 된다. 그러면 일어날 수 있게 되고,
-- 일어난 동안에는 그림판이 사라진다. (일어난 사람은 그리지 못한다는 규칙은 그대로다)
Config.LOCK_JUMP_WHILE_SEATED = true

-- 라운드가 끝나면 전원을 스폰 지점으로 되돌린다.
-- 한 점에 겹쳐 서지 않도록 이 반지름만큼 둥글게 흩는다.
Config.SPAWN_SPREAD_RADIUS = 6

--------------------------------------------------------------------
-- 스트로크 전송 (3단계)
--------------------------------------------------------------------

-- 한 라운드에 한 사람이 보낼 수 있는 스트로크 개수 상한.
--
-- ⚠️ 이건 그림 그리는 데 필요한 값이 아니라 **방어용**이다.
--    익스플로잇으로 초당 수천 개를 보내면 서버가 죽고 관전자 화면도 멎는다.
--    5분 동안 손으로 그을 수 있는 선은 아무리 많아도 이 근처에 못 간다.
Config.MAX_STROKES_PER_ROUND = 3000

-- 제출한 그림이 화면 가운데로 옮겨가는 데 걸리는 시간 (초)
Config.PRESENT_TWEEN_SECONDS = 0.45

-- 그릴 사람 뽑기 — 확정: 안 뽑힐수록 확률이 오르는 가중치 방식 (§1)
--
-- 모두 같은 확률로 뽑으면 운 나쁜 사람은 열 판을 내리 구경만 하게 된다.
-- 안 뽑힐 때마다 가중치를 올려두면 언젠가는 반드시 차례가 온다.
Config.PICK_BASE_WEIGHT = 1 -- 처음 들어온 사람의 가중치
Config.PICK_WEIGHT_GAIN = 1 -- 안 뽑힌 라운드마다 이만큼 오른다
-- 상한이 없으면 오래 있던 사람이 계속 독점하게 된다.
-- 8이면 방금 들어온 사람보다 8배까지만 유리하다.
Config.PICK_MAX_WEIGHT = 8

-- 확정: "안 그리기" 를 선언하면 뽑기에서 빠진다. 다만 **가중치는 계속 오른다.**
-- 선언을 풀었을 때 그동안 기다린 만큼이 반영되지 않으면,
-- 잠깐 쉬었다는 이유로 줄 맨 뒤로 밀리는 셈이 된다.
Config.OPT_OUT_KEEPS_GAINING = true

-- 확정: 안 그리기 선언 때문에 그릴 사람이 모자라면 **라운드를 시작하지 않는다.**
-- 선언을 무시하고 뽑으면 버튼이 거짓말을 하게 된다.
Config.MIN_AVAILABLE_DRAWERS = 2

-- 확정: 두 사람이 모두 제출하면 시간이 남아도 그리기가 끝난다.
-- 제출은 취소할 수 없다. 취소가 되면 "상대가 제출했나" 를 보고
-- 마음을 바꾸는 눈치 싸움이 되어버리기 때문이다.
Config.ALLOW_EARLY_SUBMIT = true

-- 라운드의 진행 단계. 서버와 클라이언트가 같은 이름을 써야 하므로 여기에 둔다.
-- 심사(RATING)와 정산(RESULTS)은 4단계에서 이 사이에 끼워 넣는다.
Config.PHASE = {
	WAITING = "waiting", -- 사람이 모자라 기다리는 중
	INTERMISSION = "intermission", -- 다음 라운드까지 대기 (직전 결과를 보여준다)
	DRAWING = "drawing", -- 그리는 중
	RATING = "rating", -- 관전자가 별점을 매기는 중
	RESULTS = "results", -- 누가 이겼는지 보여주는 중
}

--------------------------------------------------------------------
-- 별점 / 점수
--------------------------------------------------------------------

Config.MIN_STARS = 1
Config.MAX_STARS = 5

-- 확정: 승자는 별점 합산에 이만큼 더 받는다
Config.WINNER_BONUS = 5

--------------------------------------------------------------------
-- 저장 (DataStore)
--------------------------------------------------------------------
-- ⚠️ 스튜디오에서 쓰려면 크리에이터 대시보드에서
--    "Studio에서 API 서비스 액세스 활성화" 를 켜야 한다.
--    안 켜면 아래 저장은 전부 실패하고, 리더보드가 항상 0 으로 보인다.

-- 이름에 버전을 붙여둔다. 저장 형식을 바꿔야 할 때
-- 옛 데이터를 건드리지 않고 v2 로 새로 시작할 수 있다.
Config.STATS_STORE_NAME = "DrawBattleStats_v1"

-- 처리한 영수증 번호를 적어두는 곳. 사람이 아니라 거래에 딸린 값이라 따로 둔다.
-- 여기가 비면 이미 준 물건을 한 번 더 주게 된다. 이름을 바꾸지 말 것.
Config.RECEIPT_STORE_NAME = "DrawBattleReceipts_v1"

-- 불러오기를 몇 번까지 다시 시도할 것인가.
-- 한 번 실패했다고 기록이 없는 사람 취급하면 그 판의 점수가 날아간다.
Config.STATS_LOAD_TRIES = 3

-- 주기적으로 저장하는 간격(초).
-- 서버가 죽는 방식은 여러 가지라 BindToClose 만 믿을 수 없다.
Config.STATS_AUTOSAVE_SECONDS = 120

--------------------------------------------------------------------
-- 프로 서버
--------------------------------------------------------------------
-- 확정: 프로 서버 자격은 **누적 Score** 로 건다. (README §2)
--       리더보드에 보이는 그 숫자다. 기준 점수(N)는 6단계에서 정한다.
--
-- ⚠️ 아래 PRO_MIN_RATING / PRO_DEMOTE_RATING 은 **예전 계획(별점 평균)의 값이라
--    지금 아무 데서도 안 쓴다.** 6단계에서 Score 기준값으로 바꿀 때 지운다.
--    RATING_WINDOW 와 PRO_MIN_ROUNDS 는 PlayerStats 가 평균 목록을 쌓는 데 쓰고 있다.

Config.PRO_MIN_RATING = 3.5 -- (안 씀) 예전 계획: 그리기 자격 최소 평균 별점
Config.PRO_DEMOTE_RATING = 3.2 -- (안 씀) 예전 계획: 이 밑으로 떨어지면 자격 상실
Config.PRO_MIN_ROUNDS = 20 -- [미정] 최소 참여 판수 (없으면 1판 5.0 받은 사람이 프로)
Config.RATING_WINDOW = 20 -- [미정] 최근 몇 판을 평균낼 것인가

-- 승격선(3.5)과 강등선(3.2)을 벌려두는 이유:
-- 둘 다 같으면 경계값 근처의 플레이어가 매 라운드 승격/강등을 반복한다.
-- 이렇게 간격을 두는 것을 히스테리시스라고 한다.

--------------------------------------------------------------------
-- 캐시 아이템 (Robux)
--------------------------------------------------------------------
-- 확정: 가격 3종. 크리에이터 대시보드 → 수익 창출 → **개발자 상품** 에서 만든 것이다.
-- (게임패스가 아니다. 게임패스는 한 번 사면 영원히 갖는 물건이고, 이건 살 때마다 결제된다)
--
-- ID 를 0 으로 두면 "아직 안 만들었다" 는 뜻이 되어, 그 상품 버튼이 꺼진 채로 보인다.
-- 0 인 채로 PromptProductPurchase 를 부르면 오류가 나기 때문이다.
--
-- 이 숫자는 **비밀이 아니다.** 로블록스 사이트에서 누구나 볼 수 있다.
-- 공개 저장소에 올려도 된다. 결제를 지키는 것은 ID 를 숨기는 게 아니라,
-- 로블록스가 결제를 확인한 뒤에 **서버만** 물건을 주는 구조다. (PurchaseService)
Config.PRODUCT_IDS = {
	PEEK = 3710340239, -- 대시보드 이름 "Peek at Opponent"
	CUSTOM_PROMPT = 3710340571, -- 대시보드 이름 "Write a Theme"
	DRAW_NEXT = 3710340412, -- 대시보드 이름 "Draw Next Round"
}

-- 확정: 게임에 들어와 **20분이 지나면** 주제 작성권을 하나 준다.
-- 로벅스로 사는 것과 같은 물건이다.
--
-- ⚠️ 실제 기준은 **21분**이다. 유저에게는 20분이라고 말한다.
--    1분을 여유로 두는 이유: 15초마다 세는데다 서버가 밀리면 시간이 조금씩 뜬다.
--    "20분이라더니 왜 안 줘" 가 "어 벌써 줬네" 보다 나쁘다. 넉넉한 쪽으로 둔다.
--
-- **대기 중인 시간도 센다.** 접속해 있으면 그냥 올라간다.
-- 빈 서버에 켜두고 방치해도 오르지만, 아래 "하나만" 규칙 때문에
-- 방치해서 얻을 수 있는 것은 **최대 한 장**이다. 쌓아둘 수가 없다.
--
-- 테스트할 때는 여기를 30 처럼 짧게 바꿔서 확인한다.
-- ⚠️ 확인이 끝나면 반드시 21 * 60 으로 되돌릴 것. 그대로 게시하면 공짜로 계속 나간다.
Config.PLAY_SECONDS_PER_TOKEN = 21 * 60

-- 확정: **한 장까지만 가진다. 쓰기 전에는 다음 것을 못 받는다.**
--
-- 가지고 있는 동안에는 시간이 아예 안 쌓인다.
-- 쌓아뒀다가 쓰는 순간 또 나오면 그건 결국 쌓아둔 것과 같기 때문이다.
-- 쓰고 나면 0 부터 다시 센다.
Config.MAX_FREE_TOKENS = 1

Config.PLAYTIME_TICK = 15

-- ⚠️ 이건 **예비값일 뿐이다.**
--    화면에 찍는 가격은 GetProductInfo 로 대시보드에서 직접 읽어온다.
--    여기 숫자는 그걸 못 읽었을 때만 쓴다. 대시보드에서 가격을 바꿔도
--    여기를 안 고쳐서 버튼이 거짓말을 하는 일이 없게 하려는 것이다.
Config.PRODUCT_PRICES = {
	PEEK = 10,
	CUSTOM_PROMPT = 30,
	DRAW_NEXT = 15,
}

-- 확정: 엿보기는 **라운드가 끝날 때까지** 보인다.
-- 그리고 보는 동안에도 내 타이머는 계속 간다. (§3.3 완화책)
--
-- ⚠️ 이건 §3.3 에서 "베끼기가 최적 전략이 될 위험이 가장 큰" 쪽으로 고른 것이다.
--    실제로 베끼는 사람이 나오면 여기를 초 단위로 바꾼다.
Config.PEEK_LASTS_ALL_ROUND = true

-- 직접 쓰는 주제 단어의 길이 제한.
-- 짧으면 "ㅋ" 같은 게 주제가 되고, 길면 화면 상단 바를 넘친다.
Config.PROMPT_MIN_LENGTH = 2
Config.PROMPT_MAX_LENGTH = 24

-- ⚠️ CUSTOM_PROMPT 기능은 TextService:FilterStringAsync 필터링이
--    로블록스 정책상 의무다. 필터 없이 구현하면 안 된다. (§3.1)

-- 확정: "다음에 내가 그리기" 는 **라운드당 2명까지.** (§3.2, 2026-10-26 개발자 결정)
--
-- 그릴 자리가 2개라 두 자리를 다 살 수 있다. 두 명이 다 산 판은
-- 돈 안 낸 사람이 아무도 못 그린다. 처음에는 그게 걱정돼서 1명으로 막았다가,
-- 개발자가 알고 2명으로 정했다. 사는 사람이 많아 무료 유저가 계속 밀리면 1 로 되돌린다.
--
-- 화면의 "sold out" 과 실제 뽑기가 **둘 다 이 숫자를 본다.** 여기만 바꾸면 된다.
Config.DRAW_NEXT_SEATS = 2

--------------------------------------------------------------------
-- 주제
--------------------------------------------------------------------

-- 확정: **고정 딕셔너리**에서 뽑는다. AI 생성은 쓰지 않는다. (README §2)
-- API 비용이 없고 백엔드 서버도 필요 없다.
--
-- 고르는 기준
--   - 3분 안에 그릴 수 있고, 관전자가 보고 알아볼 수 있는 것
--   - 상표·실존 인물·캐릭터 이름은 넣지 않는다 (로블록스 정책)
--   - 무기·폭력은 넣지 않는다
--   - ⚠️ 그림으로 장난치기 쉬운 단어는 **일부러 뺐다** (바나나, 핫도그, 가지, 오이 등).
--      그림은 유저 생성 콘텐츠라 신고 기능(§3.10)이 생기기 전까지는 빌미를 줄이는 편이 낫다.
--
-- 길이는 가운데 연출(PromptReveal)이 알아서 줄여서 맞춘다. 긴 단어도 넣어도 된다.
--
-- 매 판 무작위로 뽑는다. 119개면 1시간(15판)쯤 놀 때 한 번 겹칠 확률이 60% 쯤 된다.
-- "최근 나온 주제는 다시 안 뽑기" 를 검토했지만 **하지 않기로 했다** (2026-10-25, 개발자 결정).
Config.PROMPTS = {
	-- 동물
	"Cat", "Dog", "Fish", "Bird", "Rabbit", "Turtle", "Snake", "Elephant",
	"Giraffe", "Lion", "Penguin", "Octopus", "Shark", "Whale", "Frog", "Owl",
	"Butterfly", "Spider", "Snail", "Duck", "Horse", "Cow", "Pig", "Monkey", "Dinosaur",

	-- 음식
	"Apple", "Pizza", "Hamburger", "Ice Cream", "Cake", "Donut", "Watermelon",
	"Cookie", "Sandwich", "Carrot", "Cheese", "Egg", "Popcorn", "Sushi", "Taco",
	"Strawberry", "Cupcake", "Pineapple", "Bread",

	-- 물건
	"Umbrella", "Guitar", "Lamp", "Chair", "Clock", "Key", "Book", "Glasses",
	"Hat", "Shoe", "Backpack", "Camera", "Phone", "Scissors", "Candle", "Balloon",
	"Kite", "Crown", "Trophy", "Gift", "Mirror", "Ladder", "Bucket", "Toothbrush", "Headphones",

	-- 탈것
	"Car", "Airplane", "Bicycle", "Train", "Boat", "Rocket", "Helicopter", "Bus",
	"Submarine", "Tractor",

	-- 자연과 장소
	"Tree", "Flower", "Mountain", "Volcano", "Island", "Rainbow", "Cloud", "Sun",
	"Moon", "Planet", "Star", "Beach", "Waterfall", "Cactus", "Mushroom", "Snowman",
	"House", "Castle", "Lighthouse", "Bridge",

	-- 상상 속 존재
	"Robot", "Alien", "Dragon", "Ghost", "Wizard", "Mermaid", "Unicorn", "Pirate",
	"Ninja", "Superhero",

	-- 장면
	"Campfire", "Treasure Chest", "Hot Air Balloon", "Igloo", "Tent", "Windmill",
	"Ferris Wheel", "Sandcastle", "Skateboard", "Rollercoaster",
}

--------------------------------------------------------------------
-- 신고
--------------------------------------------------------------------

Config.REPORTS_TO_HIDE = 3 -- [미정] 신고 몇 개면 그림을 즉시 가릴 것인가


--------------------------------------------------------------------
-- 그림판 도구
--------------------------------------------------------------------
-- 배열 순서가 곧 툴바에 놓이는 순서이고, 숫자 단축키(1~7)도 이 순서를 따른다.
--
-- icon 은 지금 이모지로 때운다. 나중에 아이콘 이미지를 만들면
-- iconImage 에 "rbxassetid://..." 를 넣으면 그쪽이 우선 쓰인다.
--
-- 아이콘은 전부 이모지로 골랐다. 화살표나 도형 기호(↶ ／ ◻ 같은 것)는
-- 로블록스 기본 글꼴에 글자가 없어서 빈칸으로 나오는 일이 있다.
-- 이모지는 별도 글꼴로 그려지므로 안전하다.
Config.TOOLS = {
	{ id = "pen", label = "Pen", icon = "✏️", iconImage = "" },
	{ id = "brush", label = "Brush", icon = "🖌️", iconImage = "" },
	{ id = "line", label = "Line", icon = "📏", iconImage = "" },
	{ id = "eraser", label = "Eraser", icon = "🧼", iconImage = "" },
	{ id = "eyedropper", label = "Eyedropper", icon = "💧", iconImage = "" },
}

Config.DEFAULT_TOOL = "pen"

-- 브러시는 아직 "굵고 살짝 연한 펜" 이다.
-- 진짜 부드러운 가장자리(소프트 브러시)는 픽셀 단위로 알파를 주물러야 하는데,
-- EditableImage 픽셀 API 는 README §7-4 대상이라 손대지 않았다.
Config.BRUSH_THICKNESS_MULTIPLIER = 1.6
Config.BRUSH_EXTRA_TRANSPARENCY = 0.25

-- 커서 동그라미가 이보다 작아지면 눈에 안 보인다. 캔버스 픽셀 기준 최소 지름.
Config.MIN_CURSOR_SIZE = 10

-- 스포이드는 굵기라는 게 없으므로 고정 크기를 쓴다.
Config.EYEDROPPER_CURSOR_SIZE = 18

-- 지우개는 굵기를 펜과 따로 기억한다. 실제로 쓸 때 굵기가 크게 다르기 때문이다.
Config.DEFAULT_ERASER_THICKNESS = 24
Config.MIN_ERASER_THICKNESS = 4
Config.MAX_ERASER_THICKNESS = 128

-- 종이 색. 지우개는 "이 색으로 칠하기" 로 동작하므로
-- 이 값과 실제 캔버스 배경색이 반드시 같아야 한다.
Config.CANVAS_BACKGROUND_COLOR = Color3.fromRGB(255, 250, 250)

Config.DEFAULT_COLOR = Color3.fromRGB(0, 0, 0)
Config.DEFAULT_TRANSPARENCY = 0

--------------------------------------------------------------------
-- 색상 팔레트
--------------------------------------------------------------------
-- 8칸 x 2줄. 자주 쓰는 색을 한 번에 집게 하려는 것이고,
-- 정확한 색이 필요하면 Custom 탭의 슬라이더를 쓴다.
Config.PALETTE_COLUMNS = 8
Config.PALETTE = {
	Color3.fromRGB(0, 0, 0),
	Color3.fromRGB(102, 102, 102),
	Color3.fromRGB(170, 170, 170),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(122, 71, 42),
	Color3.fromRGB(196, 132, 74),
	Color3.fromRGB(255, 214, 178),
	Color3.fromRGB(255, 138, 174),

	Color3.fromRGB(226, 42, 42),
	Color3.fromRGB(255, 132, 41),
	Color3.fromRGB(255, 214, 53),
	Color3.fromRGB(126, 205, 62),
	Color3.fromRGB(38, 158, 96),
	Color3.fromRGB(56, 174, 226),
	Color3.fromRGB(41, 78, 204),
	Color3.fromRGB(142, 68, 204),
}

--------------------------------------------------------------------
-- UI 배치 / 색
--------------------------------------------------------------------
Config.UI = {
	-- 1 = 완전 투명. 캔버스 바깥으로 3D 맵이 그대로 보인다.
	-- 화면을 어둡게 깔고 싶어지면 이 값만 0.5 같은 값으로 바꾸면 된다.
	BACKDROP_TRANSPARENCY = 1,
	BACKDROP_COLOR = Color3.fromRGB(0, 0, 0),

	-- 반응형 배치 (계산은 UI/Layout.lua 가 한다)
	--
	-- 이 크기의 화면을 기준으로 UI 를 만들었다. 화면이 더 작으면 그만큼 줄인다.
	REFERENCE_WIDTH = 1280,
	REFERENCE_HEIGHT = 720,

	-- 배율 하한.
	--
	-- 0.6 으로 두었더니 세로가 짧은 폰에서 UI 가 화면을 다 잡아먹었다.
	-- 계산상 필요한 배율이 0.53 인데 0.6 에서 멈춰버려서,
	-- 정사각형인 캔버스가 얇은 띠처럼 눌렸다.
	--
	-- 실제로 확인된 폰 화면이 750x332 였다. 계산상 필요한 배율은 0.46 이다.
	-- 하한을 0.5 로 두면 거기서 멈춰버려 UI 가 필요보다 커진다.
	-- 0.45 면 그 화면에서 하한이 걸리지 않고 계산대로 줄어든다.
	--
	-- 도구 버튼은 74 * 0.46 = 34px 이 된다. 작지만 그 화면 폭의 4.5% 라
	-- 로블록스 점프 버튼과 비슷한 크기다.
	MIN_UI_SCALE = 0.45,

	-- 화면 폭이 이보다 넓으면 색상 패널을 왼쪽에 늘 펼쳐둔다.
	-- 좁으면 서랍으로 접어서 캔버스가 화면을 다 쓰게 한다.
	-- 900 으로 잡으면 폰 가로(852)는 접히고 태블릿(1024)은 펼쳐진다.
	WIDE_LAYOUT_MIN_WIDTH = 900,

	-- 캔버스와 주변 UI 사이 여백
	CANVAS_GAP = 12,

	-- 패널(색상 패널 등) 공통 모양
	PANEL_COLOR = Color3.fromRGB(252, 252, 254),
	PANEL_TRANSPARENCY = 0.03,
	PANEL_CORNER = 14,
	PANEL_STROKE_COLOR = Color3.fromRGB(214, 216, 226),

	-- 패널 안 소제목 줄(“Color Sets” 같은)
	HEADER_COLOR = Color3.fromRGB(238, 239, 245),

	TEXT_COLOR = Color3.fromRGB(46, 48, 58),
	MUTED_TEXT_COLOR = Color3.fromRGB(140, 143, 155),

	-- 선택된 도구/탭을 표시하는 색
	ACCENT_COLOR = Color3.fromRGB(56, 174, 226),

	-- 되돌릴 수 없어 보이는 버튼(전체지우기 확인 등)
	DANGER_COLOR = Color3.fromRGB(226, 62, 62),

	-- 종이가 너무 작아지면 아래쪽 UI 와 겹치더라도 이만큼은 보여준다.
	-- 안 보이는 것보다 겹치는 편이 낫다. 안 보이면 고장으로 읽힌다.
	MIN_CANVAS_SIZE = 160,

	-- 지금 눌러도 소용없는 버튼을 흐리게 만들 때 쓴다.
	-- (되돌릴 게 없을 때의 되돌리기 버튼 등)
	DISABLED_TRANSPARENCY = 0.55,

	-- 좁은 화면에서 색상 패널을 여는 버튼.
	-- 도구 버튼과 같은 크기로 두고 강조색을 칠한다.
	-- 작게 두면 화면 구석에서 눈에 안 띄어 못 찾는다.
	PANEL_TOGGLE_SIZE = 74,

	-- 좌측 색상 패널
	-- 높이는 내용에 따라 정해지지만, 화면에 들어가는지 미리 계산하려면
	-- 대략의 값이 필요하다. Custom 탭이 펼쳐졌을 때 기준이다.
	COLOR_PANEL_HEIGHT = 560,
	COLOR_PANEL_WIDTH = 330,
	COLOR_PANEL_MARGIN = 24,

	-- 별점 줄. 관전 목록 아래에 붙는다.
	STAR_ROW_HEIGHT = 52,
	STAR_SIZE = 40,

	-- 결과 패널 (인터미션에 직전 라운드 결과를 보여준다)
	RESULTS_WIDTH = 420,

	-- 화면 구석에 지금 상태를 적어둔다. 버그를 잡을 때만 켠다.
	-- 무엇이 어긋났는지 화면만 보고 알 수 있어서, 추측하지 않아도 된다.
	SHOW_DEBUG = false,

	-- 주제 뽑기 연출 (화면 한가운데)
	PROMPT_REVEAL_WIDTH = 460,
	PROMPT_REVEAL_HEIGHT = 190,
	-- 연출이 도는 동안 뒤를 얼마나 어둡게 덮을지. 0 = 안 덮음, 1 = 새까맣게.
	PROMPT_DIM_STRENGTH = 0.55,

	-- 관전 UI.
	-- 평소에는 눈 모양 버튼 하나만 있고, 누르면 화면 아래에
	-- 누굴 관전할지 고르는 줄이 펼쳐진다.
	-- 그 줄이 펼쳐진 동안에는 캔버스가 그만큼 자리를 비켜준다. (README §5.4)
	SPECTATE_TOGGLE_SIZE = 74,
	SPECTATE_BUTTON_WIDTH = 180,
	SPECTATE_BUTTON_HEIGHT = 46,
	SPECTATE_BAR_MARGIN = 16,

	-- 그림을 보는 동안 뒤 배경(3D 맵)을 흐리게 한다.
	-- 그림에 눈이 가게 하려는 것이다. 0 으로 두면 흐려지지 않는다.
	BACKGROUND_BLUR = 18,

	-- 색상환
	COLOR_WHEEL_SIZE = 200,
	COLOR_WHEEL_BAR_WIDTH = 26, -- 오른쪽 밝기 막대
	COLOR_WHEEL_GAP = 12,

	-- 원판을 이루는 "살" 개수. 많을수록 매끄럽지만 그만큼 Frame 이 생긴다.
	-- 120 이면 살 하나가 3도라 눈으로는 이음매가 보이지 않는다.
	COLOR_WHEEL_SPOKES = 120,

	-- 상단 바 (주제 / 제출 / 남은 시간)
	TOP_BAR_HEIGHT = 56,
	TOP_BAR_WIDTH = 520,
	-- 화면이 납작한 폰에서는 이 여백 하나하나가 그림 크기를 깎는다.
	-- 750x332 화면 기준으로 위아래 여백을 줄여 캔버스를 그만큼 키웠다.
	TOP_BAR_MARGIN = 4,

	-- 하단 툴바
	TOOL_BUTTON_SIZE = 74,
	TOOL_BUTTON_GAP = 10,
	TOOLBAR_BOTTOM_MARGIN = 10,

	-- 오른쪽 세로줄. 되돌리기·다시하기·전체지우기·팔레트·눈 버튼이 여기 모인다.
	--
	-- 위쪽에 가로로 눕히면 상단 바와 같은 높이를 두고 다투게 되고,
	-- 좁은 화면에서 반드시 겹친다. 세로줄은 위쪽 자리를 아예 안 쓴다.
	-- 승리수 / 점수 표시줄 (화면 왼쪽 아래)
	-- 로블록스 기본 리더보드에 같은 값이 있지만, 모바일에서는 메뉴를 열어야
	-- 보이므로 화면에 늘 띄워둔다.
	-- 상점 창 (화면 한가운데). 아이콘을 눌러야 열린다.
	SHOP_WIDTH = 320,
	SHOP_ROW_HEIGHT = 40,
	SHOP_TOGGLE_SIZE = 74,
	-- 상점 버튼 색. 팔레트 버튼(ACCENT, 파랑)과 달라야 손이 안 헷갈린다.
	SHOP_BUTTON_COLOR = Color3.fromRGB(245, 176, 65),
	-- 엿보기 색. 👀 버튼과, 상대 그림을 보는 동안의 종이 테두리에 쓴다.
	-- 팔레트(파랑)·상점(주황)과 달라야 한다. 같은 색이면 세로줄에서 손이 헷갈린다.
	PEEK_COLOR = Color3.fromRGB(150, 90, 230),
	-- 상대 그림을 보는 동안 종이에 두르는 테두리 두께.
	-- 종이가 내 것과 똑같이 흰색이라, 테두리가 없으면 지금 누구 그림인지 헷갈린다.
	PEEK_BORDER = 6,
	-- 👀 버튼. 그림판 오른쪽 위 모서리 바로 바깥에 붙는다. (DrawBattleUI._buildShop)
	-- 아이콘 아래에 "Peek"/"Back" 글자가 들어가서 세로로 조금 길다.
	--
	-- ⚠️ 폭은 오른쪽 세로줄 폭(PANEL_TOGGLE_SIZE)보다 넓게 하지 말 것.
	--    그림판이 세로줄 앞까지 꽉 차는 화면(세로로 든 폰 등)에서는 이 버튼이
	--    세로줄과 같은 줄에 들어가는데, 더 넓으면 화면 오른쪽 밖으로 삐져나간다.
	PEEK_BUTTON_WIDTH = 74,
	PEEK_BUTTON_HEIGHT = 96,

	-- 짧게 떴다 사라지는 알림 (화면 위쪽 가운데)
	TOAST_TOP = 78, -- 상단 바 바로 아래
	TOAST_HEIGHT = 44,
	TOAST_SECONDS = 3.5,

	-- 그릴 차례 게이지 (화면 왼쪽 아래)
	-- 그리는 동안에는 숨는다. 색상 패널이 정확히 그때만 보이므로 자리가 겹치지 않는다.
	CHANCE_BAR_MARGIN = 16,
	CHANCE_BAR_WIDTH = 240,
	CHANCE_BAR_TRACK_HEIGHT = 10,
	CHANCE_BAR_BUTTON_HEIGHT = 32,
	CHANCE_BAR_TEXT_SIZE = 15,

	STATS_BAR_MARGIN = 16, -- 화면 가장자리에서 띄우는 거리
	STATS_BAR_GAP = 14, -- 승리수와 점수 사이
	STATS_BAR_TEXT_SIZE = 18, -- 이 값 하나로 줄 전체가 커지고 작아진다

	SIDE_BAR_MARGIN = 16,
	SIDE_BAR_GAP = 10,

	-- 되돌리기 / 다시하기 / 전체지우기 버튼
	ACTION_BUTTON_SIZE = 62,
	ACTION_BUTTON_GAP = 10,
	ACTION_TOP_MARGIN = 12,
}

return Config
