# Claude Skills ガイドライン

このディレクトリには、Claudeのスキルを構築するためのガイドライン、テンプレート、チェックリストが含まれています。

## 📄 ファイル構成

```
docs/skills/
├── README.md                                          # このファイル
├── The-Complete-Guide-to-Building-Skill-for-Claude.pdf  # 完全ガイド (PDF)
├── checklist.md                                       # 実用的なチェックリスト
└── templates/                                         # スキルテンプレート
    └── skill-template/                                # 基本テンプレート
        └── SKILL.md
```

## 🚀 クイックスタート

### 1. ガイドを読む

まず完全ガイド (PDF) を読んで、スキルの基本概念を理解してください:
- スキルとは何か
- どのように機能するか
- ベストプラクティス

### 2. チェックリストを確認

[checklist.md](./checklist.md) を使って、スキル作成の各ステップを確認してください。

### 3. テンプレートを使用

[templates/](./templates/) から適切なテンプレートをコピーして、スキル作成を開始してください。

## 📋 スキル作成の基本ステップ

### Step 1: ユースケースを定義

スキルで解決したい具体的な問題を2-3個定義します:
- 誰がこのスキルを使うか？
- どのような状況で使うか？
- 何を達成するか？

### Step 2: フォルダ構造を作成

```bash
your-skill-name/
├── SKILL.md          # 必須: スキルの定義と指示
├── scripts/          # オプション: 実行可能なスクリプト
├── references/       # オプション: 参照ドキュメント
└── assets/           # オプション: テンプレート、アイコンなど
```

### Step 3: SKILL.md を作成

```markdown
---
name: your-skill-name
description: スキルの説明。いつ使うべきか明記する。
---

# Your Skill Name

## 指示

### Step 1: [最初のステップ]
...

### Step 2: [次のステップ]
...

## 使用例

例1: [一般的なシナリオ]
...

## トラブルシューティング

エラー: [よくあるエラー]
解決方法: [解決手順]
...
```

### Step 4: テストと反復

1. トリガーテスト: スキルが適切なタイミングで起動するか
2. 機能テスト: スキルが正しく動作するか
3. パフォーマンステスト: スキルありとなしで比較

## 🎯 スキルの種類

### Category 1: ドキュメント・アセット作成
- 一貫性のある高品質なアウトプット
- スタイルガイド、テンプレートを埋め込む
- 外部ツール不要

### Category 2: ワークフロー自動化
- 複数ステップのプロセス
- 検証ゲート、反復改善を含む
- テンプレートと組み込みレビュー

### Category 3: MCP連携
- MCP サーバーとの連携
- 複数のMCP呼び出しを順次実行
- ドメイン専門知識を組み込む

## 📐 技術要件

### 必須要件

1. **ファイル名**: `SKILL.md` (大文字小文字厳密)
2. **フォルダ名**: kebab-case (例: `notion-project-setup`)
3. **YAML フロントマター**:
   - `name`: kebab-case
   - `description`: 1024文字以内、XMLタグ禁止

### 制約事項

- ❌ `README.md` をスキルフォルダ内に含めない
- ❌ `claude` または `anthropic` を名前に使わない
- ❌ XMLタグ (`< >`) を使わない

## 🔍 よくある問題

### スキルがトリガーされない
→ `description` フィールドを見直す。具体的なトリガーフレーズを含める。

### スキルがトリガーされすぎる
→ ネガティブトリガーを追加。スコープをより具体的にする。

### 指示が守られない
→ 指示を簡潔にする。重要な部分は上部に配置。箇条書きを使う。

### MCP接続に失敗
→ MCPサーバーが接続されているか確認。ツール名が正しいか確認。

## 📚 追加リソース

- [Anthropic Skills Documentation](https://docs.anthropic.com/claude/docs/skills)
- [Agent Skills Specification](https://agentskills.ai/)
- [skill-creator skill](https://github.com/anthropics/skills/tree/main/skill-creator)

## 💡 ヒント

1. **小さく始める**: 1つの具体的なタスクから始めて、徐々に拡張する
2. **skill-creator を使う**: Claude.ai で利用可能な skill-creator スキルを使って生成・レビュー
3. **既存スキルを参考にする**: [anthropics/skills](https://github.com/anthropics/skills) にある公式スキルを参考にする
4. **反復改善**: フィードバックに基づいて継続的に改善する
