package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
)

const (
	relayPrivateKeyEnv  = "RELAY_PRIVATE_KEY"
	relayServerDNSEnv   = "RELAY_SERVER_DNS"
	relayServerIPEnv    = "RELAY_SERVER_IP"
	relayWSPortEnv      = "RELAY_WS_PORT"
	relayTCPPortEnv     = "RELAY_TCP_PORT"
	relayWSSPortEnv     = "RELAY_WSS_PORT"
	relayQUICPortEnv    = "RELAY_QUIC_PORT"
	relayDataDirEnv     = "RELAY_DATA_DIR"
	defaultRelayDataDir = "/data"
)

// defaultPrivateKeyRaw is the original hardcoded Ed25519 key.
// Used as fallback when RELAY_PRIVATE_KEY is not set.
var defaultPrivateKeyRaw = []byte{
	3, 98, 126, 31, 53, 38, 77, 83, 95, 52, 208,
	245, 12, 231, 179, 29, 77, 119, 64, 225, 28, 76,
	152, 60, 22, 170, 169, 92, 240, 114, 50, 34, 97,
	34, 166, 6, 69, 146, 135, 77, 74, 250, 62, 215,
	106, 6, 45, 2, 118, 162, 136, 195, 108, 174, 61,
	180, 216, 136, 89, 9, 101, 139, 157, 193,
}

// ServerConfig holds network identity and addressing configuration.
type ServerConfig struct {
	PrivateKey []byte
	ServerDNS  string
	ServerIP4  string
	WSPort     int
	TCPPort    int
	WSSPort    int
	QUICPort   int
}

// StorageConfig holds media/profile data roots.
type StorageConfig struct {
	RootDir    string
	MediaDir   string
	ProfileDir string
}

// DefaultServerConfig returns the configuration matching the original
// primary node (mknoun.xyz). Used when environment variables are not set.
func DefaultServerConfig() ServerConfig {
	return ServerConfig{
		PrivateKey: defaultPrivateKeyRaw,
		ServerDNS:  "mknoun.xyz",
		ServerIP4:  "13.60.15.36",
		WSPort:     4000,
		TCPPort:    4005,
		WSSPort:    4001,
		QUICPort:   4002,
	}
}

// loadServerConfigFromEnv reads server configuration from environment
// variables, falling back to DefaultServerConfig() for any unset values.
func loadServerConfigFromEnv() ServerConfig {
	defaults := DefaultServerConfig()

	cfg := ServerConfig{
		PrivateKey: defaults.PrivateKey,
		ServerDNS:  envStrOrDefault(relayServerDNSEnv, defaults.ServerDNS),
		ServerIP4:  envStrOrDefault(relayServerIPEnv, defaults.ServerIP4),
		WSPort:     envIntOrDefault(relayWSPortEnv, defaults.WSPort),
		TCPPort:    envIntOrDefault(relayTCPPortEnv, defaults.TCPPort),
		WSSPort:    envIntOrDefault(relayWSSPortEnv, defaults.WSSPort),
		QUICPort:   envIntOrDefault(relayQUICPortEnv, defaults.QUICPort),
	}

	if raw := strings.TrimSpace(os.Getenv(relayPrivateKeyEnv)); raw != "" {
		key, err := base64.StdEncoding.DecodeString(raw)
		if err != nil {
			log.Fatalf("Invalid %s: bad base64: %v", relayPrivateKeyEnv, err)
		}
		if len(key) != ed25519.PrivateKeySize {
			log.Fatalf("Invalid %s: expected %d bytes, got %d", relayPrivateKeyEnv, ed25519.PrivateKeySize, len(key))
		}
		cfg.PrivateKey = key
	}

	return cfg
}

// loadStorageConfigFromEnv chooses a writable storage root.
//
// Priority:
//  1. RELAY_DATA_DIR when explicitly set
//  2. /data when it is writable/creatable
//  3. <working-directory>/data as a local-dev fallback
func loadStorageConfigFromEnv() StorageConfig {
	cfg, fallbackReason, err := resolveStorageConfig(
		strings.TrimSpace(os.Getenv(relayDataDirEnv)),
		os.MkdirAll,
		os.Getwd,
	)
	if err != nil {
		log.Fatalf("Failed to resolve relay storage config: %v", err)
	}
	if fallbackReason != "" {
		log.Printf(
			"[STORAGE] Falling back to %s because %s",
			cfg.RootDir,
			fallbackReason,
		)
	}
	return cfg
}

func resolveStorageConfig(
	explicitRoot string,
	ensureDir func(string, os.FileMode) error,
	getwd func() (string, error),
) (StorageConfig, string, error) {
	root := strings.TrimSpace(explicitRoot)
	fallbackReason := ""
	if root == "" {
		root = defaultRelayDataDir
		if err := ensureDir(root, 0755); err != nil {
			wd, wdErr := getwd()
			if wdErr != nil {
				return StorageConfig{}, "", fmt.Errorf(
					"default storage root %s unavailable (%v) and getwd failed: %w",
					defaultRelayDataDir,
					err,
					wdErr,
				)
			}
			root = filepath.Join(wd, "data")
			fallbackReason = fmt.Sprintf(
				"%s is unavailable: %v",
				defaultRelayDataDir,
				err,
			)
		}
	}

	if err := ensureDir(root, 0755); err != nil {
		return StorageConfig{}, "", fmt.Errorf(
			"storage root %s is unavailable: %w",
			root,
			err,
		)
	}

	return StorageConfig{
		RootDir:    root,
		MediaDir:   filepath.Join(root, "media"),
		ProfileDir: filepath.Join(root, "profiles"),
	}, fallbackReason, nil
}

// IsCustomKey reports whether the config uses a non-default private key.
func (c ServerConfig) IsCustomKey() bool {
	if len(c.PrivateKey) != len(defaultPrivateKeyRaw) {
		return true
	}
	for i := range c.PrivateKey {
		if c.PrivateKey[i] != defaultPrivateKeyRaw[i] {
			return true
		}
	}
	return false
}

func envStrOrDefault(key, fallback string) string {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	return raw
}

// generateAndPrintKey generates a new Ed25519 keypair and prints the
// base64-encoded raw key (seed + public, 64 bytes) to stdout.
func generateAndPrintKey() {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		log.Fatalf("Failed to generate Ed25519 key: %v", err)
	}
	raw := append(priv.Seed(), pub...)
	fmt.Println(base64.StdEncoding.EncodeToString(raw))
}
