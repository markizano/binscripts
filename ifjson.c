
/**
 * ifconjig - readOnly ifconfig for JSON output.
 */

#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <netinet/ether.h>
#include <netdb.h>
#include <ifaddrs.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <json-c/json.h>

int Usage () {
    printf("Usage: ifjson [ifaddr] [inet|inet6]\nReturn codes:\n"\
        "  0: EXIT_OK - Got details on the network interface.\n"\
        "  4: Error - There was a general error processing the request.\n"
        "  8: User-error - getifaddr received invalid input.\n"
    );
    return 8;
}

/**
 * getnameinfo_ex: Wrapper around getnameinfo(3).
 * Gets the address in Decimal format from binary format based on a network socket struct.
 * @param address String representation label for the network address type.
 * @param if_addr Network we are trying to translate.
 * @param family enum { AF_INET, AF_INET6 }
 * @param host Output variable for the resulting address as a string.
 */
int getnameinfo_ex(char *address, struct sockaddr *if_addr, int family, char *host) {
    int s;
    s = getnameinfo(
        if_addr,
        (family == AF_INET) ? sizeof(struct sockaddr_in): sizeof(struct sockaddr_in6),
        host,
        NI_MAXHOST,
        NULL, 0, NI_NUMERICHOST
    );
    if ( s != 0) {
        return s;
    }
    return 0;
}

