# AGENTS.md - canopy-chronicle

本專案提供一個跨 AI 的 Skill，把專案的歷史記成查得回來的紀錄：做過什麼、為什麼這樣決定、踩過什麼坑。

## 維護原則

- 規則只寫在 `skills/canopy-chronicle/`，README 只說明用途、安裝與限制。
- Skill 必須能單獨安裝，不依賴其他專案、工具與本機路徑。可以用反引號點名 `canopy-context` 作為選用搭配，但沒有它也要照常運作，不安裝它、不替它寫檔。
- 外掛是正式的安裝方式：這個 repo 本身就是一個外掛，也自帶市集檔。Claude Code 用 `.claude-plugin/`，Codex 用 `.codex-plugin/` 與 `.agents/plugins/marketplace.json`。改版本號時，三處（兩份 `plugin.json` 與 `.claude-plugin/marketplace.json`）要一起改。
- 外掛提供的 Skill 只有 `skills/canopy-chronicle/`，Skill 用到的參考文件與腳本都放在裡面。
- 進 repo 的檔案要能公開發佈：不放個人路徑、機器名、私有網址，也不放真實的紀錄內容。
- 腳本只用 POSIX sh（`#!/bin/sh`）與 POSIX 工具，目前涵蓋 macOS 與 Linux，不涵蓋 Windows。不用 bash 專屬語法，也不用 BSD 與 GNU 行為不同的寫法（`date -d`／`date -v`、`stat`、`sed -i`、`readlink -f`）。不帶 `--apply` 時不改任何檔案；刪除一律是移到刪除的去處，不用 `rm` 刪紀錄。
- 格式的唯一來源是 `skills/canopy-chronicle/references/format.md`。改格式時，它、`scripts/` 與 `tests/run.sh` 要一起改。
- `SKILL.md` 正文控制在 100 行內，細節放 `references/`。`description` 是唯一常駐內容，要維持簡短。
- 不加背景服務、資料庫或排程；要加 Hook、MCP 或其他外掛元件前，先有實際使用的問題依據，並和使用者確認。

## 驗證

改動腳本或格式後跑 `sh tests/run.sh`；有 dash 時再跑 `TEST_SH=dash sh tests/run.sh`，抓出只在 bash 能動的寫法。測試只用 `mktemp -d` 的暫存資料夾，不碰真的紀錄。

改動 Skill 或外掛設定後跑 `claude plugin validate . --strict`，並用暫存家目錄（`HOME` 指向暫存資料夾，Codex 另加 `CODEX_HOME`）各跑一次市集加入與外掛安裝，不要動真的設定。

使用者的 `~/.canopy-chronicle/` 是個人資料，不進 repo。
