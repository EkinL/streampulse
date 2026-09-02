DROP INDEX IF EXISTS idx_users_provider_subject;
ALTER TABLE users DROP COLUMN provider_subject;
ALTER TABLE users DROP COLUMN auth_provider;
ALTER TABLE users ALTER COLUMN password_hash DROP DEFAULT;
