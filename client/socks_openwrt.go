//go:build openwrt

package main

import (
	"context"
	"fmt"
)

type unsupportedWireGuard struct{}
type unsupportedNetstack struct{}

func (d *unsupportedWireGuard) Close() {}

func startUserspaceWireGuard(string) (*unsupportedWireGuard, *unsupportedNetstack, error) {
	return nil, nil, fmt.Errorf("WireGuard and SOCKS modes are not included in the OpenWrt RAW build")
}

func runSocks5Server(context.Context, string, *unsupportedNetstack, bool, string, string) error {
	return fmt.Errorf("SOCKS mode is not included in the OpenWrt RAW build")
}
