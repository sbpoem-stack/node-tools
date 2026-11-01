#!/usr/bin/env bash
# v2node 落地机: Reality "偷自己" 准备脚本
#   - 用 Cloudflare DNS 验证申请 <域名> 的真证书 (不需要 80 端口)
#   - 在 127.0.0.1:8443 跑一个 TLS1.3 + H2 的伪装站
#   - 生成 Reality 密钥对 + shortId, 打印面板该填的值
# 不会改动 v2node 本身, Reality 参数请填进 V2board 面板的节点设置。
#
# 用法:
#   export CF_Token="Cloudflare API Token (example.com 的 DNS 编辑权限)"
#   bash v2node-steal-self.sh m7q2.example.com
set -euo pipefail

DOMAIN="${1:?用法: bash $0 <节点域名, 如 m7q2.example.com>}"
WEBROOT="/var/www/${DOMAIN}"
CERT_DIR="/etc/ssl/${DOMAIN}"

[ "$(id -u)" = 0 ] || { echo "请用 root 运行"; exit 1; }
[ -n "${CF_Token:-}" ] || { echo "请先 export CF_Token=..."; exit 1; }

echo "==> 1/4 安装依赖"
if command -v apt-get >/dev/null; then
  apt-get update -y && apt-get install -y nginx curl socat cron openssl
elif command -v dnf >/dev/null; then
  dnf install -y nginx curl socat cronie openssl
else
  yum install -y nginx curl socat cronie openssl
fi

echo "==> 2/4 申请证书 (Let's Encrypt, DNS 验证)"
if [ ! -x ~/.acme.sh/acme.sh ]; then
  curl -fsSL https://get.acme.sh | sh -s email="admin@${DOMAIN#*.}"
fi
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
# 已有证书时 --issue 会返回非 0, 忽略即可
~/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" --keylength ec-256 || true
mkdir -p "$CERT_DIR"
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
  --key-file "$CERT_DIR/key.pem" \
  --fullchain-file "$CERT_DIR/fullchain.pem" \
  --reloadcmd "systemctl reload nginx || true"

echo "==> 3/4 伪装站 (仅监听 127.0.0.1:8443)"
mkdir -p "$WEBROOT"
if [ ! -f "$WEBROOT/index.html" ]; then
cat > "$WEBROOT/index.html" <<EOF
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Notes</title>
<style>body{font:16px/1.6 system-ui,sans-serif;max-width:680px;margin:60px auto;padding:0 16px;color:#222}</style>
</head><body><h1>Notes</h1><p>Personal notes and small projects. Nothing to see here yet.</p>
<p><small>&copy; $(date +%Y)</small></p></body></html>
EOF
fi
cat > "/etc/nginx/conf.d/${DOMAIN}.conf" <<EOF
server {
    listen 127.0.0.1:8443 ssl http2;
    server_name ${DOMAIN};
    ssl_certificate     ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    root ${WEBROOT};
    index index.html;
    add_header Strict-Transport-Security "max-age=63072000" always;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
# 发行版默认站点会占 80 端口, 去掉避免冲突 (伪装站只用 127.0.0.1:8443)
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx

echo "==> 4/4 生成 Reality 密钥"
TMPK="$(mktemp)"
openssl genpkey -algorithm X25519 -out "$TMPK"
PRIV="$(openssl pkey -in "$TMPK" -outform DER | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=\n')"
PUB="$(openssl pkey -in "$TMPK" -pubout -outform DER | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=\n')"
rm -f "$TMPK"
SID="$(openssl rand -hex 4)"

echo
echo "伪装站自检:"
curl -sS -o /dev/null -w "  HTTP %{http_code}, TLS 握手正常\n" \
  --resolve "${DOMAIN}:8443:127.0.0.1" "https://${DOMAIN}:8443/" || echo "  !! 伪装站访问失败, 请检查 nginx"

cat <<EOF

================ 面板节点设置 (VLESS) ================
  安全性 / tls        : Reality
  流控 flow           : xtls-rprx-vision
  Server Name (SNI)   : ${DOMAIN}
  Dest (目标地址)     : 127.0.0.1
  Dest 端口           : 8443
  Private Key (私钥)  : ${PRIV}
  Public Key (公钥)   : ${PUB}
  Short ID            : ${SID}
  Xver                : 0
  连接地址            : ${DOMAIN}
  连接端口 / 服务端口 : 保持原样不变
======================================================
保存后执行  v2node restart  (或 systemctl restart v2node) 让节点重新拉取配置。
EOF
