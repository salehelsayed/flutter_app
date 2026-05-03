package main

// GroupInboxBackend abstracts the storage layer for group inbox messages.
type GroupInboxBackend interface {
	// Store appends a message to a group's inbox.
	Store(groupId string, from string, message string) error

	// RetrieveSince returns messages for a group with timestamp > sinceTimestamp.
	// Messages are NOT deleted on retrieve (non-destructive read).
	RetrieveSince(groupId string, sinceTimestamp int64) []groupInboxMessage

	// RetrieveCursor returns up to limit messages for a group starting after
	// the given opaque cursor. An empty cursor starts from the beginning.
	// Returns the messages, next cursor (empty string if no more), and any
	// explicit history-gap metadata detected at the cursor boundary.
	RetrieveCursor(groupId string, cursor string, limit int) (messages []groupInboxMessage, nextCursor string, historyGaps []groupInboxHistoryGap)

	// Prune removes expired messages across all groups.
	Prune()

	// Stats returns the number of active groups and total message count.
	Stats() (groups int, totalMessages int)
}

// GroupInboxRecipientBackend is implemented by backends that can persist the
// per-message recipient ACL used by relay stream authorization.
type GroupInboxRecipientBackend interface {
	StoreWithRecipients(groupId string, from string, message string, recipientPeerIds []string) error
}
