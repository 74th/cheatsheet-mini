# docker sandbox (sbx)

## codex/claude codeをプロジェクトルート以外で起動する

codexは`--cd`というオプションがあるので手軽。

```bash
HERDR_AGENT=codex sbx run codex -- --cd ./20260822-agent-gateway/
```

claudeは`sbx exec`を代用し、`-w`で作業ディレクトリを指定。

## コンテナ内でghが使えるようにする

```bash
gh auth token | sbx secret set github
```

## コンテナ内で環境変数を設定する

```bash
echo 'export MY_VARIABLE=my_value' >> /etc/sandbox-persistent.sh
```
