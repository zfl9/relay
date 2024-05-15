# relay

高性能 relay（中继/转发）工具，类似 socat，但专注于 proxy 领域，通过组合不同的 in、out 协议，可实现：

- ipt2socks：`in:tproxy` + `out:socks4/5`
- tls-client：`in:tproxy` + `out:tlsproxy`
- tls-server：`in:tlsproxy` + `out:raw`
- trojan-tproxy：`in:tproxy` + `out:trojan`
- trojan-client：`in:socks5` + `out:trojan`
- trojan-server：`in:trojan` + `out:raw`

> 积极开发中，优先实现 ipt2socks，并支持 socks4 传出，然后是 tlsproxy 协议、trojan-tproxy 客户端。

# 设计目标

- Linux only
- 高性能，尽可能零拷贝，减少系统调用
- 低资源开销，即便是低端路由器也能流畅运行
- 支持条件编译，避免对不需要的协议支付相关成本