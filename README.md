# node-tools

Reality 节点运维小工具。

## sni-test.sh — 落地机 SNI 测速

在落地机上测试约 90 个候选 Reality SNI（全球 CDN 与大厂域名，已排除在国内被墙的域名），按 TLS 握手延迟排序，并检查 TLS 1.3 / HTTP2 / 证书。默认只显示可用的，加 `-a` 显示全部。

排除已被其他节点使用的 SNI：

```bash
EXCLUDE="d1.awsstatic.com m.media-amazon.com" bash <(curl -fsSL https://raw.githubusercontent.com/sbpoem-stack/node-tools/main/sni-test.sh)
```
不安装任何东西，只用系统自带的 curl。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sbpoem-stack/node-tools/main/sni-test.sh)
```

测试自己指定的域名：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sbpoem-stack/node-tools/main/sni-test.sh) a.example.com b.example.com
```

选结果里 ✓ 且握手最快的域名，面板中填：SNI = 该域名，Server Address 留空，Server Port = 443。

## v2node-steal-self.sh — Reality “偷自己”（可选）

在落地机上用 Cloudflare DNS 验证申请证书，在 `127.0.0.1:8443` 跑伪装站，并生成 Reality 密钥。需要安装 Nginx。

```bash
export CF_Token="你的 Cloudflare DNS 编辑 Token"
bash <(curl -fsSL https://raw.githubusercontent.com/sbpoem-stack/node-tools/main/v2node-steal-self.sh) node1.example.com
```

面板中：SNI = 节点域名，Dest = `127.0.0.1`，Dest 端口 = `8443`（Dest 与端口分开填）。
