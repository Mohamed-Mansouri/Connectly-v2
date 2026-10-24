CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK(kind IN ('direct', 'group')),
  title TEXT,
  direct_key TEXT UNIQUE,
  created_by TEXT NOT NULL REFERENCES users(id),
  created_at TEXT NOT NULL,
  CHECK((kind = 'direct' AND direct_key IS NOT NULL) OR (kind = 'group' AND title IS NOT NULL))
);
CREATE TABLE IF NOT EXISTS conversation_members (
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  last_read_sequence INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS conversation_members_user ON conversation_members(user_id, conversation_id);
CREATE TABLE IF NOT EXISTS messages (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id TEXT NOT NULL REFERENCES users(id),
  client_id TEXT NOT NULL,
  body TEXT NOT NULL CHECK(length(body) BETWEEN 1 AND 4000),
  created_at TEXT NOT NULL,
  UNIQUE(conversation_id, sender_id, client_id)
);
CREATE INDEX IF NOT EXISTS messages_conversation_sequence ON messages(conversation_id, sequence DESC);
INSERT INTO connectly_schema_migrations (version) VALUES (3)
ON CONFLICT(version) DO NOTHING;
