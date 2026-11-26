#!/bin/sh
# tests/run.sh：status.sh、maintain.sh、prune.sh 的自動化測試。
# 全部在 mktemp -d 建的暫存資料夾裡跑，跑完刪掉；不讀寫真的 ~/.canopy-chronicle。
# 用法：sh tests/run.sh          （預設用 sh 執行腳本）
#       TEST_SH=dash sh tests/run.sh

LC_ALL=C
export LC_ALL

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
SCRIPTS=$HERE/../skills/canopy-chronicle/scripts
SH=${TEST_SH:-sh}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/chronicle-test.XXXXXX") || exit 2
trap 'rm -rf -- "$TMP"' EXIT
trap 'exit 130' INT TERM

# 第二道保險：就算哪裡漏設 CANOPY_CHRONICLE_HOME，也只會落在暫存資料夾。
HOME=$TMP/home
export HOME
mkdir -p -- "$HOME"

ROOT="$TMP/root dir"
TRASH="$TMP/trash bin"
CANOPY_CHRONICLE_HOME=$ROOT
CANOPY_CHRONICLE_TRASH=$TRASH
CANOPY_CHRONICLE_TODAY=2026-11-26
export CANOPY_CHRONICLE_HOME CANOPY_CHRONICLE_TRASH CANOPY_CHRONICLE_TODAY

PASS=0
FAIL=0

ok() {
	PASS=$((PASS + 1))
	printf 'ok    %s\n' "$1"
}

ng() {
	FAIL=$((FAIL + 1))
	printf 'FAIL  %s\n' "$1"
	[ -n "${OUT:-}" ] && printf '%s\n' "$OUT" | sed 's/^/        | /'
}

# 執行腳本：run 名稱 參數…；結果放在 OUT（含標準錯誤）與 CODE。
run() {
	_s=$1
	shift
	OUT=$("$SH" "$SCRIPTS/$_s.sh" "$@" 2>&1)
	CODE=$?
}

# 帶一個環境變數執行：run_env 名稱=值 腳本 參數…
run_env() {
	_e=$1
	_s=$2
	shift 2
	OUT=$(env "$_e" "$SH" "$SCRIPTS/$_s.sh" "$@" 2>&1)
	CODE=$?
}

expect_code() {
	if [ "$CODE" = "$1" ]; then ok "$2"; else ng "$2（結束碼 $CODE，預期 $1）"; fi
}

expect_out() {
	case $OUT in
	*"$1"*) ok "$2" ;;
	*) ng "$2（輸出沒有「$1」）" ;;
	esac
}

expect_no_out() {
	case $OUT in
	*"$1"*) ng "$2（輸出不該有「$1」）" ;;
	*) ok "$2" ;;
	esac
}

check() {
	_d=$1
	shift
	if "$@"; then ok "$_d"; else ng "$_d"; fi
}

# 條件寫成一段 sh 字串（測試自己寫的），用於需要 && 的檢查。
check_all() {
	if eval "$2"; then ok "$1"; else ng "$1"; fi
}

# 資料夾的指紋：所有路徑加上每個檔的 cksum。資料夾不存在時印 missing。
tree_sum() {
	if [ -d "$1" ]; then
		(cd -- "$1" && find . -print | sort && find . -type f -exec cksum {} + | sort)
	else
		printf 'missing\n'
	fi
}

fresh_root() {
	rm -rf -- "$ROOT" "$TRASH"
	mkdir -p -- "$ROOT"
}

# 建一個專案：mkproj 代號
mkproj() {
	mkdir -p -- "$ROOT/$1"
	printf '# %s\n\n範圍：測試用\n建立：2026-11-26\n' "$1" >"$ROOT/$1/PROJECT.md"
	printf '# 釘選\n\n## 仍有效的決定\n- 測試用的釘選（2026-11-01-01）\n' >"$ROOT/$1/PINNED.md"
}

# 照 Skill 的寫法手動追加一筆：紀錄進月份檔，索引行進 INDEX.md。
# add 代號 編號 類型 標題 關鍵字
add() {
	_mon=$(printf '%s' "$2" | cut -c1-7)
	{
		printf '## %s %s\n' "$2" "$4"
		printf -- '- 類型：%s\n' "$3"
		printf -- '- 關鍵字：%s\n' "$5"
		printf '\n內容：測試紀錄 %s。\n原因：測試。\n\n' "$2"
	} >>"$ROOT/$1/$_mon.md"
	printf '%s | %s | %s | %s | %s\n' "$2" "$3" "$4" "$5" "$_mon.md" >>"$ROOT/$1/INDEX.md"
}

