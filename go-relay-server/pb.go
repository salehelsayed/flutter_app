package main

// Manual protobuf encode/decode for the rendezvous protocol.
// Uses google.golang.org/protobuf/encoding/protowire to avoid
// requiring protoc as a build dependency.
//
// Wire-compatible with @canvas-js/libp2p-rendezvous Message type.

import (
	"fmt"

	"google.golang.org/protobuf/encoding/protowire"
)

// --- Enums ---

type MessageType int32

const (
	MessageType_REGISTER          MessageType = 0
	MessageType_REGISTER_RESPONSE MessageType = 1
	MessageType_UNREGISTER        MessageType = 2
	MessageType_DISCOVER          MessageType = 3
	MessageType_DISCOVER_RESPONSE MessageType = 4
)

type ResponseStatus int32

const (
	ResponseStatus_OK                           ResponseStatus = 0
	ResponseStatus_E_INVALID_NAMESPACE          ResponseStatus = 100
	ResponseStatus_E_INVALID_SIGNED_PEER_RECORD ResponseStatus = 101
	ResponseStatus_E_INVALID_TTL                ResponseStatus = 102
	ResponseStatus_E_INVALID_COOKIE             ResponseStatus = 103
	ResponseStatus_E_NOT_AUTHORIZED             ResponseStatus = 200
	ResponseStatus_E_INTERNAL_ERROR             ResponseStatus = 300
	ResponseStatus_E_UNAVAILABLE                ResponseStatus = 400
)

// --- Message structs ---

type RzMessage struct {
	Type             MessageType
	Register         *Register
	RegisterResponse *RegisterResponse
	Unregister       *Unregister
	Discover         *Discover
	DiscoverResponse *DiscoverResponse
}

type Register struct {
	Ns               string
	SignedPeerRecord []byte
	TTL              uint64
}

type RegisterResponse struct {
	Status     ResponseStatus
	StatusText string
	TTL        uint64
}

type Unregister struct {
	Ns string
}

type Discover struct {
	Ns     string
	Limit  uint64
	Cookie []byte
}

type DiscoverResponse struct {
	Status        ResponseStatus
	StatusText    string
	Registrations []Registration
	Cookie        []byte
}

type Registration struct {
	Ns               string
	SignedPeerRecord []byte
}

// --- Marshal ---

func (r *Register) Marshal() []byte {
	var b []byte
	if r.Ns != "" {
		b = protowire.AppendTag(b, 1, protowire.BytesType)
		b = protowire.AppendString(b, r.Ns)
	}
	if len(r.SignedPeerRecord) > 0 {
		b = protowire.AppendTag(b, 2, protowire.BytesType)
		b = protowire.AppendBytes(b, r.SignedPeerRecord)
	}
	if r.TTL > 0 {
		b = protowire.AppendTag(b, 3, protowire.VarintType)
		b = protowire.AppendVarint(b, r.TTL)
	}
	return b
}

func (r *RegisterResponse) Marshal() []byte {
	var b []byte
	b = protowire.AppendTag(b, 1, protowire.VarintType)
	b = protowire.AppendVarint(b, uint64(r.Status))
	if r.StatusText != "" {
		b = protowire.AppendTag(b, 2, protowire.BytesType)
		b = protowire.AppendString(b, r.StatusText)
	}
	if r.TTL > 0 {
		b = protowire.AppendTag(b, 3, protowire.VarintType)
		b = protowire.AppendVarint(b, r.TTL)
	}
	return b
}

func (u *Unregister) Marshal() []byte {
	var b []byte
	if u.Ns != "" {
		b = protowire.AppendTag(b, 1, protowire.BytesType)
		b = protowire.AppendString(b, u.Ns)
	}
	return b
}

func (d *Discover) Marshal() []byte {
	var b []byte
	if d.Ns != "" {
		b = protowire.AppendTag(b, 1, protowire.BytesType)
		b = protowire.AppendString(b, d.Ns)
	}
	if d.Limit > 0 {
		b = protowire.AppendTag(b, 2, protowire.VarintType)
		b = protowire.AppendVarint(b, d.Limit)
	}
	if len(d.Cookie) > 0 {
		b = protowire.AppendTag(b, 3, protowire.BytesType)
		b = protowire.AppendBytes(b, d.Cookie)
	}
	return b
}

