CREATE TABLE IF NOT EXISTS posts (
  id TEXT PRIMARY KEY,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK(length(body) BETWEEN 1 AND 3000),
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS posts_author_time ON posts(author_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS posts_time ON posts(created_at DESC, id DESC);

CREATE TABLE IF NOT EXISTS follows (
  follower_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  followed_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY(follower_id, followed_id),
  CHECK(follower_id <> followed_id)
);

CREATE TABLE IF NOT EXISTS friendships (
  user_low_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_high_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  requested_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK(status IN ('pending', 'accepted')),
  created_at TEXT NOT NULL,
  PRIMARY KEY(user_low_id, user_high_id),
  CHECK(user_low_id < user_high_id),
  CHECK(requested_by = user_low_id OR requested_by = user_high_id)
);
CREATE INDEX IF NOT EXISTS friendships_high ON friendships(user_high_id, status);

CREATE TABLE IF NOT EXISTS post_reactions (
  post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK(kind IN ('like', 'love', 'celebrate', 'insightful')),
  PRIMARY KEY(post_id, user_id)
);

INSERT INTO connectly_schema_migrations (version) VALUES (2)
ON CONFLICT(version) DO NOTHING;
