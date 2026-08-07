# net.device

defined in the native [net.device](../src/device.c) module. It enumerates the
network interfaces provided by the operating system.


## interfaces, err = device.getifaddrs()

return a table keyed by interface name. Each value is an interface table that
may contain:

- boolean flags: `up`, `broadcast`, `debug`, `loopback`, `pointtopoint`,
  `notrailers`, `running`, `noarp`, `promisc`, `allmulti`, `multicast`, and
  platform-specific flags such as `simplex` or `lower_up`;
- `index:number`: the interface index;
- `mtu:number`: the interface MTU;
- `ether:string`: the link-layer address in colon-separated hexadecimal form;
- `inet:table[]`: IPv4 address records;
- `inet6:table[]`: IPv6 address records.

Each IPv4 or IPv6 address record may contain `address`, `netmask`, `broadcast`,
and `point2point` string fields when the operating system provides them.
Interface and address ordering is the ordering returned by `getifaddrs(3)`.

**Returns**

- `interfaces:table`: interface name to interface information mapping;
- `err:error`: error object when `getifaddrs(3)` fails.