func (reg *Registration) Marshal() []byte {
	var b []byte
	if reg.Ns != "" {
		b = protowire.AppendTag(b, 1, protowire.BytesType)
		b = protowire.AppendString(b, reg.Ns)
	}
	if len(reg.SignedPeerRecord) > 0 {
		b = protowire.AppendTag(b, 2, protowire.BytesType)
		b = protowire.AppendBytes(b, reg.SignedPeerRecord)
	}
	return b
}

func (dr *DiscoverResponse) Marshal() []byte {
	var b []byte
	b = protowire.AppendTag(b, 1, protowire.VarintType)
	b = protowire.AppendVarint(b, uint64(dr.Status))
	if dr.StatusText != "" {
		b = protowire.AppendTag(b, 2, protowire.BytesType)
		b = protowire.AppendString(b, dr.StatusText)
	}
	for _, reg := range dr.Registrations {
		regBytes := reg.Marshal()
		b = protowire.AppendTag(b, 3, protowire.BytesType)
		b = protowire.AppendBytes(b, regBytes)
	}
	if len(dr.Cookie) > 0 {
		b = protowire.AppendTag(b, 4, protowire.BytesType)
		b = protowire.AppendBytes(b, dr.Cookie)
	}
	return b
}

func (m *RzMessage) Marshal() []byte {
	var b []byte
	b = protowire.AppendTag(b, 1, protowire.VarintType)
	b = protowire.AppendVarint(b, uint64(m.Type))
	if m.Register != nil {
		data := m.Register.Marshal()
		b = protowire.AppendTag(b, 2, protowire.BytesType)
		b = protowire.AppendBytes(b, data)
	}
	if m.RegisterResponse != nil {
		data := m.RegisterResponse.Marshal()
		b = protowire.AppendTag(b, 3, protowire.BytesType)
		b = protowire.AppendBytes(b, data)
	}
	if m.Unregister != nil {
		data := m.Unregister.Marshal()
		b = protowire.AppendTag(b, 4, protowire.BytesType)
		b = protowire.AppendBytes(b, data)
	}
	if m.Discover != nil {
		data := m.Discover.Marshal()
		b = protowire.AppendTag(b, 5, protowire.BytesType)
		b = protowire.AppendBytes(b, data)
	}
	if m.DiscoverResponse != nil {
		data := m.DiscoverResponse.Marshal()
		b = protowire.AppendTag(b, 6, protowire.BytesType)
		b = protowire.AppendBytes(b, data)
	}
	return b
}

// --- Unmarshal ---

func skipField(wtype protowire.Type, data []byte) (int, error) {
	n := protowire.ConsumeFieldValue(0, wtype, data)
	if n < 0 {
		return 0, fmt.Errorf("invalid field value")
	}
	return n, nil
}

func UnmarshalRegister(data []byte) (*Register, error) {
	r := &Register{}
	for len(data) > 0 {
		num, wtype, n := protowire.ConsumeTag(data)
		if n < 0 {
			return nil, fmt.Errorf("invalid tag in Register")
		}
		data = data[n:]
		switch num {
		case 1:
			val, n := protowire.ConsumeString(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid ns")
			}
			r.Ns = val
			data = data[n:]
		case 2:
			val, n := protowire.ConsumeBytes(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid signedPeerRecord")
			}
			r.SignedPeerRecord = append([]byte(nil), val...)
			data = data[n:]
		case 3:
			val, n := protowire.ConsumeVarint(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid ttl")
			}
			r.TTL = val
			data = data[n:]
		default:
			skip, err := skipField(wtype, data)
			if err != nil {
				return nil, err
			}
			data = data[skip:]
		}
	}
	return r, nil
}

