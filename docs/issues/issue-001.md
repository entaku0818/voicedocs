# Issue #001: 基本録音機能の実装
**Priority**: High
**Assignee**: 
**Labels**: feature, recording, core

## 概要
アプリの基本録音機能を実装する。長時間録音対応、バックグラウンド録音、録音の追加・継続機能を含む。

## 要件
- [x] 録音開始/停止機能
- [x] 長時間録音対応（制限なし）
- [x] バックグラウンド録音対応
- [x] 録音品質設定（高音質/標準）
- [x] 録音ファイルの自動保存
- [x] 録音時間の表示

## 技術仕様
- AVAudioRecorder使用
- Core Data でメタデータ管理
- Background Audio モード対応

## 完了条件
- [x] 基本的な録音/停止ができる
- [x] バックグラウンドで録音継続できる
- [x] 録音データがCore Dataに保存される
- [x] 録音時間が正確に表示される

## 実装詳細

### 実装したファイル

- `AudioRecorder.swift`: 録音機能の改善（長時間録音、バックグラウンド録音、録音品質設定）
- `ContentView.swift`: UI改善（録音時間表示、品質設定画面）
- `Info.plist`: 必要な権限設定の追加
- `voicedocsTests.swift`: ユニットテストの追加

### 主要な改善点

1. **権限設定の追加**: マイクアクセスと音声認識の権限説明を追加
2. **バックグラウンド録音**: UIBackgroundModesでaudioモードを有効化
3. **長時間録音対応**: 時間制限を撤廃し、バックグラウンドタスクで継続録音
4. **録音品質設定**: 標準品質(22kHz)と高品質(44kHz)の選択可能
5. **UI改善**: 録音時間の詳細表示、視覚的フィードバックの向上
6. **テスト追加**: AudioRecorderの基本機能のユニットテスト
