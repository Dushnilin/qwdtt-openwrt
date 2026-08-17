//go:build linux && !android

package main

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"
)

const openWrtRouteTable = "51820"

var interfaceNamePattern = regexp.MustCompile(`^[a-zA-Z0-9_.:-]+$`)

type nativeRawTUN struct {
	file         *os.File
	name         string
	lanInterface string
}

func createNativeRawTUN(name, lanInterface, address string, mtu int) (*nativeRawTUN, error) {
	if name == "" {
		name = "qwdtt0"
	}
	if lanInterface == "" {
		lanInterface = "br-lan"
	}
	if !validInterfaceName(name) || !validInterfaceName(lanInterface) {
		return nil, fmt.Errorf("invalid interface name")
	}
	ip := net.ParseIP(address).To4()
	if ip == nil {
		return nil, fmt.Errorf("invalid raw IPv4 address %q", address)
	}
	if mtu < 576 || mtu > 9000 {
		return nil, fmt.Errorf("invalid MTU %d", mtu)
	}

	fd, err := unix.Open("/dev/net/tun", unix.O_RDWR|unix.O_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("open /dev/net/tun: %w", err)
	}
	ifr, err := unix.NewIfreq(name)
	if err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("create ifreq: %w", err)
	}
	ifr.SetUint16(unix.IFF_TUN | unix.IFF_NO_PI)
	if err := unix.IoctlIfreq(fd, unix.TUNSETIFF, ifr); err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("TUNSETIFF: %w", err)
	}
	if err := unix.SetNonblock(fd, false); err != nil {
		unix.Close(fd)
		return nil, fmt.Errorf("set blocking TUN: %w", err)
	}

	t := &nativeRawTUN{
		file:         os.NewFile(uintptr(fd), "/dev/net/tun"),
		name:         name,
		lanInterface: lanInterface,
	}
	if err := t.configure(address, mtu); err != nil {
		t.file.Close()
		return nil, err
	}
	return t, nil
}

func validInterfaceName(name string) bool {
	return len(name) > 0 && len(name) < unix.IFNAMSIZ && interfaceNamePattern.MatchString(name)
}

func (t *nativeRawTUN) configure(address string, mtu int) error {
	commands := [][]string{
		{"ip", "addr", "replace", address + "/16", "dev", t.name},
		{"ip", "link", "set", "dev", t.name, "mtu", strconv.Itoa(mtu), "up"},
	}
	for _, command := range commands {
		if err := runNativeCommand(command...); err != nil {
			return err
		}
	}
	_ = runNativeCommand("ip", "route", "flush", "table", openWrtRouteTable)
	if err := runNativeCommand("ip", "route", "replace", "default", "dev", t.name, "table", openWrtRouteTable); err != nil {
		return err
	}
	_ = runNativeCommand("ip", "rule", "del", "iif", t.lanInterface, "lookup", openWrtRouteTable, "priority", "10000")
	if err := runNativeCommand("ip", "rule", "add", "iif", t.lanInterface, "lookup", openWrtRouteTable, "priority", "10000"); err != nil {
		return err
	}
	if err := os.WriteFile("/proc/sys/net/ipv4/ip_forward", []byte("1\n"), 0644); err != nil {
		return fmt.Errorf("enable IPv4 forwarding: %w", err)
	}
	return nil
}

func (t *nativeRawTUN) cleanup() {
	_ = t.file.Close()
	_ = runNativeCommand("ip", "rule", "del", "iif", t.lanInterface, "lookup", openWrtRouteTable, "priority", "10000")
	_ = runNativeCommand("ip", "route", "flush", "table", openWrtRouteTable)
	_ = runNativeCommand("ip", "link", "del", t.name)
}

func runNativeCommand(args ...string) error {
	cmd := exec.Command(args[0], args[1:]...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(out))
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("%s: %s", strings.Join(args, " "), message)
	}
	return nil
}
