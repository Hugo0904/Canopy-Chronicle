# lib.sh：status.sh、maintain.sh、prune.sh 共用的函式。由它們引入，不單獨執行。
# 格式定義見 ../references/format.md；改格式時這裡、format.md 與 tests/run.sh 要一起改。

# 中文欄位名以位元組比對，不受使用者的語系設定影響。
LC_ALL=C
export LC_ALL

CR=$(printf '\r')

die() {
	printf '%s\n' "$*" >&2
	exit 2
}

warn() {
	printf '%s\n' "$*" >&2
}

# 去掉前導零，避免 08、09 在算術裡被當成八進位。
dec() {
	_d=$1
	while [ "${#_d}" -gt 1 ] && [ "${_d#0}" != "$_d" ]; do
		_d=${_d#0}
	done
	printf '%s' "$_d"
}

# 根目錄與刪除的去處。
load_root() {
	if [ -n "${CANOPY_CHRONICLE_HOME:-}" ]; then
		ROOT=$CANOPY_CHRONICLE_HOME
	elif [ -n "${HOME:-}" ]; then
		ROOT=$HOME/.canopy-chronicle
	else
		die "找不到紀錄根目錄：沒有設定 HOME 或 CANOPY_CHRONICLE_HOME"
	fi
	TRASH=${CANOPY_CHRONICLE_TRASH:-$ROOT/.trash}
	[ -d "$ROOT" ] || die "紀錄根目錄不存在：$ROOT"
}

# 今天的「年×12＋月」。CANOPY_CHRONICLE_TODAY=YYYY-MM-DD 可覆寫（測試用）。
load_today() {
	if [ -n "${CANOPY_CHRONICLE_TODAY:-}" ]; then
		case $CANOPY_CHRONICLE_TODAY in
		[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
		*) die "CANOPY_CHRONICLE_TODAY 要寫成 YYYY-MM-DD：$CANOPY_CHRONICLE_TODAY" ;;
		esac
		_y=${CANOPY_CHRONICLE_TODAY%%-*}
		_m=${CANOPY_CHRONICLE_TODAY#*-}
		_m=${_m%%-*}
	else
		_y=$(date +%Y)
		_m=$(date +%m)
	fi
	_y=$(dec "$_y")
	_m=$(dec "$_m")
	if [ "$_m" -lt 1 ] || [ "$_m" -gt 12 ]; then
		die "今天的月份不合理：$_m"
	fi
	TODAY_YM=$((_y * 12 + _m))
}

# "2026-08" 轉成「年×12＋月」。
month_ym() {
	_y=$(dec "${1%%-*}")
	_m=$(dec "${1#*-}")
	printf '%s' "$((_y * 12 + _m))"
}

# 讀 config：逐行解析，只接受已知名稱與純數字，絕不執行檔案內容。
load_config() {
	KEEP_MONTHS=3
	KEEP_MIN_ENTRIES=50
	ARCHIVE_KEEP_MONTHS=12
	PROJECT_MAX_KB=512
	PINNED_MAX_LINES=30
	CONFIG_BAD=0
	_f=$ROOT/config
	[ -f "$_f" ] || return 0
	_n=0
	while IFS= read -r _line || [ -n "$_line" ]; do
		_n=$((_n + 1))
		_line=${_line%"$CR"}
		case $_line in
		'#'* | '') continue ;;
		*[!\ \	]*) ;;
		*) continue ;;
		esac
		_name=${_line%%=*}
		_val=${_line#*=}
		_ok=1
		[ "$_name" = "$_line" ] && _ok=0
		case $_val in
		'' | *[!0-9]*) _ok=0 ;;
		esac
		[ "${#_val}" -gt 6 ] && _ok=0
		if [ "$_ok" = 1 ]; then
			_val=$(dec "$_val")
			case $_name in
			KEEP_MONTHS) [ "$_val" -ge 1 ] && KEEP_MONTHS=$_val || _ok=0 ;;
			KEEP_MIN_ENTRIES) KEEP_MIN_ENTRIES=$_val ;;
			ARCHIVE_KEEP_MONTHS) ARCHIVE_KEEP_MONTHS=$_val ;;
			PROJECT_MAX_KB) [ "$_val" -ge 1 ] && PROJECT_MAX_KB=$_val || _ok=0 ;;
			PINNED_MAX_LINES) [ "$_val" -ge 1 ] && PINNED_MAX_LINES=$_val || _ok=0 ;;
			*) _ok=0 ;;
			esac
		fi
		if [ "$_ok" = 0 ]; then
			warn "config 第 $_n 行看不懂，已略過（格式是「名稱=數字」）"
			CONFIG_BAD=$((CONFIG_BAD + 1))
		fi
	done <"$_f"
}

