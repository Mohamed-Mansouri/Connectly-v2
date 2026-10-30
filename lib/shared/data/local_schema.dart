// Version 1 tables, retained for upgrade tests and existing installations.
const localSchema = <String>[
  '''CREATE TABLE users (
    id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE COLLATE NOCASE,
    name TEXT NOT NULL, password_hash TEXT NOT NULL, created_at TEXT NOT NULL)''',
  '''CREATE TABLE auth_sessions (
    token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TEXT NOT NULL, created_at TEXT NOT NULL)''',
  'CREATE INDEX auth_sessions_user ON auth_sessions(user_id)',
  '''CREATE TABLE posts (
    id TEXT PRIMARY KEY, author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL CHECK(length(body) BETWEEN 1 AND 3000), created_at TEXT NOT NULL)''',
  'CREATE INDEX posts_author_time ON posts(author_id, created_at DESC, id DESC)',
  'CREATE INDEX posts_time ON posts(created_at DESC, id DESC)',
  '''CREATE TABLE follows (
    follower_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followed_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL, PRIMARY KEY(follower_id, followed_id), CHECK(follower_id <> followed_id))''',
  '''CREATE TABLE friendships (
    user_low_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_high_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    requested_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK(status IN ('pending', 'accepted')), created_at TEXT NOT NULL,
    PRIMARY KEY(user_low_id, user_high_id), CHECK(user_low_id < user_high_id),
    CHECK(requested_by = user_low_id OR requested_by = user_high_id))''',
  'CREATE INDEX friendships_high ON friendships(user_high_id, status)',
  '''CREATE TABLE post_reactions (
    post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK(kind IN ('like', 'love', 'celebrate', 'insightful')),
    PRIMARY KEY(post_id, user_id))''',
  '''CREATE TABLE conversations (
    id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('direct', 'group')),
    title TEXT, direct_key TEXT UNIQUE, created_by TEXT NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL,
    CHECK((kind = 'direct' AND direct_key IS NOT NULL) OR (kind = 'group' AND title IS NOT NULL)))''',
  '''CREATE TABLE conversation_members (
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_read_sequence INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(conversation_id, user_id))''',
  'CREATE INDEX conversation_members_user ON conversation_members(user_id, conversation_id)',
  '''CREATE TABLE messages (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id TEXT NOT NULL REFERENCES users(id), client_id TEXT NOT NULL,
    body TEXT NOT NULL CHECK(length(body) BETWEEN 1 AND 4000), created_at TEXT NOT NULL,
    UNIQUE(conversation_id, sender_id, client_id))''',
  'CREATE INDEX messages_conversation_sequence ON messages(conversation_id, sequence DESC)',
];

// Version 2 adds optional, explicitly saved per-account map pins.
const peopleLocationSchema = '''CREATE TABLE user_locations (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  latitude REAL NOT NULL CHECK(latitude BETWEEN -90 AND 90),
  longitude REAL NOT NULL CHECK(longitude BETWEEN -180 AND 180),
  visible INTEGER NOT NULL DEFAULT 1 CHECK(visible IN (0, 1)),
  updated_at TEXT NOT NULL)''';
