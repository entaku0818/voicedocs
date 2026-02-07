# Claude Skills クイックリファレンス

よく使う情報をすぐに参照できるようにまとめました。

## 📝 必須ファイル構造

```
your-skill-name/          # kebab-case で命名
└── SKILL.md              # 大文字小文字厳密
```

## 📋 最小限のSKILL.md

```markdown
---
name: your-skill-name
description: 何をするか。Use when ユーザーが「〜〜」と言った時。
---

# Your Skill Name

## 指示

### Step 1: 最初にすること
具体的な指示...

## 使用例

例1: ユーザーが「〜〜して」と言う
実行: ...
結果: ...
```

## 🎯 命名規則

| 項目 | 形式 | 例 | NG例 |
|------|------|-----|------|
| フォルダ名 | kebab-case | `notion-setup` | `Notion Setup`, `notion_setup` |
| SKILL.md | 正確な大文字小文字 | `SKILL.md` | `skill.md`, `Skill.md` |
| name フィールド | kebab-case | `notion-setup` | `Notion Setup`, `notionSetup` |

## ✅ description の書き方

### 良い例
```yaml
description: Notion ワークスペースのセットアップを自動化。Use when ユーザーが「Notionプロジェクト作成」「ワークスペース初期化」と言った時。
```

### 悪い例
```yaml
description: プロジェクトを手伝う。  # 曖昧すぎる
description: Notionを使う。          # トリガー条件がない
```

## 🔑 重要なルール

### ✅ やるべきこと
- フォルダ名は kebab-case
- description に「何をするか」と「いつ使うか」を含める
- 具体的なトリガーフレーズを含める
- 指示を簡潔明瞭に書く
- エラーハンドリングを含める

### ❌ やってはいけないこと
- スキルフォルダ内に README.md を含める
- スキル名に `claude` や `anthropic` を使う
- XMLタグ (`< >`) を使う
- description を曖昧にする
- 冗長な指示を書く

## 📦 オプションファイル構造

```
your-skill-name/
├── SKILL.md              # 必須
├── scripts/              # オプション: 実行スクリプト
│   ├── setup.py
│   └── validate.sh
├── references/           # オプション: 詳細ドキュメント
│   ├── api-guide.md
│   └── examples/
└── assets/               # オプション: テンプレート等
    └── template.md
```

## 🧪 テストのポイント

### 1. トリガーテスト (5分)
```
✅ 「Notionプロジェクト作成して」→ トリガーされる
✅ 「プロジェクトを初期化」→ トリガーされる
❌ 「天気を教えて」→ トリガーされない
```

### 2. 機能テスト (10分)
```
✅ 正しいアウトプットが生成される
✅ エラーが適切にハンドリングされる
✅ エッジケースが処理される
```

### 3. パフォーマンステスト (5分)
```
比較:
- スキルなし: 15回のやりとり、12,000トークン
- スキルあり: 2回のやりとり、6,000トークン
```

## 🔧 よくあるエラーと解決

### エラー: "Could not find SKILL.md"
```bash
# 確認
ls -la your-skill-name/
# SKILL.md が正確な名前か確認（大文字小文字）
```

### エラー: "Invalid frontmatter"
```yaml
# 間違い
name: my-skill
description: Does things

# 正しい
---
name: my-skill
description: Does things
---
```

### エラー: "Invalid skill name"
```yaml
# 間違い
name: My Cool Skill

# 正しい
name: my-cool-skill
```

## 📊 YAML フロントマター全オプション

```yaml
---
name: skill-name                    # 必須: kebab-case
description: 説明とトリガー条件      # 必須: 1024文字以内
license: MIT                        # オプション
compatibility: Claude Code only     # オプション
metadata:                           # オプション
  author: Your Name
  version: 1.0.0
  mcp-server: server-name
  category: productivity
  tags: [automation, project]
---
```

## 🚀 5分でスキルを作成

```bash
# 1. テンプレートをコピー
cp -r docs/skills/templates/skill-template my-new-skill

# 2. 編集
cd my-new-skill
# SKILL.md を編集:
# - name を変更
# - description を書く
# - 指示を書く

# 3. 圧縮
cd ..
zip -r my-new-skill.zip my-new-skill

# 4. アップロード
# Claude.ai > Settings > Capabilities > Skills > Upload
```

## 📚 すぐに使えるリンク

- [完全ガイド (PDF)](./The-Complete-Guide-to-Building-Skill-for-Claude.pdf)
- [チェックリスト](./checklist.md)
- [テンプレート](./templates/skill-template/SKILL.md)
- [公式スキル例](https://github.com/anthropics/skills)
- [Anthropic Docs](https://docs.anthropic.com/claude/docs/skills)

## 💡 プロからのヒント

1. **小さく始める**: 1つの具体的なタスクから始める
2. **skill-creator を使う**: Claude.ai で `/skill-creator` を使って生成
3. **既存スキルを参考に**: 公式リポジトリから学ぶ
4. **反復改善**: フィードバックを集めて改善し続ける
5. **トリガーに注意**: description が最も重要

## 🎓 学習パス

### 初心者 (30分)
1. 完全ガイド PDF の Introduction と Fundamentals を読む
2. テンプレートを使って簡単なスキルを作成
3. Claude.ai でテスト

### 中級者 (1時間)
1. Planning and Design を読む
2. 実際のユースケースでスキルを作成
3. チェックリストを使って品質確認

### 上級者 (2時間)
1. Patterns and Troubleshooting を読む
2. MCP連携スキルを作成
3. 公開用のドキュメントを整備

---

このリファレンスを手元に置いて、スキル作成を効率化しましょう。