int get_interfaces() {
    struct json_object *interfaces, *interface, *inet, *jflags;
    struct ifaddrs *ifaddr, *ifa;
    struct ifreq ifr;
    char host[MAX_ADDR_LEN], netmask[MAX_ADDR_LEN], bcast[MAX_ADDR_LEN], dest[MAX_ADDR_LEN],
      *iface;
    unsigned char hwaddr[MAX_ADDR_LEN];
    int family, fd, mtu, metric, result = 0;
    short flags;

    if (getifaddrs(&ifaddr) == -1) {
        perror("getifaddrs");
        exit(EXIT_FAILURE);
    }
    interfaces = json_object_new_object();
    for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        int s;
        if (ifa->ifa_addr == NULL) continue;
        family = ifa->ifa_addr->sa_family;
        iface = strndup(ifa->ifa_name, strlen(ifa->ifa_name));
        memset(host, 0, sizeof host);
        memset(netmask, 0, sizeof netmask);
        memset(bcast, 0, sizeof bcast);
        memset(dest, 0, sizeof dest);
        mtu = 0;
        metric = 0;
        flags = 0;
        memset(hwaddr, 0, sizeof hwaddr);
        switch(family) {
            case AF_PACKET:
                s = 0;
                fprintf(stderr, ">> Found packet data on %s\n", ifa->ifa_name);
            break;
            case AF_INET6:
            case AF_INET:
                //fprintf(stderr, ">> Found \x1b[1m%s\x1b[0m data on \x1b[33m%s\x1b[0m\n", family == AF_INET? "inet": "inet6", ifa->ifa_name);
                s = getnameinfo_ex("ifaddr", ifa->ifa_addr, family, host);
                if ( s != 0 ) return s;

                s = getnameinfo_ex("netmask", ifa->ifa_netmask, family, netmask);
                if ( s != 0 ) return s;

                s = getnameinfo_ex("broadcast", ifa->ifa_ifu.ifu_broadaddr, family, bcast);
                if ( s != 0 && s != EAI_FAMILY ) {
                    return 1;
                }

                s = getnameinfo_ex("destination", ifa->ifa_ifu.ifu_dstaddr, family, dest);
                if ( s != 0 && s != EAI_FAMILY ) {
                    return 1;
                }

                if ( family == AF_INET ) {
                    fd = socket(family, SOCK_DGRAM, 0);
                    if (fd == -1) {
                        fprintf(stderr, "Failed to open socket.\n");
                        return 1;
                    }
                    memcpy(ifr.ifr_name, iface, sizeof iface);
                    ioctl(fd, SIOCGIFMTU, &ifr);
                    mtu = ifr.ifr_mtu;

                    ioctl(fd, SIOCGIFMETRIC, &ifr);
                    metric = ifr.ifr_metric;

                    ioctl(fd, SIOCGIFFLAGS, &ifr);
                    flags = ifr.ifr_flags;

                    ioctl(fd, SIOCGIFHWADDR, &ifr);
                    if ( ifr.ifr_hwaddr.sa_family != ARPHRD_LOOPBACK ) {
                        memcpy(hwaddr, ether_ntoa((struct ether_addr*)ifr.ifr_hwaddr.sa_data), sizeof hwaddr);
                    }

                    close(fd);
                }

                if ( json_object_object_get_ex(interfaces, iface, &interface) ) {
                    json_object_get(interface);
                } else {
                    interface = json_object_new_object();
                }
                if ( json_object_object_get_ex(interface, (family == AF_INET) ? "inet4": "inet6", &inet) ) {
                    json_object_get(inet);
                } else {
                    inet = json_object_new_object();
                }
                json_object_object_add(inet, "address", json_object_new_string(host));
                json_object_object_add(inet, "netmask", json_object_new_string(netmask));
                json_object_object_add(inet, "broadcast", json_object_new_string(bcast));
                json_object_object_add(inet, "destination", json_object_new_string(dest));

                json_object_object_add(interface, (family == AF_INET) ? "inet4": "inet6", inet);

                if ( family == AF_INET ) {
                    json_object_object_add(interface, "mtu", json_object_new_int(mtu));
                    json_object_object_add(interface, "hwaddr", json_object_new_string(hwaddr));
                    json_object_object_add(interface, "metric", json_object_new_int(metric));
                    if ( flags != 0 ) {
                        jflags = json_object_new_array();
                        if ( (flags & IFF_UP) == IFF_UP ) {
                            json_object_array_add(jflags, json_object_new_string("up"));
                        }
                        if ( (flags & IFF_BROADCAST) == IFF_BROADCAST ) {
                            json_object_array_add(jflags, json_object_new_string("broadcast"));
                        }
#ifdef IFF_DEBUG
                        if ( (flags & IFF_DEBUG) == IFF_DEBUG ) {
                            json_object_array_add(jflags, json_object_new_string("debug"));
                        }
#endif
#ifdef IFF_LOOPBACK
                        if ( (flags & IFF_LOOPBACK) == IFF_LOOPBACK ) {
                            json_object_array_add(jflags, json_object_new_string("loopback"));
                        }
#endif
#ifdef IFF_POINTOTPOINT
                        if ( (flags & IFF_POINTOTPOINT) == IFF_POINTOTPOINT ) {
                            json_object_array_add(jflags, json_object_new_string("pointotpoint"));
                        }
#endif
#ifdef IFF_RUNNING
                        if ( (flags & IFF_RUNNING) == IFF_RUNNING ) {
                            json_object_array_add(jflags, json_object_new_string("running"));
                        }
#endif
#ifdef IFF_NOARM
                        if ( (flags & IFF_NOARM) == IFF_NOARM ) {
                            json_object_array_add(jflags, json_object_new_string("noarm"));
                        }
#endif
#ifdef IFF_PROMISC
                        if ( (flags & IFF_PROMISC) == IFF_PROMISC ) {
                            json_object_array_add(jflags, json_object_new_string("promisc"));
                        }
#endif
#ifdef IFF_NOTRAILERS
                        if ( (flags & IFF_NOTRAILERS) == IFF_NOTRAILERS ) {
                            json_object_array_add(jflags, json_object_new_string("notrailers"));
                        }
#endif
#ifdef IFF_ALLMULTI
                        if ( (flags & IFF_ALLMULTI) == IFF_ALLMULTI ) {
                            json_object_array_add(jflags, json_object_new_string("allmulti"));
                        }
#endif
#ifdef IFF_MASTER
                        if ( (flags & IFF_MASTER) == IFF_MASTER ) {
                            json_object_array_add(jflags, json_object_new_string("master"));
                        }
#endif
#ifdef IFF_SLAVE
                        if ( (flags & IFF_SLAVE) == IFF_SLAVE ) {
                            json_object_array_add(jflags, json_object_new_string("slave"));
                        }
#endif
#ifdef IFF_MULTICAST
                        if ( (flags & IFF_MULTICAST) == IFF_MULTICAST ) {
                            json_object_array_add(jflags, json_object_new_string("multicast"));
                        }
#endif
#ifdef IFF_PORTSEL
                        if ( (flags & IFF_PORTSEL) == IFF_PORTSEL ) {
                            json_object_array_add(jflags, json_object_new_string("portsel"));
                        }
#endif
#ifdef IFF_AUTOMEDIA
                        if ( (flags & IFF_AUTOMEDIA) == IFF_AUTOMEDIA ) {
                            json_object_array_add(jflags, json_object_new_string("automedia"));
                        }
#endif
#ifdef IFF_DYNAMIC
                        if ( (flags & IFF_DYNAMIC) == IFF_DYNAMIC ) {
                            json_object_array_add(jflags, json_object_new_string("dynamic"));
                        }
#endif
#ifdef IFF_LOWER_UP
                        if ( (flags & IFF_LOWER_UP) == IFF_LOWER_UP ) {
                            json_object_array_add(jflags, json_object_new_string("lower_up"));
                        }
#endif
#ifdef IFF_DORMANT
                        if ( (flags & IFF_DORMANT) == IFF_DORMANT ) {
                            json_object_array_add(jflags, json_object_new_string("dormant"));
                        }
#endif
#ifdef IFF_ECHO
                        if ( (flags & IFF_ECHO) == IFF_ECHO ) {
                            json_object_array_add(jflags, json_object_new_string("echo"));
                        }
#endif
                    }
                    json_object_object_add(interface, "flags", jflags);
                }
                json_object_object_add(interfaces, iface, interface);
            break;
            default:
                s = -1;
                fprintf(stderr, "\x1b[31mDon't know what to do with %d\x1b[0m\n", family);
            break;
        }
        free(iface);
    }

    printf("%s\n", json_object_to_json_string_ext(interfaces, JSON_C_TO_STRING_SPACED | JSON_C_TO_STRING_PRETTY));
    freeifaddrs(ifaddr);
    if ( json_object_put(jflags) != 1 ) {
        perror("MEMFREE");
    }
    if ( json_object_put(interface) != 1 ) {
        perror("MEMFREE");
    }
    if ( json_object_put(interfaces) != 1 ) {
        perror("MEMFREE");
    }
    return result;
}

int main(int argc, char *argv[]) {
    int result = 0;
    if ( argc >= 2 ) {
        if ( !strcmp(argv[1], "-h") || !strcmp(argv[1], "--help") ) {
            return Usage();
        }
    }
    if ( get_interfaces() != 0 ) {
        fprintf(stderr, "Failed to get interface list.\n");
        result = 1;
    }
    return result;
}