# 把某個月份手動封存（用來準備刪除測試的資料），索引行改指向封存檔。
archive_by_hand() {
	mkdir -p -- "$ROOT/$1/archive"
	gzip -n -c -- "$ROOT/$1/$2.md" >"$ROOT/$1/archive/$2.md.gz"
	rm -f -- "$ROOT/$1/$2.md"
	sed "s#| $2.md\$#| archive/$2.md.gz#" "$ROOT/$1/INDEX.md" >"$TMP/idx" && mv -- "$TMP/idx" "$ROOT/$1/INDEX.md"
}

printf '用 %s 執行腳本；暫存資料夾：%s\n' "$SH" "$TMP"

# ---------------------------------------------------------------- 1. 正常與格式錯誤
fresh_root
mkproj app
add app 2026-11-26-01 決定 '金額用整數分' '結帳, 折扣, 四捨五入'
add app 2026-11-26-02 完成 '結帳頁上線' '結帳'
add app 2026-11-26-03 踩坑 '時區造成日期差一天' '時區, Invalid date'
run status app
expect_code 0 "1 正常紀錄：status 結束碼 0"
expect_out "沒有問題" "1 正常紀錄：印出沒有問題"
run status
expect_code 0 "1 不指定專案：全部檢查結束碼 0"

# bad 案例名 編號 類型 標題 關鍵字 預期訊息片段：建立只有這一筆壞掉的專案，檢查結束碼 1 且指出那一筆。
bad() {
	fresh_root
	mkproj app
	add app 2026-11-26-01 決定 '好的一筆' '甲'
	add app "$2" "$3" "$4" "$5"
	run status app
	expect_code 1 "1 $1：結束碼 1"
	expect_out "2026-11.md $2：" "1 $1：指出 $2"
	expect_out "$6" "1 $1：訊息含「$6」"
}
bad '類型不在六種' 2026-11-26-02 其他 '標題' '甲' '不是六種之一'
bad '編號格式不對' 2026-11-26-2 決定 '標題' '甲' '編號格式不對'
bad '編號重複' 2026-11-26-01 決定 '標題' '甲' '編號重複'
bad '標題含 |' 2026-11-26-02 決定 'a | b' '甲' '標題含 |'
bad '關鍵字含 |' 2026-11-26-02 決定 '標題' '甲|乙' '關鍵字含 |'
bad '關鍵字超過六個' 2026-11-26-02 決定 '標題' 'a,b,c,d,e,f,g' '最多六個'

# 缺必填欄位：手寫月份檔，索引照重建規則（缺的欄位為空）補上。
fresh_root
mkproj app
add app 2026-11-26-01 決定 '好的一筆' '甲'
printf '## 2026-11-26-02 缺類型\n- 關鍵字：甲\n\n內容。\n' >>"$ROOT/app/2026-11.md"
printf '## 2026-11-26-03 缺關鍵字\n- 類型：完成\n\n內容。\n' >>"$ROOT/app/2026-11.md"
printf '%s\n' '2026-11-26-02 |  | 缺類型 | 甲 | 2026-11.md' '2026-11-26-03 | 完成 | 缺關鍵字 |  | 2026-11.md' >>"$ROOT/app/INDEX.md"
run status app
expect_code 1 "1 缺必填欄位：結束碼 1"
expect_out "2026-11-26-02：缺「- 類型：」" "1 缺類型：指出 2026-11-26-02"
expect_out "2026-11-26-03：缺「- 關鍵字：」" "1 缺關鍵字：指出 2026-11-26-03"
expect_no_out "對不上" "1 缺必填欄位：索引本身沒有被誤判"

# 索引和紀錄對不上：紀錄有、索引沒寫。
fresh_root
mkproj app
add app 2026-11-26-01 決定 '一' '甲'
printf '## 2026-11-26-02 忘了寫索引\n- 類型：完成\n- 關鍵字：乙\n\n內容。\n' >>"$ROOT/app/2026-11.md"
run status app
expect_code 1 "1 索引少一行：結束碼 1"
expect_out "索引 1 行，紀錄 2 筆" "1 索引少一行：指出行數與筆數"

