root上传sing-box.tar.gz 

bash <(curl -sL https://github.com/linlin8866/sing-/raw/main/sing.sh)

bash <(wget -qO- https://github.com/linlin8866/sing-/raw/main/sing.sh)


proxies:
  - name: Server-anytls
    type: anytls
    server: 23.136.164.185
    port: 62734
    password: hcBj3TqSKm4qm-fpcL-YpJqaL-Oiza8hPbogE9PGEAo
    tls: true
    servername: www.bing.com
    skip-cert-verify: true

  - name: Server-ss
    type: ss
    server: 23.136.164.185
    port: 48139
    cipher: 2022-blake3-aes-128-gcm
    password: XhJGdlS2Q6EW/u+FqFTAag==
    udp: true

  - name: Server-hy2
    type: hysteria2
    server: 23.136.164.185
    port: 63636
    password: QDs6QpQdW8x1
    alpn:
      - h3
    sni: www.bing.com
    skip-cert-verify: true
    fast-open: true
    udp: true

  - name: Server-trojan
    type: trojan
    server: 23.136.164.185
    port: 11982
    password: B0kT+7gGyNe81FaFtiONqw==
    tls: true
    servername: www.bing.com
    skip-cert-verify: true
    udp: true

  - name: Server-tuic
    type: tuic
    server: 23.136.164.185
    port: 14160
    uuid: 92f3553f-c68d-4c26-9f1a-2437ce27d073
    password: FMO8bceeW7Hq
    tls: true
    servername: www.bing.com
    skip-cert-verify: true
    congestion-control: cubic
    udp: true

  - name: Server-http
    type: http
    server: 23.136.164.185
    port: 41747
    username: Zwsj8w4h
    password: iOV4XhAidIUK
    tls: true
    servername: www.bing.com
    skip-cert-verify: true

  - name: Server-socks5
    type: socks5
    server: 23.136.164.185
    port: 34324
    username: 4qTUXiIN
    password: TM9BV3XCbseZ
    udp: true

  - name: Server-naive
    type: naive
    server: 23.136.164.185
    port: 19832
    username: hjIwJUGC
    password: 7xau4UhkYer8
    tls: true
    servername: www.bing.com
    skip-cert-verify: true

proxy-groups:
  - name: 自动选择
    type: url-test
    proxies:
      - Server-anytls
      - Server-ss
      - Server-hy2
      - Server-trojan
      - Server-tuic
      - Server-http
      - Server-socks5
      - Server-naive
    url: http://www.gstatic.com/generate_204
    interval: 300