# 檢查使用者給的專案代號，並設定 PDIR。命名不合規不拒絕，只擋會跑出根目錄的寫法。
use_project() {
	case $1 in
	'' | . | .. | */* | .* | -*) die "專案代號不合法：$1" ;;
	esac
	[ -d "$ROOT/$1" ] || die "找不到專案「$1」（根目錄：$ROOT）"
	PDIR=$ROOT/$1
}

# 根目錄底下的專案代號，一行一個；略過點開頭的資料夾（例如 .trash）。
list_projects() {
	for _p in "$ROOT"/*/; do
		[ -d "$_p" ] || continue
		_p=${_p%/}
		printf '%s\n' "${_p##*/}"
	done
}

# 專案的紀錄檔（相對路徑），依月份由舊到新；同月份時封存檔在前。
record_files() {
	{
		for _f in "$1"/archive/[0-9][0-9][0-9][0-9]-[0-9][0-9].md.gz; do
			[ -f "$_f" ] || continue
			_b=${_f##*/}
			printf '%s 0 archive/%s\n' "${_b%.md.gz}" "$_b"
		done
		for _f in "$1"/[0-9][0-9][0-9][0-9]-[0-9][0-9].md; do
			[ -f "$_f" ] || continue
			_b=${_f##*/}
			printf '%s 1 %s\n' "${_b%.md}" "$_b"
		done
	} | sort | cut -d' ' -f3
}

# 未封存的月份檔（YYYY-MM），由舊到新。
live_months() {
	for _f in "$1"/[0-9][0-9][0-9][0-9]-[0-9][0-9].md; do
		[ -f "$_f" ] || continue
		_b=${_f##*/}
		printf '%s\n' "${_b%.md}"
	done | sort
}

# 一個檔有幾筆紀錄。
count_entries() {
	case $1 in
	*.gz) gzip -dc -- "$1" | grep -c '^## ' ;;
	*) grep -c '^## ' "$1" ;;
	esac
}

# 確認每個紀錄檔都讀得到；讀不到的檔逐一回報，回傳 1。
check_sources() {
	_rc=0
	for _r in $(record_files "$1"); do
		case $_r in
		*.gz) gzip -t -- "$1/$_r" 2>/dev/null || { warn "讀不了 $_r（壓縮檔壞了？）"; _rc=1; } ;;
		*) [ -r "$1/$_r" ] || { warn "讀不了 $_r"; _rc=1; } ;;
		esac
	done
	return $_rc
}

# 把所有紀錄檔串成一條資料流，每個檔前面放一行「\036相對路徑」當分隔。
record_stream() {
	for _r in $(record_files "$1"); do
		printf '\036%s\n' "$_r"
		case $_r in
		*.gz) gzip -dc -- "$1/$_r" ;;
		*) cat -- "$1/$_r" ;;
		esac
		printf '\n'
	done
}

