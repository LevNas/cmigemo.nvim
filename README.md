# cmigemo.nvim

ローマ字入力で日本語テキストを検索できる Neovim プラグイン。バックエンドに [cmigemo](https://github.com/koron/cmigemo)（C実装）を使用。

`"nihongo"` と入力するだけで `にほんご`、`ニホンゴ`、`日本語` すべてにマッチします。

## 必要なもの

- Neovim 0.10+
- [cmigemo](https://github.com/koron/cmigemo) がインストール済みで PATH に通っていること
- cmigemo 辞書（通常 cmigemo と一緒にインストールされます）

## インストール

### lazy.nvim

```lua
{
  "LevNas/cmigemo.nvim",
  opts = {},
}
```

## セットアップ

```lua
require("cmigemo").setup({
  cmigemo_cmd = "cmigemo",  -- cmigemo バイナリのパス（デフォルト: "cmigemo"）
  dict_path = nil,           -- 辞書パス（デフォルト: 自動検出）
  query_timeout = 200,       -- レスポンスタイムアウト（ms、デフォルト: 200）
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

-- Vim very magic 形式 - Vim 検索、Flash 等で使用
local pattern = require("cmigemo").query("kensaku", { rxop = "vim" })
-- => "\v(nihongo|にほんご|ニホンゴ|日本語|...)"
```

**パラメータ:**
- `word` (string): クエリ文字列
- `opts.rxop` (`"pcre"` | `"vim"`): 正規表現の形式（デフォルト: `"pcre"`）

**戻り値:** `string|nil` - 成功時は正規表現パターン、失敗時は `nil`

### `require("cmigemo").is_available()`

cmigemo バイナリと辞書が利用可能かチェックします。

**戻り値:** `boolean`

### `require("cmigemo").stop()`

常駐している cmigemo プロセスを停止します。

## アーキテクチャ

cmigemo.nvim は `cmigemo -q -d <dict>` を常駐プロセスとして起動し、stdin/stdout で通信します。プロセスは最初の `query()` 呼び出し時に遅延起動され、`VimLeavePre` で自動停止します。

```
lua/cmigemo/
├── init.lua           -- コア API (setup, query, is_available, stop)
├── health.lua         -- :checkhealth cmigemo
├── core/
│   ├── process.lua    -- サブプロセス管理 (stdin/stdout IPC)
│   └── dict.lua       -- 辞書の自動検出
└── ext/
    ├── flash.lua      -- flash.nvim 連携 (migemo ジャンプ、文節ジャンプ)
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

## 連携プラグインの設定例

lazy.nvim の設定サンプルは [`examples/`](examples/) ディレクトリにあります。

- [`examples/flash.lua`](examples/flash.lua) — flash.nvim 連携（migemo ジャンプ、文節ジャンプ）
- [`examples/snacks-picker.lua`](examples/snacks-picker.lua) — snacks.nvim picker 連携（migemo grep）

## 謝辞

- [cmigemo](https://github.com/koron/cmigemo) by MURAOKA Taro (KoRoN) — ローマ字から日本語パターンへの変換を支える C/Migemo エンジン
- [budoux.lua](https://github.com/atusy/budoux.lua) by atusy — Google の [BudouX](https://github.com/google/budoux) の Lua 移植版。文節分割に使用

## ライセンス

MIT
