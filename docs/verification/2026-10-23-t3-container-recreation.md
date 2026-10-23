# T3 Code コンテナ削除・再作成の実機検証

実施日時: 2026-10-23 12:01 JST。対象: Umbrel / Portainer endpoint 1。

追記（同日13:26以降）: 当初のHTTP・トンネル確認ではデスクトップクライアントとの互換性を検出できなかった。0.1.2のデスクトップアプリから両環境に接続すると「Client not supported」となったため、サーバーを0.1.2へ更新した。更新後、ユーザーが両環境への接続成功を確認済み。現在の稼働状態は末尾の追記を参照。

## 結果

仕事用・個人用のT3 Codeコンテナを順番に停止・削除し、同じイメージと設定、既存volumeで再作成できた。停止操作開始からDocker healthcheckがhealthyになるまで、両方とも約7.3秒。T3 Connectのトンネルも自動復帰した。

個人用でコンテナ内に直接追加・更新していたソフトは引き継がれなかった。永続データの復元はスムーズだが、追加ソフトも維持するにはイメージに組み込む必要がある。

## 実施方法と範囲

- 対象は `t3-code-personal-t3-code-1` と `t3-code-work-t3-code-1`。
- PortainerのDocker API proxy経由で実施。既存のConfig、HostConfig、ネットワークaliasを保存し、同じ設定で再作成した。動的IPアドレスは再割り当て。
- 停止は45秒の猶予付き。削除は `v=false&force=false`。旧コンテナを実際に削除してから新規作成した。
- 同一の既存イメージを使用。pull、build、Gitの更新、Portainer stackの削除・再デプロイは実施していない。
- DinD、ネットワーク、他アプリのコンテナは維持。volumeの削除APIは呼んでいない。
- 削除前に各コンテナの書き込みレイヤーをDocker commitで復旧用イメージとして保存した。これはvolumeのバックアップを含まない。

