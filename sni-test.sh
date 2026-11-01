#!/usr/bin/env bash
# 在【落地机】上运行: 测试一批候选 Reality SNI, 按 TLS 握手延迟排序
# 不安装任何东西, 只用系统自带的 curl
# 用法: bash sni-test.sh            (使用内置候选列表)
#       bash sni-test.sh a.com b.com (测试自己指定的域名)

CANDIDATES=(
  # --- AWS CloudFront 上的 Amazon/AWS 自家域名 (和 AWS 入口 IP 最搭) ---
  aws.amazon.com
  d1.awsstatic.com
  m.media-amazon.com
  images-na.ssl-images-amazon.com
  # --- 游戏 / 软件下载 CDN (大流量很正常) ---
  download-porter.hoyoverse.com
  fastcdn.hoyoverse.com
  # --- Apple 下载 CDN ---
  iosapps.itunes.apple.com
  swcdn.apple.com
  updates.cdn-apple.com
  # --- 其他大厂静态/下载 ---
  dl.google.com
  download.visualstudio.microsoft.com
  www.samsung.com
)
[ $# -gt 0 ] && CANDIDATES=("$@")

command -v curl >/dev/null || { echo "需要 curl"; exit 1; }

printf "%-40s %-8s %-6s %-6s %s\n" "SNI" "握手(s)" "TLS" "HTTP" "结论"
for d in "${CANDIDATES[@]}"; do
  out=$(curl -sS -o /dev/null --max-time 8 --tlsv1.3 --tls-max 1.3 --http2 \
        -w "%{time_appconnect} %{http_version} %{http_code} %{ssl_verify_result}" \
        "https://$d/" 2>/dev/null)
  if [ -z "$out" ]; then
    printf "%-40s %-8s %-6s %-6s %s\n" "$d" "-" "-" "-" "✗ 不支持 TLS1.3 或连不上"
    continue
  fi
  read -r t hv code verify <<<"$out"
  verdict="✓ 可用"
  [ "$hv" != "2" ] && verdict="✗ 不支持 H2"
  [ "$verify" != "0" ] && verdict="✗ 证书校验失败"
  if [ "$verdict" = "✓ 可用" ]; then
    awk "BEGIN{exit !($t > 0.08)}" && verdict="△ 可用但较慢(附近无 CDN 节点)"
  fi
  printf "%-40s %-8s %-6s %-6s %s\n" "$d" "$t" "1.3" "$hv" "$verdict"
done | sort -k2 -n
echo
echo "选 ✓ 且握手时间最短的 1~2 个, 填进面板: SNI=该域名, Dest=该域名, Dest端口=443"