# 解析資料流。mode=index 印出索引；mode=check 印出格式問題，一行一件。
PARSE_AWK='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function prob(msg) { print file " " (id == "" ? "（沒有編號）" : id) "：" msg }
function check(   n, a, i, k, okfmt) {
	okfmt = (id ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/)
	if (okfmt) {
		mm = substr(id, 6, 2) + 0; dd = substr(id, 9, 2) + 0; nn = substr(id, 12, 2) + 0
		if (mm < 1 || mm > 12 || dd < 1 || dd > 31 || nn < 1) okfmt = 0
	}
	if (!okfmt) prob("編號格式不對，要是 YYYY-MM-DD-NN（NN 從 01 起）")
	else if (substr(id, 1, 7) != fmon) prob("編號的月份和所在檔案不同")
	if (id != "" && (id in seen)) prob("編號重複（另一筆在 " seen[id] "）")
	else if (id != "") seen[id] = file
	if (title == "") prob("缺標題")
	if (index(title, "|")) prob("標題含 |")
	if (ht == 0) prob("缺「- 類型：」，要緊接在標題行下面")
	else if (!(typ in TYPES)) prob("類型「" typ "」不是六種之一（完成、決定、要求、踩坑、驗收、擱置）")
	if (hk == 0) prob("缺「- 關鍵字：」，要緊接在標題行下面")
	else {
		if (index(kw, "|")) prob("關鍵字含 |")
		if (index(kw, "，")) prob("關鍵字要用半形逗號分隔")
		n = split(kw, a, ",")
		if (n == 0) prob("關鍵字是空的")
		else if (n > 6) prob("關鍵字有 " n " 個，最多六個")
		for (i = 1; i <= n; i++) if (trim(a[i]) == "") { prob("關鍵字有空的一項"); break }
	}
}
function flush() {
	if (!have) return
	if (mode == "index") print id " | " typ " | " title " | " kw " | " file
	else check()
	have = 0
}
BEGIN {
	T1 = "- 類型："; T2 = "- 關鍵字："; T3 = "- 相關："
	split("完成 決定 要求 踩坑 驗收 擱置", tl, " ")
	for (i in tl) TYPES[tl[i]] = 1
}
{ sub(/\r$/, "") }
substr($0, 1, 1) == "\036" {
	flush(); file = substr($0, 2)
	fmon = file; sub(/^archive\//, "", fmon); fmon = substr(fmon, 1, 7)
	next
}
substr($0, 1, 3) == "## " {
	flush(); have = 1; infields = 1
	rest = substr($0, 4); sp = index(rest, " ")
	if (sp) { id = substr(rest, 1, sp - 1); title = trim(substr(rest, sp + 1)) }
	else { id = trim(rest); title = "" }
	typ = ""; kw = ""; ht = 0; hk = 0
	next
}
have && infields {
	if (index($0, T1) == 1) { typ = trim(substr($0, length(T1) + 1)); ht++; next }
	if (index($0, T2) == 1) { kw = trim(substr($0, length(T2) + 1)); hk++; next }
	if (index($0, T3) == 1) next
	infields = 0
}
END { flush() }
'

# 從紀錄檔重建索引，印到標準輸出。
build_index() {
	record_stream "$1" | awk -v mode=index "$PARSE_AWK"
}

# 列出格式問題，一行一件。
check_records() {
	record_stream "$1" | awk -v mode=check "$PARSE_AWK"
}

# 重建的索引和現有 INDEX.md 是否相同（沒有 INDEX.md 時視同空檔）。
index_current() {
	if [ -f "$1/INDEX.md" ]; then
		build_index "$1" | cmp -s - "$1/INDEX.md"
	else
		[ -z "$(build_index "$1")" ]
	fi
}

# 寫入重建的索引（先寫暫存檔再換上）。
write_index() {
	check_sources "$1" || return 1
	build_index "$1" >"$1/.INDEX.md.tmp" || { rm -f -- "$1/.INDEX.md.tmp"; return 1; }
	mv -- "$1/.INDEX.md.tmp" "$1/INDEX.md"
}

# 行數（最後一行沒有換行也算）。
line_count() {
	awk 'END { print NR }' "$1"
}
