# Umbrel 管理画面の HTTPS

2026-11-02 に Umbrel 本体へ適用済み。Tailscale 接続中は
`https://umbrel` で管理画面を開けます。

## 接続経路

Tailscale MagicDNS が `umbrel` を `100.110.109.117` に解決します。
Tailscale Serve の TCP 443 を、ループバックで待ち受ける HAProxy へ転送します。
HAProxy は TLS ClientHello の SNI で接続先を選択し、暗号化された通信をそのまま転送します。

- `umbrel` / `umbrel.local`: Umbrel 標準 HTTPS (`127.0.0.1:443`)
- その他: Tailscale HTTPS (`100.110.109.117:9443`) → T3 Code (`127.0.0.1:3773`)

既存の `https://umbrel.tail7651b5.ts.net` は T3 Code のままです。
既存の 8443 番の設定も維持しています。9443 番も tailnet 内で T3 Code を提供します。
ルーター側のポート開放は追加していません。

## 証明書

Umbrel 標準のローカル CA と、`umbrel` を SAN に持つサーバー証明書を使います。
HAProxy は秘密鍵を保持しません。Umbrel によるサーバー証明書の更新がそのまま反映されます。

この Mac では既存のログインキーチェーンにある CA と Umbrel 本体の CA が一致し、
`security verify-cert` の SSL / `umbrel` 検証が成功しました。
他の端末でも使う場合は、その端末で Tailscale を接続し、Umbrel の CA を信頼させてください。
CA の公開証明書は `/home/umbrel/umbrel/lan-ingress/ca.pem` です。
秘密鍵 (`ca.key` / `server.key`) を端末へコピーする必要はありません。

## 配置・更新

通常の Umbrel Docker デーモン上で動作します。Portainer 管理下の専用 DIND には配置しません。
実配置は `/home/umbrel/https-router/`、コンテナ名は `umbrel-https-router` です。
Compose の `restart: unless-stopped` と Tailscale Serve の `--bg` で設定を永続化しています。
OS の再起動による動作確認は未実施です。

```sh
scp compose.yml haproxy.cfg umbrel@umbrel:/home/umbrel/https-router/
ssh -t umbrel@umbrel 'sudo docker compose -f /home/umbrel/https-router/compose.yml run --rm --no-deps router haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg'
ssh -t umbrel@umbrel 'sudo docker compose -f /home/umbrel/https-router/compose.yml up -d --force-recreate'
```

Tailscale の IP が変わった場合は `haproxy.cfg` のバックエンド IP を更新します。
T3 Code の内部ポートが変わった場合は Serve の 9443 番の転送先を更新します。

適用した Serve 設定:

```sh
sudo docker exec tailscale_web_1 tailscale serve --bg --https=9443 http://127.0.0.1:3773
sudo docker exec tailscale_web_1 tailscale serve --https=443 off
sudo docker exec tailscale_web_1 tailscale serve --bg --tcp=443 tcp://127.0.0.1:24443
```

## 確認結果

- HAProxy 設定検証: 成功
- `https://umbrel/`: Umbrel の CA を指定した証明書検証付き GET で HTTP 200
- `https://umbrel.tail7651b5.ts.net/`: 証明書検証付き GET で HTTP 200、タイトル `T3 Code (Beta)`
- 既存の `https://umbrel.tail7651b5.ts.net:8443/`: HTTP 307
- HAProxy から両バックエンドへの TLS パススルー: HTTP 200

macOS の curl はユーザー単位の CA 信頼を扱えない場合があるため、確認時は
SSH 経由で取得した公開 CA を `curl --cacert` に指定しています。
ブラウザーの実操作と、自宅 LAN 外の実回線からの確認は未実施です。
この Mac の実際の名前解決先である Tailscale IP 経由で確認しています。

## 元に戻す

変更前の Serve 設定は `/home/umbrel/https-router/serve-before.json` に保存しています。
以下を Umbrel 上で順に実行すると、443 番が元の T3 Code 用 HTTPS に戻ります。

```sh
sudo docker exec tailscale_web_1 tailscale serve --tcp=443 off
sudo docker exec tailscale_web_1 tailscale serve --bg --https=443 http://127.0.0.1:3773
sudo docker exec tailscale_web_1 tailscale serve --https=9443 off
sudo docker compose -f /home/umbrel/https-router/compose.yml down
```

## 参照

- [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve)
- [HAProxy の設定仕様](https://github.com/haproxy/haproxy/blob/master/doc/configuration.txt)
- [Umbrel LAN ingress](https://github.com/getumbrel/umbrel/blob/master/packages/umbreld/source/modules/lan-ingress/lan-ingress.ts)
