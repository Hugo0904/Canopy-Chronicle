#!/bin/sh
# status.sh：唯讀檢查紀錄。用法見 ../references/format.md 的「腳本」一節。
#   status.sh [專案代號]          檢查一個或全部專案；有問題時結束碼 1
#   status.sh --brief 專案代號    印出開場摘要

. "$(dirname -- "$0")/lib.sh"

usage() {
	cat <<'EOF'
用法：status.sh [專案代號]
      status.sh --brief 專案代號
EOF
}

BRIEF=0
PROJ=
HAVE_PROJ=0
for arg in "$@"; do
	case $arg in
	--brief) BRIEF=1 ;;
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

if [ "$BRIEF" = 1 ]; then
	[ "$HAVE_PROJ" = 1 ] || die "--brief 要指定專案代號"
	use_project "$PROJ"
	printf '# %s 開場摘要\n\n## PINNED.md\n\n' "$PROJ"
	if [ -f "$PDIR/PINNED.md" ]; then
		cat -- "$PDIR/PINNED.md"
	else
		printf '（沒有 PINNED.md）\n'
	fi
	printf '\n## 索引最後 10 筆\n\n'
	if [ -s "$PDIR/INDEX.md" ]; then
		tail -n 10 "$PDIR/INDEX.md"
	else
		printf '（還沒有紀錄）\n'
	fi
	printf '\n## 怎麼查\n\n'
	printf -- '- 搜索引：grep -i "關鍵字" "%s/INDEX.md"\n' "$PDIR"
	printf -- '- 讀一筆：打開索引最後一欄的檔案，找「## 編號」那一行\n'
	printf -- '- 封存的月份：gzip -dc "%s/archive/YYYY-MM.md.gz"\n' "$PDIR"
	exit 0
fi

load_config
PROBLEMS=$CONFIG_BAD

# 檢查一個專案，印出摘要與問題。
check_project() {
	name=$1
	dir=$ROOT/$name
	n=0

	say() {
		printf '  - %s\n' "$*"
		n=$((n + 1))
	}

	total=0
	archived=0
	bytes=0
	for rel in $(record_files "$dir"); do
		c=$(count_entries "$dir/$rel" 2>/dev/null)
		c=${c:-0}
		total=$((total + c))
		case $rel in
		archive/*) archived=$((archived + c)) ;;
		*) bytes=$((bytes + $(wc -c <"$dir/$rel"))) ;;
		esac
	done
	kb=$(((bytes + 1023) / 1024))
	pinned=0
	[ -f "$dir/PINNED.md" ] && pinned=$(line_count "$dir/PINNED.md")

	printf '%s：%s 筆（封存 %s 筆），未封存 %s KB／上限 %s KB，PINNED.md %s／%s 行\n' \
		"$name" "$total" "$archived" "$kb" "$PROJECT_MAX_KB" "$pinned" "$PINNED_MAX_LINES"

	case $name in
	*[!a-z0-9-]*) say "專案代號「$name」只能用小寫英數與連字號" ;;
	esac
	[ -f "$dir/PROJECT.md" ] || say "缺 PROJECT.md"
	[ -f "$dir/PINNED.md" ] || say "缺 PINNED.md"
	if [ "$pinned" -gt "$PINNED_MAX_LINES" ]; then
		say "PINNED.md 有 $pinned 行，超過上限 $PINNED_MAX_LINES 行"
	fi
	if [ "$bytes" -gt $((PROJECT_MAX_KB * 1024)) ]; then
		say "未封存的紀錄 $kb KB，超過上限 $PROJECT_MAX_KB KB，該維護了（maintain.sh）"
	fi

	if ! check_sources "$dir" 2>/dev/null; then
		check_sources "$dir" 2>&1 | while IFS= read -r line; do printf '  - %s\n' "$line"; done
		n=$((n + 1))
	else
		lines=0
		[ -f "$dir/INDEX.md" ] && lines=$(line_count "$dir/INDEX.md")
		if [ "$lines" -ne "$total" ]; then
			say "索引 $lines 行，紀錄 $total 筆，對不上（maintain.sh --apply 可重建）"
		elif ! index_current "$dir"; then
			say "索引內容和紀錄對不上（maintain.sh --apply 可重建）"
		fi
		probs=$(check_records "$dir")
		if [ -n "$probs" ]; then
			printf '%s\n' "$probs" | while IFS= read -r line; do printf '  - %s\n' "$line"; done
			n=$((n + $(printf '%s\n' "$probs" | awk 'END { print NR }')))
		fi
	fi

	PROBLEMS=$((PROBLEMS + n))
}

if [ "$HAVE_PROJ" = 1 ]; then
	use_project "$PROJ"
	check_project "$PROJ"
else
	found=0
	tmp_list=$(list_projects)
	if [ -n "$tmp_list" ]; then
		# 逐行讀，專案代號含空白也不會斷開。
		while IFS= read -r p; do
			found=1
			check_project "$p"
		done <<EOF
$tmp_list
EOF
	fi
	[ "$found" = 1 ] || printf '根目錄裡還沒有專案：%s\n' "$ROOT"
fi

if [ "$PROBLEMS" -gt 0 ]; then
	printf '共 %s 個問題\n' "$PROBLEMS"
	exit 1
fi
printf '沒有問題\n'
exit 0
