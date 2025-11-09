CREATE TABLE IF NOT EXISTS pokemon (
    card_id text PRIMARY KEY,
    name text,
    image_url text,
    variants text -- stringified json
);

CREATE TABLE IF NOT EXISTS owned (
    card_id text PRIMARY KEY,
    variants text -- stringified json
);