# PINNED.md 超過上限（預設 30 行）。
fresh_root
mkproj app
add app 2026-11-26-01 決定 '一' '甲'
awk 'BEGIN { for (i = 1; i <= 31; i++) print "- 第 " i " 行（2026-11-26-01）" }' >"$ROOT/app/PINNED.md"
run status app
expect_code 1 "1 PINNED 太長：結束碼 1"
expect_out "PINNED.md 有 31 行" "1 PINNED 太長：指出行數"

# 專案大小超過上限（預設 512 KB）。
fresh_root
mkproj app
add app 2026-11-26-01 決定 '一' '甲'
awk 'BEGIN { s = "0123456789012345678901234567890123456789012345678901234567890123456789"; for (i = 0; i < 8000; i++) print s }' >>"$ROOT/app/2026-11.md"
run status app
expect_code 1 "1 專案太大：結束碼 1"
expect_out "超過上限 512 KB" "1 專案太大：指出大小"

# ---------------------------------------------------------------- 2. 開場摘要
fresh_root
mkproj app
printf '# 釘選\n\n## 仍有效的決定\n- 獨特的釘選句子\n' >"$ROOT/app/PINNED.md"
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do
	add app "2026-11-26-$i" 完成 "第 $i 筆" "k$i"
done
run status --brief app
expect_code 0 "2 --brief：結束碼 0"
expect_out "獨特的釘選句子" "2 --brief：印出 PINNED.md"
want=$(tail -n 10 "$ROOT/app/INDEX.md")
expect_out "$want" "2 --brief：印出索引最後 10 行"
expect_no_out "2026-11-26-02 |" "2 --brief：不印第 10 行以前的索引"
run status --brief
check "2 --brief 沒給專案：非零結束碼" [ "$CODE" -ne 0 ]

# ---------------------------------------------------------------- 3. 預演不改任何檔案
# 準備三支腳本都有事可做的資料：索引過期、有可封存的月份、有可刪的封存檔。
fresh_root
mkproj app
printf 'KEEP_MIN_ENTRIES=1\n' >"$ROOT/config"
add app 2025-01-05-01 完成 '很舊' '舊'
archive_by_hand app 2025-01
add app 2026-06-01-01 完成 '可封存' '六月'
add app 2026-11-26-01 完成 '當月' '十一月'
printf '## 2026-11-26-02 索引沒寫\n- 類型：完成\n- 關鍵字：甲\n\n內容。\n' >>"$ROOT/app/2026-11.md"
before=$(tree_sum "$ROOT"; tree_sum "$TRASH")
run status
check "3 預演資料：status 有抓到問題" [ "$CODE" = 1 ]
run maintain
expect_out "會封存 2026-06" "3 maintain 預演：列出會封存的月份"
run maintain app
run prune
expect_out "可移走 archive/2025-01.md.gz" "3 prune 預演：列出可移走的檔案"
run prune app
run status --brief app
after=$(tree_sum "$ROOT"; tree_sum "$TRASH")
check "3 三支腳本預演前後，資料夾指紋相同" [ "$before" = "$after" ]

# ---------------------------------------------------------------- 4. 重建索引和手動追加的結果相同
fresh_root
mkproj app
add app 2026-09-08-09 決定 '九月  兩個空白' 'a, b,c'
add app 2026-09-09-01 要求 '使用者說：先別動' '要求, 原話'
add app 2026-10-01-01 驗收 '十月驗收' '驗收'
add app 2026-11-26-01 擱置 '匯出先不做' '匯出, PDF'
cp -- "$ROOT/app/INDEX.md" "$TMP/manual"
pp_before=$(cksum <"$ROOT/app/PROJECT.md"; cksum <"$ROOT/app/PINNED.md")
run maintain app
expect_out "索引已是最新" "4 手動追加的索引：maintain 判定已是最新"
rm -f -- "$ROOT/app/INDEX.md"
run maintain --apply app
expect_code 0 "4 maintain --apply：結束碼 0"
check "4 重建的 INDEX.md 和手動追加的逐位元組相同" cmp -s "$TMP/manual" "$ROOT/app/INDEX.md"
check "4 沒有月份被封存" [ ! -d "$ROOT/app/archive" ]
pp_after=$(cksum <"$ROOT/app/PROJECT.md"; cksum <"$ROOT/app/PINNED.md")
check "4 PROJECT.md、PINNED.md 沒被改" [ "$pp_before" = "$pp_after" ]

