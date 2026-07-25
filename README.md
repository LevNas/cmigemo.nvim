# cmigemo.nvim

ローマ字入力で日本語テキストを検索できる Neovim プラグイン。`"nihongo"` と入力するだけで `にほんご`、`ニホンゴ`、`日本語` すべてにマッチします。

- **migemo 変換 API** — ローマ字を日本語対応の正規表現（PCRE / Vim magic）へ変換。ripgrep・Vim 検索・各種プラグインから利用可能
- **flash.nvim 連携ジャンプ** — ローマ字入力で日本語へラベルジャンプ。ラベルと入力が衝突しない先読み割当、複合語への継続入力、MeCab があれば読みベースの高精度照合（読みモード）。オペレータからのリモート操作・treesitter 検索も migemo 入力に対応
- **snacks.nvim picker 連携** — migemo grep
- **文節ジャンプ** — BudouX による文節境界へのジャンプ

## 必要なもの

- Neovim 0.10+
- バックエンド: [cmigemo](https://github.com/koron/cmigemo) または [rustmigemo](https://github.com/oguna/rustmigemo)（PATH にあれば自動検出。辞書の探索先は [docs/backends.md](docs/backends.md)）
- 任意: [MeCab](https://taku910.github.io/mecab/)（読みモードが有効化）、[budoux.lua](https://github.com/atusy/budoux.lua)（文節ジャンプ）

## インストール

lazy.nvim:

```lua
{
  "LevNas/cmigemo.nvim",
  opts = {},
}
```

## 使用例

作者が日常使いしている2つの連携です。そのまま使える完全な設定は [`examples/`](examples/) にあります。

### flash.nvim — ローマ字で日本語へジャンプ

`s` を押してローマ字を打つと日本語のマッチが絞り込まれ、ラベルキーでジャンプします。オペレータ待ちの `r`（リモート操作）や `R`（treesitter 検索）も migemo 入力で使えます。完全版（flash 標準の `s` / `S` / `r` / `R` / `<c-s>` 配置 + 文節ジャンプ `gb`、低スペック端末向けの軽量化設定込み）は [examples/flash.lua](examples/flash.lua)。

```lua
{
  "folke/flash.nvim",
  dependencies = { "LevNas/cmigemo.nvim" },
  keys = {
    { "s", function() require("cmigemo.ext.flash").jump() end,
      mode = { "n", "x", "o" }, desc = "Flash: Migemo Jump" },
    { "r", function() require("cmigemo.ext.flash").remote() end,
      mode = "o", desc = "Flash: Migemo Remote" },
  },
}
```

### snacks.nvim picker — migemo grep

grep の入力をローマ字のまま日本語にヒットさせます（完全版: [examples/snacks-picker.lua](examples/snacks-picker.lua)）。

```lua
-- snacks.nvim opts の picker.sources.grep.finder を差し替え
finder = function(opts, ctx)
  return require("cmigemo.ext.snacks").grep(opts, ctx)
end
```

## ドキュメント

- [docs/backends.md](docs/backends.md) — バックエンドと辞書の自動検出
- [docs/flash.md](docs/flash.md) — flash ジャンプの挙動（先読みラベル・compound 分節・読みモード・リモート操作 / treesitter 検索・文節ジャンプ）
- [docs/api.md](docs/api.md) — セットアップ・API・アーキテクチャ・ヘルスチェック

## 謝辞

- [cmigemo](https://github.com/koron/cmigemo) by MURAOKA Taro (KoRoN) — ローマ字から日本語パターンへの変換を支える C/Migemo エンジン
- [rustmigemo](https://github.com/oguna/rustmigemo) / [yet-another-migemo-dict](https://github.com/oguna/yet-another-migemo-dict) by oguna — Rust 実装の migemo バックエンドと対応辞書
- [MeCab](https://taku910.github.io/mecab/) by Taku Kudo — 読みモードを支える形態素解析器
- [flash.nvim](https://github.com/folke/flash.nvim) / [snacks.nvim](https://github.com/folke/snacks.nvim) by folke — 連携先のジャンプ / ピッカープラグイン
- [budoux.lua](https://github.com/atusy/budoux.lua) by atusy — Google の [BudouX](https://github.com/google/budoux) の Lua 移植版。文節分割に使用

## ライセンス

MIT
