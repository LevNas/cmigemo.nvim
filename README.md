# cmigemo.nvim

ローマ字入力で日本語テキストを検索できる Neovim プラグイン。バックエンドに [cmigemo](https://github.com/koron/cmigemo)（C実装）または [rustmigemo](https://github.com/oguna/rustmigemo)（Rust実装）を使用。

`"nihongo"` と入力するだけで `にほんご`、`ニホンゴ`、`日本語` すべてにマッチします。

主な機能:

- **migemo 変換 API** — ローマ字を日本語対応の正規表現（PCRE / Vim magic）へ変換。ripgrep・Vim 検索・各種プラグインから利用可能
- **flash.nvim 連携ジャンプ** — ローマ字入力で日本語へラベルジャンプ。ラベルと入力が衝突しない先読み割当、複合語への継続入力（compound 分節）、MeCab があれば読みベースの高精度照合（読みモード）
- **snacks.nvim picker 連携** — migemo grep
- **文節ジャンプ** — BudouX による文節境界へのジャンプ

## 必要なもの

- Neovim 0.10+
- 次のいずれかのバックエンドが PATH に通っていること（インストール済みのものを自動検出します）
  - [cmigemo](https://github.com/koron/cmigemo) ＋ cmigemo 辞書（通常 cmigemo と一緒にインストールされます）
  - [rustmigemo](https://github.com/oguna/rustmigemo) ＋ `migemo-compact-dict`
- 任意: [MeCab](https://taku910.github.io/mecab/)（flash ジャンプの読みモードが有効化）、[budoux.lua](https://github.com/atusy/budoux.lua)（文節ジャンプ）

## バックエンド

`cmigemo_cmd` 未指定時は `cmigemo` → `rustmigemo` の順に検出し、最初に見つかったものを使用します。明示する場合は `cmigemo_cmd = "rustmigemo"` のように指定します。

辞書もバックエンドに応じて自動検出します。

| バックエンド | 既定の辞書探索先 |
|---|---|
| cmigemo | バイナリの install prefix 直下（`<prefix>/share/{migemo,cmigemo}/utf-8/migemo-dict`。symlink 解決済みのため Nix / home-manager / Homebrew の profile 経由でも到達）→ `/usr/share/cmigemo/utf-8/migemo-dict` 等のプラットフォーム標準パス |
| rustmigemo | `~/.local/share/migemo/migemo-compact-dict` |

rustmigemo 辞書は [oguna/yet-another-migemo-dict](https://github.com/oguna/yet-another-migemo-dict) の `migemo-compact-dict` を上記パスへ配置してください（テキスト形式の `migemo-dict` は rustmigemo が読めず panic するため探索対象外です）。

## 読みモード（MeCab、任意）

[MeCab](https://taku910.github.io/mecab/) が PATH にある（または `mecab_cmd` で指定した）環境では、flash ジャンプの照合が**読みモード**に切り替わります。可視テキストを MeCab で読みに変換し、入力ローマ字をかな変換して読みへ直接前方一致させるため、辞書に無い複合語（生産性向上・記録する等）も語境界を越えて確実にマッチします。照合は3層構成です：

1. 読み照合（形態素境界起点・形態素跨ぎ自由）
2. リテラル照合（ASCII 識別子など、常時併用）
3. migemo 照合（上2層が0件のときのみ。MeCab の誤読・別読みを回収）

MeCab が無い環境では従来どおり migemo のみで動作します（機能後退なし）。

## flash ジャンプの挙動

`require("cmigemo.ext.flash").jump()` は folke/flash.nvim の上に次の挙動を実装しています：

- **ラベルと入力の非衝突（先読み割当）**: ラベル候補の各文字について「クエリ+その文字」が可視テキストにまだマッチし得るかを先読みし、続きになり得る文字はラベルに使いません。**表示されたラベルは押せば必ずジャンプ・クエリの続きは必ず入力できる**ことが保証されます
- **1文字目からラベル表示**（`label.min_pattern_length = 1` 既定。opts で上書き可能）
- **ラベル位置はマッチ先頭の左隣セル**（`label.before = true` 既定）。マッチ文字列が隠れません。行頭マッチは列0へクランプされ1文字目に重畳します
- **複合語への継続入力（compound 分節）**: migemo 照合時、辞書に無い複合列（例: `seisanseikoujou` → 生産性向上）は「バッファに実在するマッチ」をオラクルに入力を自動分節して照合します。読みモードでは読みストリーム照合が同じ役割をより高精度に果たします

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

### `require("cmigemo").stop()`

常駐している cmigemo プロセスを停止します。

## アーキテクチャ

cmigemo.nvim はバックエンド（`cmigemo` または `rustmigemo`）を `<backend> -q -d <dict>` の常駐プロセスとして起動し、stdin/stdout で通信します（両バックエンドとも同じ引数・PCRE 形式出力に対応）。プロセスは最初の `query()` 呼び出し時に遅延起動され、`VimLeavePre` で自動停止します。読みモード有効時は `mecab` も同様に常駐プロセスとして起動し、ジャンプセッションごとに可視テキストの読みインデックスを構築します。応答タイムアウト時はパイプの要求/応答の対応ズレを防ぐためプロセスを再起動します。

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
    ├── flash.lua      -- flash.nvim 連携 (migemo/読みジャンプ、先読みラベル、compound 分節)
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
- [MeCab](https://taku910.github.io/mecab/) by Taku Kudo — 読みモードを支える形態素解析器
- [budoux.lua](https://github.com/atusy/budoux.lua) by atusy — Google の [BudouX](https://github.com/google/budoux) の Lua 移植版。文節分割に使用

## ライセンス

MIT