# ---------------------------------------------------------------- 5. 封存
# 今天 2026-11，KEEP_MONTHS=3：07、08 月可封存，09 月以後不行。
# 筆數：07 兩筆、08 兩筆、09～11 各一筆，共 7 筆；KEEP_MIN_ENTRIES=4。
# 封存 07 後剩 5 筆（可以），再封存 08 會剩 3 筆（不足），所以只封存 07。
fresh_root
mkproj app
printf 'KEEP_MIN_ENTRIES=4\n' >"$ROOT/config"
add app 2026-07-01-01 完成 '七月一' '七月'
add app 2026-07-02-01 決定 '七月二' '七月'
add app 2026-08-01-01 完成 '八月一' '八月'
add app 2026-08-09-01 踩坑 '八月二' '八月'
add app 2026-09-01-01 完成 '九月' '九月'
add app 2026-10-01-01 完成 '十月' '十月'
add app 2026-11-01-01 完成 '十一月' '十一月'
cp -- "$ROOT/app/2026-07.md" "$TMP/july"
sed 's#| 2026-07.md$#| archive/2026-07.md.gz#' "$ROOT/app/INDEX.md" >"$TMP/expected-index"
pp_before=$(cksum <"$ROOT/app/PROJECT.md"; cksum <"$ROOT/app/PINNED.md")
run maintain --apply app
expect_code 0 "5 封存：結束碼 0"
check "5 2026-07 封存到 archive/2026-07.md.gz" [ -f "$ROOT/app/archive/2026-07.md.gz" ]
check "5 2026-07.md 原檔移走" [ ! -e "$ROOT/app/2026-07.md" ]
check_all "5 2026-08 因筆數不足 KEEP_MIN_ENTRIES 沒封存" '[ -f "$ROOT/app/2026-08.md" ] && [ ! -e "$ROOT/app/archive/2026-08.md.gz" ]'
expect_out "2026-08 不封存" "5 說明 2026-08 為什麼不封存"
gzip -dc -- "$ROOT/app/archive/2026-07.md.gz" >"$TMP/july-back"
check "5 封存檔解壓後和原檔相同" cmp -s "$TMP/july" "$TMP/july-back"
check "5 索引指向 archive/2026-07.md.gz，其餘不變" cmp -s "$TMP/expected-index" "$ROOT/app/INDEX.md"
pp_after=$(cksum <"$ROOT/app/PROJECT.md"; cksum <"$ROOT/app/PINNED.md")
check "5 PROJECT.md、PINNED.md 沒被改" [ "$pp_before" = "$pp_after" ]
run status app
expect_code 0 "5 封存後 status 結束碼 0"
rm -f -- "$ROOT/app/INDEX.md"
run maintain --apply app
check "5 刪掉 INDEX.md 重建（含 .gz）結果相同" cmp -s "$TMP/expected-index" "$ROOT/app/INDEX.md"

# KEEP_MIN_ENTRIES=0：07、08 都封存，09 未滿 KEEP_MONTHS 不封存。
printf 'KEEP_MIN_ENTRIES=0\n' >"$ROOT/config"
run maintain --apply app
check "5 筆數條件放寬後 2026-08 封存" [ -f "$ROOT/app/archive/2026-08.md.gz" ]
check "5 2026-09 未滿 KEEP_MONTHS 不封存" [ -f "$ROOT/app/2026-09.md" ]

# 筆數不足時一個都不封存（預設 KEEP_MIN_ENTRIES=50）。
fresh_root
mkproj app
add app 2026-01-01-01 完成 '很舊' '舊'
add app 2026-11-01-01 完成 '當月' '新'
run maintain --apply app
check_all "5 預設 50 筆下限：舊月份不封存" '[ -f "$ROOT/app/2026-01.md" ] && [ ! -d "$ROOT/app/archive" ]'

# ---------------------------------------------------------------- 6. 刪除（移到刪除的去處）
# 2025-08 的月份：KEEP_MONTHS 3 ＋ ARCHIVE_KEEP_MONTHS 12 ＝ 距今滿 15 個月才列入，也就是 2026-11。
fresh_root
mkproj app
add app 2025-08-01-01 完成 '要移走的' '舊'
add app 2025-07-01-01 完成 '撞名的' '舊'
add app 2026-11-01-01 完成 '當月' '新'
archive_by_hand app 2025-07
archive_by_hand app 2025-08
cp -- "$ROOT/app/archive/2025-08.md.gz" "$TMP/aug-gz"
cp -- "$ROOT/app/archive/2025-07.md.gz" "$TMP/jul-gz"
mkdir -p -- "$TRASH/app"
printf '原本就在的檔\n' >"$TRASH/app/2025-07.md.gz"
cp -- "$TRASH/app/2025-07.md.gz" "$TMP/trash-existing"

