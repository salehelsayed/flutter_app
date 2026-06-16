package node

import "time"

// GroupType represents the type of a group, which determines write permissions.
type GroupType string

const (
	GroupTypeChat         GroupType = "chat"
	GroupTypeAnnouncement GroupType = "announcement"
	GroupTypeQA           GroupType = "qa"
)

// GroupRole represents a member's role in a group.
type GroupRole string

const (
	GroupRoleAdmin  GroupRole = "admin"
	GroupRoleWriter GroupRole = "writer"
	GroupRoleReader GroupRole = "reader"
)

// GroupMemberDevice represents one active or revoked device registered under a
// member/account identity.
type GroupMemberDevice struct {
	DeviceId                 string `json:"deviceId"`
	TransportPeerId          string `json:"transportPeerId"`
	DeviceSigningPublicKey   string `json:"deviceSigningPublicKey"`
	MlKemPublicKey           string `json:"mlKemPublicKey,omitempty"`
	KeyPackageId             string `json:"keyPackageId,omitempty"`
	KeyPackagePublicMaterial string `json:"keyPackagePublicMaterial,omitempty"`
	Status                   string `json:"status,omitempty"`
	RevokedAt                string `json:"revokedAt,omitempty"`
}

// GroupMember represents a member of a group with their identity and role.
type GroupMember struct {
	PeerId         string              `json:"peerId"`
	Username       string              `json:"username,omitempty"`
	Role           GroupRole           `json:"role"`
	PublicKey      string              `json:"publicKey"`
	MlKemPublicKey string              `json:"mlKemPublicKey,omitempty"`
	Devices        []GroupMemberDevice `json:"devices,omitempty"`
}

// GroupConfig holds the configuration of a group.
type GroupConfig struct {
	Name              string        `json:"name"`
	GroupType         GroupType     `json:"groupType"`
	Description       string        `json:"description,omitempty"`
	AvatarBlobId      string        `json:"avatarBlobId,omitempty"`
	AvatarMime        string        `json:"avatarMime,omitempty"`
	MetadataUpdatedAt string        `json:"metadataUpdatedAt,omitempty"`
	ConfigVersion     string        `json:"configVersion,omitempty"`
	StateHash         string        `json:"stateHash,omitempty"`
	Members           []GroupMember `json:"members"`
	CreatedBy         string        `json:"createdBy"`
	CreatedAt         string        `json:"createdAt"`
}

// GroupEpochKey is one retained (epoch, key) pair in the held-keys ring.
type GroupEpochKey struct {
	Key      string `json:"key"`      // base64 AES-256 key for this epoch
	KeyEpoch int    `json:"keyEpoch"` // key rotation epoch
}

// GroupKeyInfo holds the symmetric encryption key(s) for a group.
//
// Keys is a retained ring of the most-recent epochs this node legitimately
// held while a member, newest-first (index 0 == current epoch). Decrypt/verify
// on the receive path consult the ring (no clock gate) so any held epoch still
// decrypts. Key/KeyEpoch mirror the ring head (current epoch) for the send path
// and wire/Dart back-compat. PrevKey/PrevKeyEpoch are a derived view over the
// second ring entry, preserved so existing JSON/Dart consumers keep parsing.
// GraceDeadline now governs only which epoch a node will sign/publish under.
type GroupKeyInfo struct {
	Key           string          `json:"key"`            // base64 AES-256 key (current epoch / ring head)
	KeyEpoch      int             `json:"keyEpoch"`       // current key rotation epoch
	PrevKey       string          `json:"prevKey"`        // derived view over ring[1]; previous key
	PrevKeyEpoch  int             `json:"prevKeyEpoch"`   // derived view over ring[1]; previous epoch
	GraceDeadline time.Time       `json:"graceDeadline"`  // zero when no grace period is active (send/sign constraint)
	Keys          []GroupEpochKey `json:"keys,omitempty"` // retained held-epoch ring, newest-first
}
