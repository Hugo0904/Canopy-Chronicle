#!/bin/sh
# prune.sh：列出封存滿期限的檔案；帶 --apply 才移到刪除的去處（不直接刪除）。
#   prune.sh [--apply] [專案代號]
# 封存日期沒有另外記錄，用月份推算：一個月份最早在滿 KEEP_MONTHS 個月時封存，
# 所以「封存滿 ARCHIVE_KEEP_MONTHS 個月」視為月份距今滿 KEEP_MONTHS＋ARCHIVE_KEEP_MONTHS 個月。

. "$(dirname -- "$0")/lib.sh"

usage() {
	printf '用法：prune.sh [--apply] [專案代號]\n'
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
LIMIT=$((KEEP_MONTHS + ARCHIVE_KEEP_MONTHS))
FAILED=0
LISTED=0

# 刪除去處的檔名：同名已存在時加序號，不覆蓋。
free_name() {
	d=$1
	b=$2
	[ -e "$d/$b" ] || { printf '%s' "$d/$b"; return; }
	i=2
	while [ -e "$d/${b%.md.gz}.$i.md.gz" ]; do
		i=$((i + 1))
	done
	printf '%s' "$d/${b%.md.gz}.$i.md.gz"
}

prune_project() {
	name=$1
	dir=$ROOT/$name
	moved=0
	any=0
	printf '%s：\n' "$name"
	for f in "$dir"/archive/[0-9][0-9][0-9][0-9]-[0-9][0-9].md.gz; do
		[ -f "$f" ] || continue
		b=${f##*/}
		age=$((TODAY_YM - $(month_ym "${b%.md.gz}")))
		[ "$age" -ge "$LIMIT" ] || continue
		any=1
		LISTED=$((LISTED + 1))
		c=$(count_entries "$f" 2>/dev/null)
		if [ "$APPLY" = 1 ]; then
			mkdir -p -- "$TRASH/$name" || { FAILED=1; continue; }
			dest=$(free_name "$TRASH/$name" "$b")
			if mv -- "$f" "$dest"; then
				printf '  已移走 archive/%s（%s 筆）→ %s\n' "$b" "${c:-?}" "$dest"
				moved=1
			else
				FAILED=1
			fi
		else
			printf '  可移走 archive/%s（%s 筆）\n' "$b" "${c:-?}"
		fi
	done
	[ "$any" = 1 ] || printf '  沒有封存滿 %s 個月的檔案\n' "$ARCHIVE_KEEP_MONTHS"
	if [ "$moved" = 1 ]; then
		if write_index "$dir"; then
			printf '  已重建索引，移走的紀錄不再出現在索引裡\n'
		else
			printf '  索引重建失敗，請跑 maintain.sh --apply\n'
			FAILED=1
		fi
	fi
}

if [ "$HAVE_PROJ" = 1 ]; then
	use_project "$PROJ"
	prune_project "$PROJ"
else
	list=$(list_projects)
	if [ -n "$list" ]; then
		while IFS= read -r p; do
			prune_project "$p"
		done <<EOF
$list
EOF
	else
		printf '根目錄裡還沒有專案：%s\n' "$ROOT"
	fi
fi

if [ "$APPLY" != 1 ] && [ "$LISTED" -gt 0 ]; then
	printf '這是預演，沒有移動任何檔案。加 --apply 會移到 %s/<專案代號>/，移走後索引就搜不到這些紀錄。\n' "$TRASH"
fi
exit "$FAILED"
