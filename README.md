# Portainer AI management

OpenCode から公式 Portainer MCP Server を使い、`http://umbrel:9000` 配下の
Docker 環境を自然言語で管理するためのローカル設備です。

## 構成

```text
OpenCode
  -> portainer-read  (read-only, automatic)
  -> portainer-write (write, approval required)
    -> local stdio: mcp-portainer 2.44.0
    -> HTTP API: http://umbrel:9000/api
      -> Portainer 2.44.x
        -> managed Docker environments
```

MCP をサーバー側で公開せず、AI クライアント上で stdio プロセスとして
起動します。MCP 用の待受ポート、共通 gate token、TLS 終端を追加する必要が
ないため、単一ユーザー環境でMCP側の攻撃面を最小化した構成です。

## 現在の状態

設備時にPortainerを `2.39.5` から `2.44.0` へ更新し、公式MCPも `2.44.0` に
揃えました。Umbrel App、専用DIND、Portainer API、2つのMCPはいずれも稼働確認済み
です。

## 導入

### 1. MCP用アクセストークンを作る

ブラウザは不要です。次のスクリプトがパスワードを非表示で受け取り、Portainer
APIで専用access tokenを作成してmacOS Keychainへ保存します。

```bash
./scripts/configure-portainer-key
```

トークン自体は標準出力やリポジトリへ書きません。可能ならPortainer上に専用の
非管理者ユーザーを作り、必要なenvironment/teamだけを許可してください。

### 2. Portainer を更新する

最初に dry-run で対象を確認します。

```bash
./scripts/upgrade-portainer
```

内容が正しければ、バックアップ付きで更新します。

```bash
./scripts/upgrade-portainer --apply
```

SSH の既定値は `umbrel@umbrel` です。異なる場合は `PORTAINER_SSH_TARGET` で
上書きできます。

umbrelOS更新後にDocker socketの権限が戻ることがあります。スクリプトが権限不足を
検出した場合は、表示される `sudo usermod -aG docker umbrel` を一度実行し、新しい
SSH接続で再実行します。

更新スクリプトはこのサーバーのUmbrel App構成専用で、次を行います。

- Umbrel管理APIを使ってAppを停止・開始し、proxyと専用DIND構成を維持
- 停止中の2.39データを `backups/` へ保存
- 元データを `data/portainer-mcp-2.44` へ複製し、2.44.0は複製側だけをmigration
- Portainer imageだけをdigest固定の2.44.0へ変更
- 管理stack用 `172.30.0.0/16` をouter nftablesの `DOCKER-USER` で許可
- ComposeとDocker entrypointをchecksum検証付きで一体管理
- version、APIキー、endpoint ID/statusを検証できるまで自動rollback
- 成功後も元の2.39データを未変更のまま保持

更新版Composeとentrypointは `umbrel-portainer-compose.yml` と
`umbrel-portainer-entrypoint.sh` として管理します。Umbrel App StoreのPortainer更新を
行うとこのカスタマイズが上書きされる可能性があるため、更新後は
`./scripts/portainer-doctor` でMCP互換性を再確認してください。Portainerが2.39.6へ
戻っていた場合は、`./scripts/upgrade-portainer` のdry-runを確認してから
`./scripts/upgrade-portainer --apply` を実行します。既存の2.44データは削除せず、
timestamp付きで退避してから最新2.39.6データを再移行します。

### 3. 接続を確認する

```bash
./scripts/portainer-doctor
opencode mcp list
```

このディレクトリでOpenCodeを再起動すると、2つのMCPが自動接続されます。

- `portainer-read`: `GET`/`HEAD`だけを公開し、通常の調査に使用
- `portainer-write`: 変更操作を公開するが、全tool callでOpenCodeの承認を要求

## AIに依頼できる操作例

- 「Portainerで見えるDocker環境と停止中コンテナを一覧にして」
- 「`nextcloud` の直近200行のログを調べて。変更はしないで」
- 「`nginx` コンテナを再起動し、起動後の状態とログを確認して」
- 「このstackの現在の設定を確認し、変更案だけ提示して」

破壊的操作では、AIに対象名と変更内容を復唱させてから実行させてください。

## T3 Code remote development

`stacks/t3-code/` contains the Dockerfile, parameterized Compose stack,
GitHub Actions image pipeline, integration test, and migration procedure for
the work and personal remote development environments. See
[`stacks/t3-code/README.md`](stacks/t3-code/README.md) before publishing or
deploying the image.

## セキュリティ方針

- PortainerのRBACをそのまま適用し、APIキーの権限以上の操作は不可
- 読み取り専用と書き込み用MCPを分離し、書き込み側は毎回承認
- APIキーはmacOS Keychainへ保存し、設定ファイル・ログ・Gitへ書かない
- `PORTAINER_NO_PROXY=1` で任意Docker/Kubernetes API proxyを無効化
- `BASE,DOCKER` と `observability` だけを公開
- container/stackの環境変数値は既定でマスク
- 外部公開するMCP HTTPサーバーは設置しない

`http://umbrel:9000` へのパスワード、APIキー、管理通信は暗号化されません。
この初期設定は信頼できる隔離LANに限って使用してください。LAN内にも信頼できない
端末がある場合は、Portainerの `9443/TLS` と検証可能な証明書を先に有効化し、
`PORTAINER_URL` をHTTPSへ変更してください。

## バージョン更新

Portainerを更新するときは、公式方針に従ってMCPのminor versionも合わせます。
変更箇所は次の3点です。

- `scripts/portainer-mcp` の `MCP_VERSION`
- `scripts/portainer-mcp` と `scripts/portainer-doctor` の互換性判定
- `scripts/upgrade-portainer` の `TARGET_VERSION`
