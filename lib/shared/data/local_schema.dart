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

// Version 3 adds optional profile details and an on-device profile photo.
const userProfileSchema = '''CREATE TABLE user_profiles (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  bio TEXT NOT NULL DEFAULT '' CHECK(length(bio) <= 160),
  photo BLOB CHECK(photo IS NULL OR length(photo) <= 2000000),
  updated_at TEXT NOT NULL)''';

// Version 4 keeps recorded clips separate from message list queries.
const messageAudioSchema = '''CREATE TABLE message_audio (
  message_sequence INTEGER PRIMARY KEY REFERENCES messages(sequence) ON DELETE CASCADE,
  data BLOB NOT NULL CHECK(length(data) BETWEEN 1 AND 2000000),
  duration_ms INTEGER NOT NULL CHECK(duration_ms BETWEEN 1 AND 120000))''';

// Version 5 adds post comments. They disappear with their post or author.
const postCommentSchema = [
  '''CREATE TABLE post_comments (
  id TEXT PRIMARY KEY,
  post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK(length(body) BETWEEN 1 AND 1000),
  created_at TEXT NOT NULL)''',
  'CREATE INDEX post_comments_post_time ON post_comments(post_id, created_at, id)',
];

// Version 6 adds one pending password-reset code per account (stored hashed).
const passwordResetSchema = '''CREATE TABLE password_resets (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL, expires_at TEXT NOT NULL)''';

// Version 7 indexes hashtags and @mentions so posts can be searched by them.
const postLinkSchema = [
  '''CREATE TABLE post_tags (
  post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  tag TEXT NOT NULL CHECK(length(tag) BETWEEN 1 AND 40),
  PRIMARY KEY(post_id, tag))''',
  'CREATE INDEX post_tags_tag ON post_tags(tag, post_id)',
  '''CREATE TABLE post_mentions (
  post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY(post_id, user_id))''',
  'CREATE INDEX post_mentions_user ON post_mentions(user_id, post_id)',
];

// Version 7 full-text index of post bodies (SQLite FTS4). Triggers keep it in
// step with `posts`, including deletes cascaded from a removed account.
// Created separately because a device SQLite might lack the FTS module; search
// then falls back to plain substring matching.
const postSearchTriggers = [
  '''CREATE TRIGGER posts_fts_insert AFTER INSERT ON posts BEGIN
  INSERT INTO posts_fts(post_id, body) VALUES (new.id, new.body); END''',
  '''CREATE TRIGGER posts_fts_delete AFTER DELETE ON posts BEGIN
  DELETE FROM posts_fts WHERE post_id = old.id; END''',
  '''CREATE TRIGGER posts_fts_update AFTER UPDATE OF body ON posts BEGIN
  UPDATE posts_fts SET body = new.body WHERE post_id = new.id; END''',
];
// Tried in order: Android's system SQLite ships FTS4; some desktop builds
// (used by the tests) only ship FTS5. Both accept the same `word*` queries.
const postSearchTable = [
  'CREATE VIRTUAL TABLE posts_fts USING fts4(post_id, body, notindexed=post_id, tokenize=unicode61)',
  'CREATE VIRTUAL TABLE posts_fts USING fts4(post_id, body, notindexed=post_id)',
  'CREATE VIRTUAL TABLE posts_fts USING fts5(post_id UNINDEXED, body)',
];

// Version 8 stores one optional photo per post, outside `posts` so feed
// queries stay small; the bytes are loaded only when a card is shown.
const postImageSchema = '''CREATE TABLE post_images (
  post_id TEXT PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,
  data BLOB NOT NULL CHECK(length(data) BETWEEN 1 AND 2000000),
  width INTEGER NOT NULL CHECK(width BETWEEN 1 AND 4096),
  height INTEGER NOT NULL CHECK(height BETWEEN 1 AND 4096))''';

// Version 9 rebuilds `posts` (SQLite cannot change a CHECK in place):
// * `shared_post_id` marks a repost; no foreign key, so a repost survives the
//   original's deletion and shows "no longer available";
// * the body may be empty for a repost without comment or a photo-only post
//   (the repository still requires text, a photo or a shared post).
const postsV9Schema = [
  '''CREATE TABLE posts_v9 (
  id TEXT PRIMARY KEY,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK(length(body) <= 3000),
  created_at TEXT NOT NULL,
  shared_post_id TEXT)''',
  '''INSERT INTO posts_v9 (id, author_id, body, created_at)
  SELECT id, author_id, body, created_at FROM posts''',
  'DROP TABLE posts',
  'ALTER TABLE posts_v9 RENAME TO posts',
  'CREATE INDEX posts_author_time ON posts(author_id, created_at DESC, id DESC)',
  'CREATE INDEX posts_time ON posts(created_at DESC, id DESC)',
  'CREATE INDEX posts_shared ON posts(shared_post_id)',
];

// Version 9: a chat message can carry a post sent to a friend.
const messagePostSchema = '''CREATE TABLE message_posts (
  message_sequence INTEGER PRIMARY KEY REFERENCES messages(sequence) ON DELETE CASCADE,
  post_id TEXT NOT NULL)''';
