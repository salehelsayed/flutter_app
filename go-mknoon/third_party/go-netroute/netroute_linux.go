// Copyright 2012 Google, Inc. All rights reserved.
//
// Use of this source code is governed by a BSD-style license
// that can be found in the LICENSE file in the root of the source
// tree.

//go:build linux

// Generate a local routing table structure following the code at
// https://github.com/google/gopacket/blob/master/routing/routing.go

package netroute

import (
	"errors"
	"net"
	"runtime"
	"sort"
	"syscall"
	"unsafe"

	"github.com/google/gopacket/routing"
)

func New() (routing.Router, error) {
	if newRouterFailureHook != nil {
		if err := newRouterFailureHook(); err != nil {
			return nil, err
		}
	}
	// 190: On Android, SELinux denies the netlink route-socket bind (b/155595000,
	// targetSdk>=30), so the syscall.NetlinkRIB below ALWAYS fails at the bind —
	// but the bind ATTEMPT still emits an `avc: denied { bind }
	// tclass=netlink_route_socket` audit denial on every call, and basichost
	// retries it every ~5s (the SELinux audit spam the spec flags). Short-circuit
	// BEFORE the bind: behaviorally identical to the denied-bind failure (every
	// caller already degrades gracefully on this error — interface addresses come
	// from the anet-backed manet interface-address lane, not from netroute), but
	// with no audit spam. runtime.GOOS is a compile-time constant, so the
	// non-Android linux build keeps the syscall path byte-for-byte unchanged.
	if runtime.GOOS == "android" {
		return nil, errors.New("netroute: disabled on android (netlink route-socket bind denied by SELinux, b/155595000)")
	}
	rtr := &router{}
	rtr.ifaces = make(map[int]net.Interface)
	rtr.addrs = make(map[int]ipAddrs)
	tab, err := syscall.NetlinkRIB(syscall.RTM_GETROUTE, syscall.AF_UNSPEC)
	if err != nil {
		return nil, err
	}
	msgs, err := syscall.ParseNetlinkMessage(tab)
	if err != nil {
		return nil, err
	}
loop:
	for _, m := range msgs {
		switch m.Header.Type {
		case syscall.NLMSG_DONE:
			break loop
		case syscall.RTM_NEWROUTE:
			rt := (*syscall.RtMsg)(unsafe.Pointer(&m.Data[0]))
			routeInfo := rtInfo{}
			attrs, err := syscall.ParseNetlinkRouteAttr(&m)
			if err != nil {
				return nil, err
			}
			if rt.Family != syscall.AF_INET && rt.Family != syscall.AF_INET6 {
				continue loop
			}
			for _, attr := range attrs {
				switch attr.Attr.Type {
				case syscall.RTA_DST:
					routeInfo.Dst = &net.IPNet{
						IP:   net.IP(attr.Value),
						Mask: net.CIDRMask(int(rt.Dst_len), len(attr.Value)*8),
					}
				case syscall.RTA_SRC:
					routeInfo.Src = &net.IPNet{
						IP:   net.IP(attr.Value),
						Mask: net.CIDRMask(int(rt.Src_len), len(attr.Value)*8),
					}
				case syscall.RTA_GATEWAY:
					routeInfo.Gateway = net.IP(attr.Value)
				case syscall.RTA_PREFSRC:
					routeInfo.PrefSrc = net.IP(attr.Value)
				case syscall.RTA_IIF:
					routeInfo.InputIface = *(*uint32)(unsafe.Pointer(&attr.Value[0]))
				case syscall.RTA_OIF:
					routeInfo.OutputIface = *(*uint32)(unsafe.Pointer(&attr.Value[0]))
				case syscall.RTA_PRIORITY:
					routeInfo.Priority = *(*uint32)(unsafe.Pointer(&attr.Value[0]))
				}
			}
			if routeInfo.Dst == nil && routeInfo.Src == nil && routeInfo.Gateway == nil {
				continue loop
			}
			switch rt.Family {
			case syscall.AF_INET:
				rtr.v4 = append(rtr.v4, &routeInfo)
			case syscall.AF_INET6:
				rtr.v6 = append(rtr.v6, &routeInfo)
			default:
				// should not happen.
				continue loop
			}
		}
	}
	sort.Sort(rtr.v4)
	sort.Sort(rtr.v6)
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	for _, iface := range ifaces {
		rtr.ifaces[iface.Index] = iface
		var addrs ipAddrs
		ifaceAddrs, err := iface.Addrs()
		if err != nil {
			return nil, err
		}
		for _, addr := range ifaceAddrs {
			if inet, ok := addr.(*net.IPNet); ok {
				// Go has a nasty habit of giving you IPv4s as ::ffff:1.2.3.4 instead of 1.2.3.4.
				// We want to use mapped v4 addresses as v4 preferred addresses, never as v6
				// preferred addresses.
				if v4 := inet.IP.To4(); v4 != nil {
					if addrs.v4 == nil {
						addrs.v4 = v4
					}
				} else if addrs.v6 == nil {
					addrs.v6 = inet.IP
				}
			}
		}
		rtr.addrs[iface.Index] = addrs
	}
	return rtr, nil
}
