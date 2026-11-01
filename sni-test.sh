#!/usr/bin/env bash
# 在【落地机】上运行: 测试一批候选 Reality SNI, 按 TLS 握手延迟排序
# 不安装任何东西, 只用系统自带的 curl
#
# 用法:
#   bash sni-test.sh                     测试内置候选列表 (只显示可用的)
#   bash sni-test.sh -a                  显示全部结果 (包括不可用的)
#   bash sni-test.sh a.com b.com         只测试指定域名
#   EXCLUDE="d1.awsstatic.com m.media-amazon.com" bash sni-test.sh
#                                        排除已被其他节点用掉的 SNI
#
# 注意: 候选里刻意不放在中国被墙的域名 (Google 大部分、YouTube、Twitch、Discord、
#       LINE、Facebook 等)。SNI 本身是明文, 用被墙域名做 SNI 会被直接按 SNI 阻断。

CANDIDATES=(
  # ---------- AWS / CloudFront 上的 Amazon 系 (和 AWS 入口 IP 最搭) ----------
  aws.amazon.com
  d1.awsstatic.com
  a0.awsstatic.com
  docs.aws.amazon.com
  console.aws.amazon.com
  signin.aws.amazon.com
  m.media-amazon.com
  f.media-amazon.com
  images-na.ssl-images-amazon.com
  images-fe.ssl-images-amazon.com
  www.amazon.com
  www.amazon.co.jp
  www.amazon.co.uk
  www.amazon.de
  www.primevideo.com
  www.imdb.com
  www.audible.com
  # ---------- 游戏 / 下载 CDN ----------
  fastcdn.hoyoverse.com
  download-porter.hoyoverse.com
  act.hoyoverse.com
  www.hoyolab.com
  cdn.cloudflare.steamstatic.com
  shared.akamai.steamstatic.com
  steamcdn-a.akamaihd.net
  download.epicgames.com
  www.unrealengine.com
  www.ea.com
  www.ubisoft.com
  www.playstation.com
  gs2.ww.prod.dl.playstation.net
  www.nintendo.com
  www.xbox.com
  assets1.xboxlive.com
  # ---------- 微软 ----------
  www.microsoft.com
  learn.microsoft.com
  officecdn.microsoft.com
  dl.delivery.mp.microsoft.com
  update.code.visualstudio.com
  # ---------- Apple ----------
  www.apple.com
  developer.apple.com
  support.apple.com
  # ---------- 硬件厂商 / 驱动下载 ----------
  www.nvidia.com
  us.download.nvidia.com
  developer.download.nvidia.com
  www.intel.com
  downloadmirror.intel.com
  www.amd.com
  drivers.amd.com
  www.samsung.com
  www.lg.com
  www.sony.com
  www.dell.com
  www.hp.com
  www.lenovo.com
  download.lenovo.com
  www.asus.com
  dlcdnets.asus.com
  www.logitech.com
  # ---------- 开发者 / 软件下载 ----------
  dl.google.com
  www.mozilla.org
  download-installer.cdn.mozilla.net
  addons.mozilla.org
  www.python.org
  files.pythonhosted.org
  pypi.org
  registry.npmjs.org
  nodejs.org
  www.jetbrains.com
  download.jetbrains.com
  download.unity3d.com
  www.adobe.com
  www.autodesk.com
  cdnjs.cloudflare.com
  www.cloudflare.com
  # ---------- 大型零售 / 品牌 ----------
  www.ebay.com
  www.walmart.com
  www.ikea.com
  www.nike.com
  www.uniqlo.com
  www.visa.com
  www.mastercard.com
  # ---------- 日韩东南亚本地大站 ----------
  www.yahoo.co.jp
  s.yimg.jp
  www.rakuten.co.jp
  www.sony.co.jp
  www.naver.com
  ssl.pstatic.net
  www.coupang.com
  www.shopee.sg
  www.lazada.sg
  www.grab.com
)

SHOW_ALL=0
if [ "${1:-}" = "-a" ]; then SHOW_ALL=1; shift; fi
[ $# -gt 0 ] && CANDIDATES=("$@")

command -v curl >/dev/null || { echo "需要 curl"; exit 1; }

is_excluded() {
  for e in ${EXCLUDE:-}; do [ "$e" = "$1" ] && return 0; done
  return 1
}

echo "测试 ${#CANDIDATES[@]} 个候选, 请稍候..."
RESULTS="$(
for d in "${CANDIDATES[@]}"; do
  if is_excluded "$d"; then continue; fi
  out=$(curl -sS -o /dev/null --max-time 6 --tlsv1.3 --tls-max 1.3 --http2 \
        -w "%{time_appconnect} %{http_version} %{ssl_verify_result}" \
        "https://$d/" 2>/dev/null)
  rc=$?
  if [ $rc -ne 0 ] || [ -z "$out" ]; then
    echo "9.999999 $d - - ✗ 不支持TLS1.3或连不上"
    continue
  fi
  read -r t hv verify <<<"$out"
  if [ "$verify" != "0" ]; then v="✗ 证书校验失败"
  elif [ "$hv" != "2" ]; then v="✗ 不支持H2"
  elif awk "BEGIN{exit !($t > 0.08)}"; then v="△ 较慢"
  else v="✓ 可用"
  fi
  echo "$t $d 1.3 $hv $v"
done | sort -g
)"

printf "\n%-40s %-9s %-4s %-5s %s\n" "SNI" "握手(s)" "TLS" "HTTP" "结论"
echo "$RESULTS" | while read -r t d tls hv v; do
  [ -z "$d" ] && continue
  if [ "$SHOW_ALL" = 0 ] && [[ "$v" == ✗* ]]; then continue; fi
  [ "$t" = "9.999999" ] && t="-"
  printf "%-40s %-9s %-4s %-5s %s\n" "$d" "$t" "$tls" "$hv" "$v"
done

ok=$(echo "$RESULTS" | grep -c "✓")
echo
echo "共 $ok 个可用 (✓)。加 -a 参数可查看不可用的。"
echo "选 ✓ 里握手最短、且没被其他节点用过的, 填进面板: SNI=该域名, Server Address 留空, Port=443"
