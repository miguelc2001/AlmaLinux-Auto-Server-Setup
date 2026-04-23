$TTL 86400
@   IN  SOA __NS_FQDN__. __ADMIN_EMAIL__. (
        __SERIAL__   ; serial (YYYYMMDDNN)
        3600         ; refresh (1h)
        1800         ; retry   (30m)
        604800       ; expire  (1w)
        86400 )      ; minimum (1d)
;
@       IN  NS   __NS_FQDN__.
@       IN  A    __SERVER_IP__
__NS_HOST__  IN  A    __SERVER_IP__
www     IN  A    __SERVER_IP__