run_env CANOPY_CHRONICLE_TODAY=2026-10-31 prune app
expect_no_out "2025-08" "6 未滿期限（距今 14 個月）：2025-08 不列入"
expect_out "可移走 archive/2025-07.md.gz" "6 剛滿期限（距今 15 個月）：2025-07 列入"
run prune app
expect_out "可移走 archive/2025-08.md.gz" "6 滿期限（距今 15 個月）：2025-08 列入"
check "6 不帶 --apply：檔案還在原處" [ -f "$ROOT/app/archive/2025-08.md.gz" ]
run prune --apply app
expect_code 0 "6 prune --apply：結束碼 0"
check "6 原處的 2025-08 消失" [ ! -e "$ROOT/app/archive/2025-08.md.gz" ]
check "6 2025-08 出現在刪除的去處且內容相同" cmp -s "$TMP/aug-gz" "$TRASH/app/2025-08.md.gz"
check "6 去處已有同名檔時不覆蓋" cmp -s "$TMP/trash-existing" "$TRASH/app/2025-07.md.gz"
check "6 撞名的改名存放且內容相同" cmp -s "$TMP/jul-gz" "$TRASH/app/2025-07.2.md.gz"
check "6 索引拿掉移走的紀錄" [ "$(cat -- "$ROOT/app/INDEX.md")" = '2026-11-01-01 | 完成 | 當月 | 新 | 2026-11.md' ]
run status app
expect_code 0 "6 刪除後 status 結束碼 0"

# ---------------------------------------------------------------- 7. config
fresh_root
mkproj app
add app 2026-10-01-01 完成 '十月' '十月'
add app 2026-11-01-01 完成 '十一月' '十一月'
printf '# 註解\nKEEP_MONTHS=1\nKEEP_MIN_ENTRIES=0\nPINNED_MAX_LINES=2\n' >"$ROOT/config"
run maintain app
expect_out "會封存 2026-10" "7 config 覆寫 KEEP_MONTHS：2026-10 變成可封存"
run status app
expect_out "超過上限 2 行" "7 config 覆寫 PINNED_MAX_LINES"

M=$TMP/pwned
{
	printf 'KEEP_MONTHS=1\n'
	printf 'KEEP_MIN_ENTRIES=0\n'
	printf 'touch "%s-1"\n' "$M"
	printf 'PINNED_MAX_LINES=$(touch "%s-2")\n' "$M"
	printf 'PROJECT_MAX_KB=`touch "%s-3"`\n' "$M"
	printf 'ARCHIVE_KEEP_MONTHS=1; touch "%s-4"\n' "$M"
	printf 'KEEP_MONTHS=2 && touch "%s-5"\n' "$M"
	printf 'PATH=/nonexistent\n'
} >"$ROOT/config"
run status app
status_out=$OUT
status_code=$CODE
run maintain app
maintain_out=$OUT
run prune app
check_all "7 惡意 config：沒有任何夾帶的指令被執行" '[ ! -e "$M-1" ] && [ ! -e "$M-2" ] && [ ! -e "$M-3" ] && [ ! -e "$M-4" ] && [ ! -e "$M-5" ]'
OUT=$status_out
expect_out "config 第 3 行看不懂" "7 惡意 config：status 指出看不懂的行"
check "7 惡意 config：status 結束碼 1" [ "$status_code" = 1 ]
OUT=$maintain_out
expect_out "會封存 2026-10" "7 惡意 config：合法的行照樣生效"

# ---------------------------------------------------------------- 多專案、多月份與異常的封存
# 不指定專案時兩個專案都要處理，每個專案兩個舊月份都封存，刪除去處依專案分開。
fresh_root
printf 'KEEP_MIN_ENTRIES=0\n' >"$ROOT/config"
for p in alpha 'b app'; do
	mkproj "$p"
	add "$p" 2025-01-01-01 完成 '到期' '舊'
	archive_by_hand "$p" 2025-01
	add "$p" 2026-06-01-01 完成 '六月' '六月'
	add "$p" 2026-07-01-01 完成 '七月' '七月'
	add "$p" 2026-11-01-01 完成 '當月' '當月'
