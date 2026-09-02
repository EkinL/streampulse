-- Connexion sociale (Google / Apple) : chaque compte peut etre relie a une
-- identite externe identifiee par (auth_provider, provider_subject).
-- Un compte social n'a pas de mot de passe : password_hash devient
-- defaut vide ('' ne matche jamais un bcrypt, le login classique echoue).
ALTER TABLE users ALTER COLUMN password_hash SET DEFAULT '';
ALTER TABLE users ADD COLUMN auth_provider VARCHAR(20) NOT NULL DEFAULT 'local';
ALTER TABLE users ADD COLUMN provider_subject VARCHAR(255);

-- Une identite sociale ne peut etre reliee qu'a un seul compte. Index
-- partiel : les comptes locaux (provider_subject NULL) ne sont pas concernes.
CREATE UNIQUE INDEX idx_users_provider_subject
    ON users (auth_provider, provider_subject)
    WHERE provider_subject IS NOT NULL;
