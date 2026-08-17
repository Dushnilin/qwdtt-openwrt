//go:build !linux || android

package main

import (
	"fmt"
	"os"
)

type nativeRawTUN struct {
	file         *os.File
	name         string
	lanInterface string
}

func createNativeRawTUN(_, _, _ string, _ int) (*nativeRawTUN, error) {
	return nil, fmt.Errorf("native RAW TUN is supported only on Linux/OpenWrt")
}

func (t *nativeRawTUN) cleanup() {}
