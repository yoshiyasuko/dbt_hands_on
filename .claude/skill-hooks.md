# Skill Hooks

このファイルは [git-workflow プラグイン](https://github.com/yoshiyasuko/claude-code-git-workflow-plugins) のライフサイクルフック設定です。`/commit` や `/create-pr` などのコマンド実行時に、各フックポイントで指定したスキルが自動的に呼び出されます。

## commit

| フック | スキル | 説明 |
|-------|-------|------|
| pre-commit | update-docs | コミット前にドキュメント更新要否を確認 |