func UnmarshalUnregister(data []byte) (*Unregister, error) {
	u := &Unregister{}
	for len(data) > 0 {
		num, wtype, n := protowire.ConsumeTag(data)
		if n < 0 {
			return nil, fmt.Errorf("invalid tag in Unregister")
		}
		data = data[n:]
		switch num {
		case 1:
			val, n := protowire.ConsumeString(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid ns")
			}
			u.Ns = val
			data = data[n:]
		default:
			skip, err := skipField(wtype, data)
			if err != nil {
				return nil, err
			}
			data = data[skip:]
		}
	}
	return u, nil
}

func UnmarshalDiscover(data []byte) (*Discover, error) {
	d := &Discover{}
	for len(data) > 0 {
		num, wtype, n := protowire.ConsumeTag(data)
		if n < 0 {
			return nil, fmt.Errorf("invalid tag in Discover")
		}
		data = data[n:]
		switch num {
		case 1:
			val, n := protowire.ConsumeString(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid ns")
			}
			d.Ns = val
			data = data[n:]
		case 2:
			val, n := protowire.ConsumeVarint(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid limit")
			}
			d.Limit = val
			data = data[n:]
		case 3:
			val, n := protowire.ConsumeBytes(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid cookie")
			}
			d.Cookie = append([]byte(nil), val...)
			data = data[n:]
		default:
			skip, err := skipField(wtype, data)
			if err != nil {
				return nil, err
			}
			data = data[skip:]
		}
	}
	return d, nil
}

func UnmarshalRegistration(data []byte) (*Registration, error) {
	reg := &Registration{}
	for len(data) > 0 {
		num, wtype, n := protowire.ConsumeTag(data)
		if n < 0 {
			return nil, fmt.Errorf("invalid tag in Registration")
		}
		data = data[n:]
		switch num {
		case 1:
			val, n := protowire.ConsumeString(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid ns")
			}
			reg.Ns = val
			data = data[n:]
		case 2:
			val, n := protowire.ConsumeBytes(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid signedPeerRecord")
			}
			reg.SignedPeerRecord = append([]byte(nil), val...)
			data = data[n:]
		default:
			skip, err := skipField(wtype, data)
			if err != nil {
				return nil, err
			}
			data = data[skip:]
		}
	}
	return reg, nil
}

func UnmarshalRzMessage(data []byte) (*RzMessage, error) {
	m := &RzMessage{}
	for len(data) > 0 {
		num, wtype, n := protowire.ConsumeTag(data)
		if n < 0 {
			return nil, fmt.Errorf("invalid tag in Message")
		}
		data = data[n:]
		switch num {
		case 1:
			val, n := protowire.ConsumeVarint(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid type")
			}
			m.Type = MessageType(val)
			data = data[n:]
		case 2:
			val, n := protowire.ConsumeBytes(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid register")
			}
			reg, err := UnmarshalRegister(val)
			if err != nil {
				return nil, fmt.Errorf("register: %w", err)
			}
			m.Register = reg
			data = data[n:]
		case 3:
			// registerResponse — server doesn't need to decode responses it sends
			skip, err := skipField(wtype, data)
			if err != nil {
				return nil, err
			}
			data = data[skip:]
		case 4:
			val, n := protowire.ConsumeBytes(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid unregister")
			}
			unreg, err := UnmarshalUnregister(val)
			if err != nil {
				return nil, fmt.Errorf("unregister: %w", err)
			}
			m.Unregister = unreg
			data = data[n:]
		case 5:
			val, n := protowire.ConsumeBytes(data)
			if n < 0 {
				return nil, fmt.Errorf("invalid discover")
			}
			disc, err := UnmarshalDiscover(val)
			if err != nil {
				return nil, fmt.Errorf("discover: %w", err)
			}
			m.Discover = disc
			data = data[n:]
		case 6:
			// discoverResponse — server doesn't need to decode responses it sends
			skip, err := skipField(wtype, data)
			if err != nil {
				return nil, err
			}
			data = data[skip:]
		default:
			skip, err := skipField(wtype, data)
			if err != nil {
				return nil, err
			}
			data = data[skip:]
		}
	}
	return m, nil
}
