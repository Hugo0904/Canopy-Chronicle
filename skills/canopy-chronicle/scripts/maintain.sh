#!/bin/sh
# maintain.sh：重建 INDEX.md，並把符合條件的舊月份封存到 archive/。
#   maintain.sh [--apply] [專案代號]
# 不帶 --apply 只預演，不改任何檔案。PROJECT.md、PINNED.md 永遠不改。

. "$(dirname -- "$0")/lib.sh"

usage() {
	printf '用法：maintain.sh [--apply] [專案代號]\n'
}

APPLY=0
PROJ=
HAVE_PROJ=0
for arg in "$@"; do
	case $arg in
	--apply) APPLY=1 ;;
	-h | --help) usage; exit 0 ;;
	-*) usage >&2; die "不認得的選項：$arg" ;;
	*)
		[ "$HAVE_PROJ" = 1 ] && die "一次只能指定一個專案代號"
		PROJ=$arg
		HAVE_PROJ=1
		;;
	esac
done

load_root
load_today
load_config
FAILED=0

# 列出要封存的月份（一行一個 YYYY-MM），並把理由印到標準錯誤。
# 條件：整個月份早於 KEEP_MONTHS 的範圍；從最舊的開始，封存後未封存的筆數仍不少於 KEEP_MIN_ENTRIES，遇到不符就停。
archive_plan() {
	dir=$1
	live=0
	for m in $(live_months "$dir"); do
		live=$((live + $(count_entries "$dir/$m.md")))
	done
	for m in $(live_months "$dir"); do
		age=$((TODAY_YM - $(month_ym "$m")))
		[ "$age" -ge "$KEEP_MONTHS" ] || break
		c=$(count_entries "$dir/$m.md")
		if [ $((live - c)) -lt "$KEEP_MIN_ENTRIES" ]; then
			warn "  $m 不封存：封存後未封存只剩 $((live - c)) 筆，少於 KEEP_MIN_ENTRIES=$KEEP_MIN_ENTRIES"
			break
		fi
		live=$((live - c))
		printf '%s %s\n' "$m" "$c"
	done
}

# 封存一個月份：壓縮到暫存檔、解壓比對無誤才換上並移除原檔。
archive_month() {
	dir=$1
	m=$2
	src=$dir/$m.md
	dst=$dir/archive/$m.md.gz
	tmp=$dir/archive/.$m.md.gz.tmp
	if [ -e "$dst" ]; then
		warn "  $m 沒有封存：archive/$m.md.gz 已經存在"
		return 1
	fi
	mkdir -p -- "$dir/archive" || return 1
	if ! gzip -n -c -- "$src" >"$tmp"; then
		rm -f -- "$tmp"
		return 1
	fi
	if gzip -dc -- "$tmp" | cmp -s - "$src"; then
		mv -- "$tmp" "$dst" && rm -f -- "$src"
	else
		rm -f -- "$tmp"
		warn "  $m 沒有封存：壓縮後比對不符"
		return 1
	fi
}

maintain_project() {
	name=$1
	dir=$ROOT/$name
	printf '%s：\n' "$name"
	if ! check_sources "$dir"; then
		printf '  有紀錄檔讀不了，這個專案先不動\n'
		FAILED=1
		return
	fi

	plan=$(archive_plan "$dir")
	if [ -n "$plan" ]; then
		while read -r m c; do
			if [ "$APPLY" = 1 ]; then
				if archive_month "$dir" "$m"; then
					printf '  已封存 %s（%s 筆）→ archive/%s.md.gz\n' "$m" "$c" "$m"
				else
					FAILED=1
				fi
			else
				printf '  會封存 %s（%s 筆）→ archive/%s.md.gz\n' "$m" "$c" "$m"
			fi
		done <<EOF
$plan
EOF
	else
		printf '  沒有要封存的月份\n'
	fi

	if [ "$APPLY" = 1 ]; then
		if index_current "$dir"; then
			printf '  索引已是最新\n'
		elif write_index "$dir"; then
			printf '  已重建索引（%s 行）\n' "$(line_count "$dir/INDEX.md")"
		else
			printf '  索引重建失敗，原本的 INDEX.md 沒動\n'
			FAILED=1
		fi
	elif [ -n "$plan" ]; then
		printf '  封存後會重建索引\n'
	elif index_current "$dir"; then
		printf '  索引已是最新\n'
	else
		printf '  索引會重建（重建後 %s 行）\n' "$(build_index "$dir" | awk 'END { print NR }')"
	fi
}

if [ "$HAVE_PROJ" = 1 ]; then
	use_project "$PROJ"
	maintain_project "$PROJ"
else
	list=$(list_projects)
	if [ -n "$list" ]; then
		while IFS= read -r p; do
			maintain_project "$p"
		done <<EOF
$list
EOF
	else
		printf '根目錄裡還沒有專案：%s\n' "$ROOT"
	fi
fi

[ "$APPLY" = 1 ] || printf '這是預演，沒有改動任何檔案；加 --apply 才會執行。\n'
exit "$FAILED"
