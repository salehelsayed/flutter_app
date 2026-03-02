package node

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

// GroupMember represents a member of a group with their identity and role.
type GroupMember struct {
	PeerId         string    `json:"peerId"`
	Username       string    `json:"username,omitempty"`
	Role           GroupRole `json:"role"`
	PublicKey      string    `json:"publicKey"`
	MlKemPublicKey string    `json:"mlKemPublicKey,omitempty"`
}

// GroupConfig holds the configuration of a group.
type GroupConfig struct {
	Name        string        `json:"name"`
	GroupType   GroupType     `json:"groupType"`
	Description string        `json:"description,omitempty"`
	Members     []GroupMember `json:"members"`
	CreatedBy   string        `json:"createdBy"`
	CreatedAt   string        `json:"createdAt"`
}

// GroupKeyInfo holds the symmetric encryption key for a group.
type GroupKeyInfo struct {
	Key      string `json:"key"`      // base64 AES-256 key
	KeyEpoch int    `json:"keyEpoch"` // key rotation epoch
}
