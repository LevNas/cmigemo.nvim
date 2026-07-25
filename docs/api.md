# セットアップ・API・アーキテクチャ

## セットアップ

```lua
require("cmigemo").setup({
  cmigemo_cmd = nil,         -- バックエンドのパス（デフォルト: cmigemo→rustmigemo の順で自動検出）
  dict_path = nil,           -- 辞書パス（デフォルト: バックエンドに応じて自動検出）
  query_timeout = 200,       -- レスポンスタイムアウト（ms、デフォルト: 200）
  mecab_cmd = nil,           -- 読みモード用 mecab のパス（デフォルト: "mecab" を自動検出。無ければ読みモード無効）
})
```

セットアップは任意です。`setup()` を呼ばずに `query()` を使った場合、デフォルト設定が自動的に適用されます。

## API

### `require("cmigemo").query(word, opts?)`

ローマ字/ASCII の入力を migemo 正規表現パターンに変換します。

```lua
-- PCRE 形式（デフォルト）- ripgrep 等で使用
local pattern = require("cmigemo").query("nihongo")
-- => "(nihongo|にほんご|ニホンゴ|日本語|...)"

-- Vim magic 形式 - Vim 検索、Flash 等で使用
-- グループは非キャプチャ \%(...\)（Vim のキャプチャ9個制限 E872 を回避）
local pattern = require("cmigemo").query("nihongo", { rxop = "vim" })
-- => "\%(nihongo\|にほんご\|ニホンゴ\|日本語\|...\)"
```

**パラメータ:**
- `word` (string): クエリ文字列
- `opts.rxop` (`"pcre"` | `"vim"`): 正規表現の形式（デフォルト: `"pcre"`）

**戻り値:** `string|nil` - 成功時は正規表現パターン、失敗時は `nil`

### `require("cmigemo").is_available()`

バックエンドのバイナリと辞書が利用可能かチェックします。

**戻り値:** `boolean`

### `require("cmigemo").mecab_cmd()`

読みモードで使う mecab コマンドを返します（未解決なら `nil` = 読みモード無効）。

### `require("cmigemo").stop()`

常駐している cmigemo プロセスを停止します。

### 診断用

`resolved_cmd()` / `backend()` / `dict_path()` — 自動検出の結果を返します（`:checkhealth cmigemo` が使用）。

## アーキテクチャ

cmigemo.nvim はバックエンド（`cmigemo` または `rustmigemo`）を `<backend> -q -d <dict>` の常駐プロセスとして起動し、stdin/stdout で通信します（両バックエンドとも同じ引数・PCRE 形式出力に対応）。プロセスは最初の `query()` 呼び出し時に遅延起動され、`VimLeavePre` で自動停止します。

読みモード有効時は `mecab` も常駐プロセスとして起動し、ジャンプセッションごとに可視テキストの読みインデックスを構築します。

応答タイムアウト時は、遅延応答が次のクエリの結果として誤読される（要求/応答の対応ズレ）のを防ぐため、プロセスを再起動してロックステップへ戻します。

```
lua/cmigemo/
├── init.lua           -- コア API (setup, query, is_available, stop)
├── health.lua         -- :checkhealth cmigemo
├── core/
│   ├── process.lua    -- migemo サブプロセス管理 (stdin/stdout IPC)
│   ├── dict.lua       -- migemo 辞書の自動検出
│   ├── mecab.lua      -- mecab サブプロセス管理 (形態素と読みの取得)
│   ├── romaji.lua     -- ローマ字→カタカナ変換 (読みモードのクエリ変換)
│   └── reading.lua    -- 読みインデックス構築と前方一致照合
└── ext/
    ├── flash.lua      -- flash.nvim 連携 (migemo/読みジャンプ、remote/treesitter 検索、先読みラベル、compound 分節)
    ├── snacks.lua     -- snacks.nvim picker 連携 (grep migemo)
    └── bunsetsu.lua   -- BudouX による文節分割
examples/
├── flash.lua          -- flash.nvim の lazy.nvim 設定例
└── snacks-picker.lua  -- snacks.nvim picker の lazy.nvim 設定例
```

## ヘルスチェック

```vim
:checkhealth cmigemo
```

バックエンド・辞書・クエリ動作・mecab（読みモード）・budoux.lua（文節ジャンプ）の状態を確認できます。