参考: Docker公式の [Compose rm](https://docs.docker.com/reference/cli/docker/compose/rm/)、[Compose up](https://docs.docker.com/reference/cli/docker/compose/up/)。公式仕様はContext7で確認。今回の実操作はCompose CLIではなくDocker API。

## 所要時間

停止操作開始からの累積時間。API通信と約2秒間隔のhealthcheck状態確認を含み、厳密なHTTP停止時間ではない。

個人用:

- 停止完了: 0.449秒
- 削除完了: 0.631秒
- 新規作成完了: 0.702秒
- start API完了: 0.999秒
- healthy確認: 7.306秒
- 起動ログ: HTTP待受 12:01:10、T3 Connect recovery登録・最初のトンネル接続 12:01:11
- 旧ID: `506bacd7956c` → 新ID: `76b31e3204cd`

仕事用:

- 停止完了: 0.496秒
- 削除完了: 0.603秒
- 新規作成完了: 0.726秒
- start API完了: 1.064秒
- healthy確認: 7.344秒
- 起動ログ: HTTP待受 12:01:39、T3 Connect recovery登録・最初のトンネル接続 12:01:40
- 旧ID: `1c8e4745b22f` → 新ID: `22dcdf362bd6`

## 永続化と接続の確認

- Docker daemon上のvolume全26個について、名前・作成日時・Mountpoint等の取得メタデータが前後で完全一致。新規作成・削除なし。
- 各T3コンテナの8個のvolumeについて、名前・mount先・読み書き設定が前後で一致。
- image ID、hostname（personal / business）が一致。
- 環境ID、T3設定、キーバインド、T3署名鍵とConnect鍵、Codex認証、Git/GitHub/OpenCode認証・設定、SSHの既存ファイル、Docker TLS証明書をSHA-256で比較。一覧中の存在するファイルはすべて一致。ファイル内容やハッシュは本レポートには掲載していない。
- workspace直下の一覧と深さ3までのGitリポジトリ一覧が一致。workspace全ファイルの内容比較は未実施。
- SQLite `PRAGMA quick_check` は両環境とも `ok`。
- 個人用: プロジェクト6、スレッド5、メッセージ12、orchestration events 110を維持。
- 仕事用: プロジェクト3、スレッド12、メッセージ53、orchestration events 2616を維持。
- 起動時にpairing linkレコードは各1件増加。上記の履歴レコード件数は一致。
- HTTP `/` は両方200。Docker TLS経由の `docker info` 成功。DinDのdaemon IDと内部コンテナ件数は前後で一致（個人0、仕事4、実行中はいずれも0）。
- 個人用の `codex login status` は再作成後も `Logged in using ChatGPT`。仕事用は実施前から `Not logged in` で変化なし。
- T3 Connectの保存済み設定が一致。新コンテナの起動ログでmanaged tunnel recovery登録成功とQUICトンネル接続登録を各4接続確認。再リンクやログイン操作は不要だった。

## 再作成によって戻ったソフト

両環境のT3 Codeは `0.0.44` のまま。

個人用:

- Codex: `0.159.3` → イメージ収録版 `0.157.1`
- OpenCode: `1.18.34` → イメージ収録版 `1.18.33`
- Neovim: `/usr/bin/nvim` が存在 → 存在しない

仕事用はCodex `0.157.1`、OpenCode `1.18.33` のまま。

コンテナ書き込みレイヤーにあるシェル履歴やキャッシュ等も永続化対象ではない。再作成後の個人用は元の配布イメージの状態で稼働しており、上記ソフトの再インストールは行っていない。

## 復旧用イメージ

同じPortainer管理Docker daemon内に保存済み。レジストリにはpushしていない。

- `t3-recreate-backup-personal:20261023` — `sha256:67889a884f968f50839d4b64d0af7e843db254ef8426c4cd677aaca9904e857b`
- `t3-recreate-backup-work:20261023` — `sha256:38e2503f9a2219eecefbb770acb708b3bfd24d314035332c1b90ef64007cac76`

削除前の追加ソフト等が必要なら、同じdaemonでこの復旧用イメージと既存のvolume・コンテナ設定を使用して再作成できる。volumeに対する時点復元ではない。

## 未検証と改善案

- クライアントUIでの環境選択・会話再開、AIへの実リクエスト、実行中のエージェントやターミナルの継続は未検証。
- 新規imageのダウンロード、PortainerのGit stack再デプロイ、DinD自体の削除・復元を含む所要時間は未検証。
- 個人用で追加されたNeovimとCLI更新を維持したい場合は、Dockerfileと公開イメージに反映してから再デプロイする。
- ComposeのhealthcheckはTCP接続のみ。今回追加でHTTP、SQLite、認証ファイル、Docker TLS、Connectの接続ログを確認した。

## 追記: Client not supported の原因と復旧

デスクトップ版0.1.2に対し、再作成後の両サーバーは0.0.44 / orchestration protocol 1だった。0.1.2のクライアントはprotocol 2を要求するため、トンネルが接続していてもアプリ接続は拒否される。

実機の `/.well-known/t3/environment` を取得する `/tmp/t3-recreate-verification/compat.py` で、修正前は両環境とも `FAIL: Client not supported (server protocol 1, desktop 0.1.2 requires 2)`、修正後は両方 `PASS: orchestration protocol 2` を確認した。ユーザーも更新後に両環境への接続成功を確認した。

参考: T3 Code公式の [更新と互換性](https://github.com/pingdotgg/t3code/blob/v0.1.2/docs/user/updating.md)、[クライアントの互換性判定](https://github.com/pingdotgg/t3code/blob/v0.1.2/packages/client-runtime/src/connection/compatibility.ts)。

対応:

- 既存の配布イメージをベースに、`npm install --global --omit=dev t3@0.1.2` を実行したローカルイメージ `t3-code-connect:0.1.2-20261023` を作成。
- image ID: `sha256:2674def1972a4edc8f926fd1b40d3652421975dfd72ffb2fe880f6163cca4556`。Portainer管理daemon内に保存し、レジストリへのpushは未実施。
- 各サーバー停止中にuserdata全体をローカルの保護ディレクトリ `/tmp/t3-recreate-verification/` にtar保存（個人 `personal-userdata-before-012.tar`、仕事 `work-userdata-before-012.tar`）。このバックアップには認証情報が含まれるため公開しない。
- root所有だった `/var/lib/t3/runtime` をUID/GID 1000へ変更し、新版のruntime展開時のEACCESを解消。
- 既存volumeとコンテナ設定を引き継いで両環境を更新。Portainer stack 4・5の `T3_CODE_IMAGE` も上記ローカルイメージへ変更したため、同じstack設定での再作成は新版を使用する。
- Git-backed stackの参照先と自動更新設定は維持。リポジトリのDockerfile・ビルドworkflow・配布イメージの既定digestは未変更。将来、配布イメージへ戻す際もクライアントと互換性のある版を指定する必要がある。

更新後の確認:

- 両方のdescriptorがserverVersion `0.1.2` / orchestrationProtocolVersion `2`。healthy、HTTP 200、Connectトンネル登録成功。
- 新版が作成した `statev2.sqlite` のquick_checkは両環境とも `ok`。個人用の6プロジェクト・5スレッド・12メッセージ、仕事用の3プロジェクト・12スレッド・53メッセージを確認。v2投影にも各スレッド・メッセージが移行済み。
- 環境ID、認証・SSH鍵・Docker証明書の確認対象ファイルは更新前と一致。設定・キーバインドは新版起動時に変更された。
- 個人用CodexはChatGPTログインを維持。仕事用は更新前から未ログイン。
- 全26個のvolumeの取得メタデータが最初の削除前と一致。DinDのdaemon ID・内部コンテナ件数も維持。
- ユーザーがデスクトップ版0.1.2から個人用・仕事用の両方へ接続できたと確認。AIへの実リクエストはこの検証では未実施。

今後の再作成検証では、TCP・HTTP・トンネルに加え、接続元クライアントのバージョンとdescriptorのプロトコル互換性、アプリからの接続を合格条件に含める。
