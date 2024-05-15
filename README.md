# relay

高性能 relay（中继/转发）工具，类似 socat，但专注于 proxy 领域，通过组合不同的 in、out 协议，可实现：

- ipt2socks：`in:tproxy` + `out:socks5`
- tls-client：`in:tproxy` + `out:tls-proxy`
- tls-server：`in:tls-proxy` + `out:raw`
- trojan-client：`in:socks5` + `out:trojan`
- trojan-tproxy：`in:tproxy` + `out:trojan`
- trojan-server：`in:trojan` + `out:raw`

> 积极开发中，优先实现 ipt2socks，并支持 socks4 传出，然后是 tls-proxy 协议、trojan-tproxy 客户端。
