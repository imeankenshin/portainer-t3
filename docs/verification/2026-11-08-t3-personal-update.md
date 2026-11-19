# 個人用T3 Codeの更新

2026-11-08 JST、Umbrel / Portainer endpoint 1の個人用サーバーのみを更新した。

- 稼働版: 0.0.45 → 0.1.7（更新時点のnpm latest、ローカルデスクトップ版も0.1.7）。
- 使用イメージ: `t3-code-personal:0.1.7-20261108`。
- image ID: `sha256:a287f051137e`（短縮表記）。Portainer管理daemon内のローカルイメージで、レジストリへのpushは未実施。
- 現在の個人用コンテナの書き込みレイヤーをcommitし、そのイメージに `npm install --global --omit=dev t3@0.1.7` を適用。他の既存ツールを維持した。
- 既存Config、HostConfig、network aliasと8個のvolumeを引き継いで再作成。旧コンテナは停止状態で `t3-code-personal-t3-code-1-before-20261108` として保持。
- 既存のroot所有runtimeをnode所有へ修復し、nodeユーザーでの起動を確認。
- Portainer stack 4の `T3_CODE_IMAGE` も更新版ローカルイメージへ変更。Git source、参照先、自動更新設定は維持。
- 仕事用サーバーと両環境のDinDは更新・再起動していない。

## 検証

- 環境descriptor: serverVersion `0.1.7`、orchestrationProtocolVersion `2`。
- HTTP `/`: 200、コンテナrunning。
- T3 Connect: `Registered tunnel connection` 4件。
- 環境ID、Codex認証、既存SSH秘密鍵、Docker TLSクライアント証明書のSHA-256が前後一致。
- Docker TLS経由の `docker info` 成功。
- `state.sqlite` と `statev2.sqlite` の `PRAGMA quick_check`: 更新前後とも `ok`。
- 旧DBのproject/thread/message件数は6/5/12のまま。
- v2 DBのproject/thread/message件数は12/5/12、v2 message投影は12件のまま。
- クライアントUIでの接続操作とAIへの実リクエストは未実施。

## 復旧資料

ローカルの `backups/t3-personal-update-20261108/`（Git対象外、ディレクトリ0700）に、停止中userdataのtar（118,858,240 bytes）、旧コンテナ設定、旧stack設定、検証スクリプトを保存。認証情報を含むため公開しない。

更新前のコンテナ書き込みレイヤーは `t3-personal-before-update:20261108` として同じdaemonに保持。DB移行後の旧版起動では、先に新サーバーを停止し、保存したuserdataも復元する必要がある。

この更新ではリポジトリの配布イメージ既定値やビルドworkflowは変更していない。個人用stackの再作成はimage overrideを使用する。同じ設定を別daemonに移す場合は、このローカルイメージの移送または再ビルドが必要。

公式更新方針: https://github.com/pingdotgg/t3code/blob/main/docs/user/updating.md （Context7と公式ソースで確認）。
