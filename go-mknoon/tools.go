//go:build tools

package tools

// Blank import to keep golang.org/x/mobile in go.mod.
// Required by gomobile bind at build time.
import _ "golang.org/x/mobile/bind"
