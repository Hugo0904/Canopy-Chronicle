# canopy-chronicle

把專案發生過的事記成一筆一筆、用關鍵字查得回來的紀錄：做過什麼、為什麼這樣決定、踩過什麼坑、說好先不做什麼。對話會被壓縮、會換新的，紀錄不會。Claude Code 和 Codex 共用同一個 Skill 和同一份本機紀錄。

它不管下一步和待辦，也不是進度表；那些交給交接筆記或專案文件。

## 安裝

Claude Code（2.1.292 以上）：

```bash
claude plugin install canopy-chronicle --marketplace Hugo0904/Canopy-Chronicle
```

2.1.275 到 2.1.291 的版本沒有這個終端機指令，改在對話裡打 `/plugin install canopy-chronicle --marketplace Hugo0904/Canopy-Chronicle`。

Codex：

```bash
codex plugin marketplace add Hugo0904/Canopy-Chronicle
codex plugin add canopy-chronicle@canopy-chronicle
```

兩行分開執行最穩。裝好後重開對話。Claude Code 裡這個 Skill 的完整名稱是 `canopy-chronicle:canopy-chronicle`。

### 開放紀錄資料夾的寫入權限

紀錄放在工作區外，沒有開放權限時，每次寫入都可能被擋下或要求確認。外掛機制不會替你做這一步，兩個宿主各設一次。

先建立紀錄資料夾：

```bash
mkdir -p ~/.canopy-chronicle
```

Claude Code 的 `~/.claude/settings.json` 加入：

```json
{
  "permissions": {
    "additionalDirectories": ["~/.canopy-chronicle"],
    "allow": [
      "Read(~/.canopy-chronicle/**)",
      "Edit(~/.canopy-chronicle/**)"
    ]
  }
}
```

Codex 的 `~/.codex/config.toml` 加入，並換成自己家目錄的絕對路徑（用 `echo ~` 查，填在 `<家目錄>`）：

```toml
[sandbox_workspace_write]
writable_roots = ["<家目錄>/.canopy-chronicle"]
```

## 怎麼用

- 第一次在某個專案用時，AI 會問要不要開始記；同意後它建立這個專案的資料夾。
- 階段驗收完、你做了決定、解決一個坑、說好先擱置時，AI 會寫一筆。你也可以直接說「記下來」。
- 要改既有功能、遇到錯誤，或你問「之前為什麼這樣做」「這個做過嗎」時，AI 會先查紀錄。
- 新對話開始在一個專案工作時，AI 先看「釘選」（仍有效的決定、擱置中的事）和最近 10 筆的索引。

紀錄放在家目錄的 `.canopy-chronicle/`，每個專案一個資料夾，不進 git，只留在這台電腦。格式見 [資料格式](skills/canopy-chronicle/references/format.md)，操作規則見 [SKILL.md](skills/canopy-chronicle/SKILL.md)。

## 三支腳本

在 `skills/canopy-chronicle/scripts/`，平常由 AI 執行。`maintain.sh` 和 `prune.sh` 不帶 `--apply` 只預演，AI 會先把預演結果給你看，你同意才執行。

| 腳本 | 做什麼 |
| --- | --- |
| `status.sh [專案代號]` | 只讀。檢查筆數、大小、索引有沒有對上、紀錄格式；有問題時結束碼 1。`--brief 專案代號` 印出開場摘要 |
| `maintain.sh [--apply] [專案代號]` | 重建索引；把舊月份壓縮封存到 `archive/`，封存後仍搜得到 |
| `prune.sh [--apply] [專案代號]` | 列出封存很久的檔案；帶 `--apply` 才移到 `~/.canopy-chronicle/.trash/`，不直接刪除。移走後索引就搜不到 |

不指定專案代號時處理全部專案。

## 容量設定

選用。在 `~/.canopy-chronicle/config` 一行寫一個 `名稱=數字`，`#` 開頭是註解，沒寫的用預設值：

```text
# 最近幾個月保留原文不封存（含當月）
KEEP_MONTHS=3
# 未封存的紀錄至少留這麼多筆，不足就不封存
KEEP_MIN_ENTRIES=50
# 封存滿幾個月才列入可刪清單（用月份推算：距今滿 KEEP_MONTHS＋這個值的月數）
ARCHIVE_KEEP_MONTHS=12
# 單一專案未封存的紀錄超過這個大小（KB）就提醒維護
PROJECT_MAX_KB=512
# 釘選的行數上限
PINNED_MAX_LINES=30
```

說明要寫在自己的 `#` 行，不能接在數字後面。腳本逐行讀這個檔，看不懂的行會略過並提醒，不會執行裡面的內容。

## 限制

- 寫紀錄靠規則，不是強制機制，可能漏記。漏了可以直接說「記下來」。
- 紀錄是當時的線索，不是現況；程式後來改了，舊紀錄不會自己更新。
- 紀錄沒有備份，也不同步到其他電腦。
- 腳本只支援 macOS 與 Linux。Windows 上 Skill 照樣能讀寫紀錄，但三支腳本不能跑，要自己維護索引與封存。
- 不排程、不自動刪除。

## 和 canopy-context 搭配（選用）

另外裝了 [canopy-context](https://github.com/Hugo0904/Canopy-Context)（交接筆記）時，兩者分工：交接筆記記「接下來做什麼」，這裡記「做過什麼、為什麼」。收工時決定與踩坑寫進這裡，交接筆記只留接手區和幾個關鍵字；接續時先讀交接，再用關鍵字查這裡。沒裝也照常運作，兩者互不依賴。

## 更新與移除

```bash
claude plugin update canopy-chronicle@canopy-chronicle
codex plugin marketplace upgrade canopy-chronicle
codex plugin add canopy-chronicle@canopy-chronicle
```

移除：`claude plugin uninstall canopy-chronicle@canopy-chronicle`、`codex plugin remove canopy-chronicle`。紀錄在 `~/.canopy-chronicle/`，移除外掛不會刪它。

## 開發這個技能的人才需要

一般使用者請用上面的外掛安裝。開發時想讓技能直接指向 checkout，可以用符號連結代替外掛安裝，兩者不要同時啟用：

```bash
ln -s "$PWD/skills/canopy-chronicle" "$HOME/.claude/skills/canopy-chronicle"
ln -s "$PWD/skills/canopy-chronicle" "$HOME/.agents/skills/canopy-chronicle"
```

只想試改動、不動既有設定時，Claude Code 可用 `claude --plugin-dir .` 載入。改腳本後跑測試（只用暫存資料夾，不碰真的紀錄）：

```bash
sh tests/run.sh
```

## 授權

[MIT](LICENSE)
