//go:build integration

package main

import (
	"bytes"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
)

func TestProductionAudioCallPortSet_UsesIsolatedRelayPool(t *testing.T) {
	listen, first, last, err := reserveProductionAudioCallPortSet()
	if err != nil {
		t.Fatal(err)
	}
	if first < 40200 || last > 40999 || last-first+1 != 24 || last >= 49152 {
		t.Fatalf("relay block %d-%d is not 24 ports in the isolated fixture pool", first, last)
	}
	if listen >= first && listen <= last {
		t.Fatalf("listener %d overlaps relay block %d-%d", listen, first, last)
	}
	config := filepath.Join(t.TempDir(), "turnserver.conf")
	if err := writeProductionAudioCallCoturnConfig(config, "192.0.2.1", bytes.Repeat([]byte{'x'}, 32), first, last); err != nil {
		t.Fatal(err)
	}
	contents, err := os.ReadFile(config)
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range []string{"min-port=" + strconv.Itoa(first), "max-port=" + strconv.Itoa(last)} {
		if !strings.Contains(string(contents), line+"\n") {
			t.Fatalf("generated coturn config omitted selected relay bound %q", line)
		}
	}
}

func TestProductionAudioCallPortSet_RechecksAfterImagePreparationBeforeDockerRun(t *testing.T) {
	listen, first, last, err := reserveProductionAudioCallPortSet()
	if err != nil {
		t.Fatal(err)
	}
	port := first + productionAudioCallRelayPortCount/2
	held, err := net.ListenPacket("udp4", fmt.Sprintf("0.0.0.0:%d", port))
	if err != nil {
		t.Fatal(err)
	}
	defer held.Close()
	lock, _, err := loadProductionAudioCallCoturnLock(filepath.Join("..", "tool", "call_audio_oracle", "coturn.lock.json"))
	if err != nil {
		t.Fatal(err)
	}
	bin := t.TempDir()
	journal := filepath.Join(bin, "docker-operations")
	t.Setenv("MKNOON_PORT_CONTRACT_DOCKER_LOG", journal)
	docker := filepath.Join(bin, "docker")
	script := fmt.Sprintf("#!/bin/sh\nprintf '%%s\\n' \"$1\" >> \"$MKNOON_PORT_CONTRACT_DOCKER_LOG\"\nif [ \"$1\" = image ]; then\n  printf '[\"coturn/coturn@%s\"]\\n'\nelse\n  exit 99\nfi\n", lock.Digest)
	if err := os.WriteFile(docker, []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	lsof := fmt.Sprintf("#!/bin/sh\nprintf 'p2222\\ncremote-client\\nf7\\nn127.0.0.1:53000->127.0.0.1:%d\\np1234\\ncfixture-holder\\nf8\\nn*:%d\\n'\n", port, port)
	if err := os.WriteFile(filepath.Join(bin, "lsof"), []byte(lsof), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)
	fixture := &productionAudioCallDeviceFixture{dockerExecutable: docker}
	_, _, err = fixture.startCoturn(lock, filepath.Join(bin, "unused.conf"), listen, first, last)
	if err == nil || !errors.Is(err, syscall.EADDRINUSE) {
		t.Fatalf("want occupied-block preflight error, got %v", err)
	}
	for _, fragment := range []string{"coturn port preflight", "UDP port " + strconv.Itoa(port), "fixture-holder (PID 1234)"} {
		if !strings.Contains(err.Error(), fragment) {
			t.Errorf("preflight omitted %q: %v", fragment, err)
		}
	}
	if strings.Contains(err.Error(), "remote-client") {
		t.Fatalf("a client with this remote destination port is not its local holder: %v", err)
	}
	operations, readError := os.ReadFile(journal)
	if readError != nil || string(operations) != "image\nimage\n" {
		t.Fatalf("want image preparation followed by failure before docker run, operations=%q, err=%v", operations, readError)
	}
	if err := held.Close(); err != nil {
		t.Fatal(err)
	}
	// The failed bind must release every temporary listener it already opened.
	closers, err := bindProductionAudioCallPortSet(listen, first, last)
	if err != nil {
		t.Fatalf("preflight leaked a temporary binding: %v", err)
	}
	for _, closer := range closers {
		_ = closer.Close()
	}
}

func TestProductionAudioCallPortConflict_ExplainsUnavailableOwnerLookup(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	cause := &net.OpError{Op: "listen", Net: "udp4", Addr: &net.UDPAddr{IP: net.IPv4zero, Port: 40200}, Err: syscall.EADDRINUSE}
	err := productionAudioCallPortConflict(cause)
	if !errors.Is(err, syscall.EADDRINUSE) || !strings.Contains(err.Error(), "UDP port 40200; holder unavailable") || !strings.Contains(err.Error(), "lsof -nP -iUDP:40200") {
		t.Fatalf("missing owner diagnostic or original bind cause: %v", err)
	}
}