done
run maintain --apply
expect_code 0 "多專案 maintain --apply：結束碼 0"
run prune --apply
expect_code 0 "多專案 prune --apply：結束碼 0"
for p in alpha 'b app'; do
	check_all "多專案 $p：06、07 都封存" '[ -f "$ROOT/$p/archive/2026-06.md.gz" ] && [ -f "$ROOT/$p/archive/2026-07.md.gz" ]'
	check "多專案 $p：到期的封存檔移到自己的去處" [ -f "$TRASH/$p/2025-01.md.gz" ]
done
run status
expect_out "共 1 個問題" "多專案處理後 status 只剩代號含空白的命名提醒"
expect_no_out "對不上" "多專案處理後索引都對得上"

# archive/ 已有同名檔：不覆蓋、結束碼 1、原檔保留。
fresh_root
mkproj app
printf 'KEEP_MIN_ENTRIES=0\n' >"$ROOT/config"
add app 2026-06-01-01 完成 '六月' '六月'
mkdir -p -- "$ROOT/app/archive"
printf '已經在這裡\n' | gzip -n -c >"$ROOT/app/archive/2026-06.md.gz"
cp -- "$ROOT/app/archive/2026-06.md.gz" "$TMP/arch-existing"
run maintain --apply app
check "archive 已有同名檔：結束碼 1" [ "$CODE" = 1 ]
check_all "archive 已有同名檔：不覆蓋且原檔保留" 'cmp -s "$TMP/arch-existing" "$ROOT/app/archive/2026-06.md.gz" && [ -f "$ROOT/app/2026-06.md" ]'

# 壞掉的 .gz：status 回報、maintain 不覆寫索引。
fresh_root
mkproj app
add app 2026-11-01-01 完成 '當月' '當月'
mkdir -p -- "$ROOT/app/archive"
printf '這不是壓縮檔\n' >"$ROOT/app/archive/2026-01.md.gz"
cp -- "$ROOT/app/INDEX.md" "$TMP/idx-before"
run status app
check "壞掉的 .gz：status 結束碼 1" [ "$CODE" = 1 ]
expect_out "讀不了 archive/2026-01.md.gz" "壞掉的 .gz：status 指出哪個檔"
run maintain --apply app
check "壞掉的 .gz：maintain 結束碼 1" [ "$CODE" = 1 ]
check "壞掉的 .gz：INDEX.md 沒被覆寫" cmp -s "$TMP/idx-before" "$ROOT/app/INDEX.md"

# ---------------------------------------------------------------- 8. 空白、不存在的專案與根目錄
fresh_root
mkproj 'my app'
add 'my app' 2026-11-26-01 完成 '空白代號' '空白'
run status 'my app'
expect_out "只能用小寫英數與連字號" "8 代號含空白：status 照常檢查並提醒命名"
expect_no_out "對不上" "8 代號含空白：索引檢查正常"
run status --brief 'my app'
expect_code 0 "8 代號含空白：--brief 正常"
expect_out "空白代號" "8 代號含空白：--brief 印出索引"
rm -f -- "$ROOT/my app/INDEX.md"
run maintain --apply 'my app'
check "8 代號含空白：maintain --apply 重建索引" [ -f "$ROOT/my app/INDEX.md" ]
run maintain --apply
expect_code 0 "8 代號含空白：不指定專案時也正常"

for s in status maintain prune; do
	run "$s" nope
	check "8 專案不存在：$s 非零結束碼" [ "$CODE" -ne 0 ]
	expect_out "找不到專案「nope」" "8 專案不存在：$s 說清楚"
	run "$s" ../x
	check "8 代號含 ..：$s 拒絕" [ "$CODE" -ne 0 ]
done

for s in status maintain prune; do
	run_env CANOPY_CHRONICLE_HOME="$TMP/no such root" "$s"
	check "8 根目錄不存在：$s 非零結束碼" [ "$CODE" -ne 0 ]
	expect_out "紀錄根目錄不存在" "8 根目錄不存在：$s 說清楚"
done
run_env CANOPY_CHRONICLE_HOME="$TMP/no such root" maintain --apply
check "8 根目錄不存在：不會被建立" [ ! -e "$TMP/no such root" ]

run_env CANOPY_CHRONICLE_TODAY=2026/11/26 maintain
check "8 CANOPY_CHRONICLE_TODAY 格式錯：非零結束碼" [ "$CODE" -ne 0 ]

check "保險：暫存的家目錄裡沒有長出 .canopy-chronicle" [ ! -e "$HOME/.canopy-chronicle" ]

printf '\n通過 %s，失敗 %s\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
