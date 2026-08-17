# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

dbtハンズオン用のリポジトリ。dbt-core 1.12(BigQueryアダプタ)を使用し、リポジトリルートがそのままdbtプロジェクト(`dbt_project.yml`)になっている。

## 環境

- dbtはリポジトリ直下の `venv/` にインストールされている(gitignore対象)。実行時は `source venv/bin/activate` するか、`venv/bin/dbt` を直接使う。
- 接続情報は `~/.dbt/profiles.yml` に定義されている(BigQuery)。認証情報を含むためリポジトリにはコミットしない。

## よく使うコマンド

```bash
source venv/bin/activate   # または venv/bin/dbt を直接実行

dbt debug                  # 接続確認
dbt run                    # 全モデルのビルド
dbt run --select <model名>  # 単一モデルのみ実行(例: dbt run --select my_first_dbt_model)
dbt test                   # 全テスト実行
dbt test --select <model名> # 単一モデルのテストのみ実行
dbt compile                # SQLのコンパイルのみ(実行なし)
dbt clean                  # target/ と dbt_packages/ を削除
```

## Gitワークフロー

- コミットは必ず `git-workflow:commit` スキルを利用すること。
- PR作成は必ず `git-workflow:create-pr` スキルを利用すること。
- コミット時は `.claude/skill-hooks.md` のpre-commitフックにより `update-docs` スキルが自動実行され、README.md / CLAUDE.md の更新要否がチェックされる。

## 構成

- `models/` — dbtモデル(SQL)。`dbt_project.yml` の設定により `models/example/` 配下はviewとしてマテリアライズされる。モデルのテスト・ドキュメントは同ディレクトリの `schema.yml` に定義する。
- `seeds/` — `dbt seed` でロードするCSV。
- `macros/` / `snapshots/` / `analyses/` / `tests/` — dbt標準のディレクトリ構成(現状は空)。
- `dbt_project.yml` の `profile:` 名は `~/.dbt/profiles.yml` のプロファイル名と一致している必要がある。
- `.agents/skills/` — プロジェクトスキルの本体(複数AIエージェント共用のuniversal形式)。`.claude/skills/` からsymlinkされており、Claude Codeはそちら経由で読み込む。利用可能なスキル: `update-docs`(README.md/CLAUDE.mdの更新判断・整合性検証)、`find-skills`(スキル検索)、`skill-creator`(スキル作成支援)。ルートの `skills-lock.json` はスキルのバージョン管理用ロックファイル。
