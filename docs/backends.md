# バックエンドと辞書の自動検出

## バックエンド

`cmigemo_cmd` 未指定時は `cmigemo` → `rustmigemo` の順に検出し、最初に見つかったものを使用します。明示する場合は `cmigemo_cmd = "rustmigemo"` のように指定します。

どちらのバックエンドも `<backend> -q -d <dict>` の常駐プロセスとして起動され、同じ引数・PCRE 形式出力で動作します。

## 辞書の探索先

辞書はバックエンドに応じて自動検出します。

| バックエンド | 既定の辞書探索先 |
|---|---|
| cmigemo | バイナリの install prefix 直下（`<prefix>/share/{migemo,cmigemo}/utf-8/migemo-dict`。symlink 解決済みのため Nix / home-manager / Homebrew の profile 経由でも到達）→ `/usr/share/cmigemo/utf-8/migemo-dict` 等のプラットフォーム標準パス |
| rustmigemo | `~/.local/share/migemo/migemo-compact-dict` |

`dict_path` を指定した場合は自動検出せずそのパスを使います。

## rustmigemo の注意点

- rustmigemo 辞書は [oguna/yet-another-migemo-dict](https://github.com/oguna/yet-another-migemo-dict) の `migemo-compact-dict` を上記パスへ配置してください
- **テキスト形式の `migemo-dict` は rustmigemo が読めず panic する**ため探索対象外です（バイナリの compact-dict 形式専用）
- 辞書によって語彙カバレッジが異なります。複合語（「日本語」「異世界」等）の見出しが辞書に無いとカナのみのパターンになり漢字テキストにマッチしません。本家 cmigemo 同梱の SKK 系辞書は複合語が充実しています

## 選定の目安

| 観点 | cmigemo | rustmigemo |
|---|---|---|
| 配布 | パッケージマネージャ（apt / nixpkgs 等）。GitHub releases 無し | GitHub releases あり（mise 等のバージョン管理ツールに乗る） |
| 辞書 | SKK 系テキスト辞書同梱（複合語が充実） | compact-dict を別途配置 |
| 速度 | どちらも常駐プロセスで ~1ms/クエリ（体感差なし） | 同左 |
