-- Создание базы данных
CREATE DATABASE music_label;
\c music_label

-- Домен 1: Артисты и контент
CREATE SCHEMA artist_content;

-- Таблица артистов
CREATE TABLE artist_content.artists (
    artist_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    genre VARCHAR(50),
    country VARCHAR(50),
    contract_start_date DATE NOT NULL,
    contract_end_date DATE
);

-- Таблица альбомов
CREATE TABLE artist_content.albums (
    album_id SERIAL PRIMARY KEY,
    artist_id INTEGER NOT NULL REFERENCES artist_content.artists(artist_id),
    title VARCHAR(100) NOT NULL,
    release_date DATE NOT NULL,
    genre VARCHAR(50),
    total_tracks INTEGER NOT NULL
);

-- Таблица треков (основная таблица перед шардированием)
CREATE TABLE artist_content.tracks (
    track_id SERIAL,
    album_id INTEGER NOT NULL REFERENCES artist_content.albums(album_id),
    title VARCHAR(100) NOT NULL,
    duration INTERVAL NOT NULL,
    is_single BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (track_id, album_id)
);

-- Таблица ставок роялти
CREATE TABLE artist_content.royalty_rates (
    rate_id SERIAL PRIMARY KEY,
    artist_id INTEGER NOT NULL REFERENCES artist_content.artists(artist_id),
    rate_percentage DECIMAL(5,2) NOT NULL,
    effective_date DATE NOT NULL
);

-- Домен 2: Продажи и финансы 
CREATE SCHEMA sales_finance;

-- Таблица платформ распространения
CREATE TABLE sales_finance.platforms (
    platform_id SERIAL PRIMARY KEY,
    platform_name VARCHAR(50) NOT NULL,
    revenue_share_percentage DECIMAL(5,2) NOT NULL
);

-- Таблица продаж (основная таблица перед шардированием)
CREATE TABLE sales_finance.sales (
    sale_id SERIAL,
    track_id INTEGER NOT NULL,
    album_id INTEGER NOT NULL,
    sale_date TIMESTAMP NOT NULL,
    platform_id INTEGER NOT NULL REFERENCES sales_finance.platforms(platform_id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_amount DECIMAL(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    PRIMARY KEY (sale_id, sale_date),
    FOREIGN KEY (track_id, album_id) REFERENCES artist_content.tracks(track_id, album_id)
);

-- Таблица выплат артистам
CREATE TABLE sales_finance.payments (
    payment_id SERIAL PRIMARY KEY,
    artist_id INTEGER NOT NULL REFERENCES artist_content.artists(artist_id),
    amount DECIMAL(12,2) NOT NULL,
    payment_date DATE NOT NULL,
    period_start_date DATE NOT NULL,
    period_end_date DATE NOT NULL
);

-- Домен 3: Пользователи и аналитика 
CREATE SCHEMA users_analytics;

-- Таблица пользователей
CREATE TABLE users_analytics.users (
    user_id SERIAL PRIMARY KEY,
    email VARCHAR(100) NOT NULL UNIQUE,
    registration_date DATE NOT NULL,
    country VARCHAR(50) NOT NULL,
    age_group VARCHAR(20)
);

-- Таблица данных стриминга (основная таблица перед шардированием)
CREATE TABLE users_analytics.streaming_data (
    stream_id SERIAL,
    track_id INTEGER NOT NULL,
    album_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL REFERENCES users_analytics.users(user_id),
    platform_id INTEGER NOT NULL REFERENCES sales_finance.platforms(platform_id),
    stream_date TIMESTAMP NOT NULL,
    duration_played INTERVAL NOT NULL,
    PRIMARY KEY (stream_id, country),
    FOREIGN KEY (track_id, album_id) REFERENCES artist_content.tracks(track_id, album_id)
);

-- Создание горизонтальных шардов

-- Шардирование таблицы tracks по artist_id
CREATE TABLE artist_content.tracks_artist_even (
    CHECK (artist_id % 2 = 0)
) INHERITS (artist_content.tracks);

CREATE TABLE artist_content.tracks_artist_odd (
    CHECK (artist_id % 2 = 1)
) INHERITS (artist_content.tracks);

-- Функция для маршрутизации вставок в tracks
CREATE OR REPLACE FUNCTION tracks_insert_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.artist_id % 2 = 0) THEN
        INSERT INTO artist_content.tracks_artist_even VALUES (NEW.*);
    ELSE
        INSERT INTO artist_content.tracks_artist_odd VALUES (NEW.*);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Триггер для вставки
CREATE TRIGGER insert_tracks_trigger
BEFORE INSERT ON artist_content.tracks
FOR EACH ROW EXECUTE FUNCTION tracks_insert_trigger();

-- Шардирование таблицы sales по дате
CREATE TABLE sales_finance.sales_2023 (
    CHECK (sale_date >= '2023-01-01' AND sale_date < '2024-01-01')
) INHERITS (sales_finance.sales);

CREATE TABLE sales_finance.sales_2024 (
    CHECK (sale_date >= '2024-01-01' AND sale_date < '2025-01-01')
) INHERITS (sales_finance.sales);

-- Функция для маршрутизации вставок в sales
CREATE OR REPLACE FUNCTION sales_insert_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.sale_date >= '2023-01-01' AND NEW.sale_date < '2024-01-01') THEN
        INSERT INTO sales_finance.sales_2023 VALUES (NEW.*);
    ELSIF (NEW.sale_date >= '2024-01-01' AND NEW.sale_date < '2025-01-01') THEN
        INSERT INTO sales_finance.sales_2024 VALUES (NEW.*);
    ELSE
        RAISE EXCEPTION 'Date out of range. Fix the sales_insert_trigger() function!';
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Триггер для вставки
CREATE TRIGGER insert_sales_trigger
BEFORE INSERT ON sales_finance.sales
FOR EACH ROW EXECUTE FUNCTION sales_insert_trigger();

-- Шардирование таблицы streaming_data по географии
CREATE TABLE users_analytics.streaming_europe (
    CHECK (country IN ('DE', 'FR', 'UK', 'IT', 'ES', 'NL', 'SE', 'PL', 'RU', 'UA'))
) INHERITS (users_analytics.streaming_data);

CREATE TABLE users_analytics.streaming_americas (
    CHECK (country IN ('US', 'CA', 'BR', 'MX', 'AR', 'CO', 'CL', 'PE'))
) INHERITS (users_analytics.streaming_data);

-- Функция для маршрутизации вставок в streaming_data
CREATE OR REPLACE FUNCTION streaming_data_insert_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.country IN ('DE', 'FR', 'UK', 'IT', 'ES', 'NL', 'SE', 'PL', 'RU', 'UA')) THEN
        INSERT INTO users_analytics.streaming_europe VALUES (NEW.*);
    ELSIF (NEW.country IN ('US', 'CA', 'BR', 'MX', 'AR', 'CO', 'CL', 'PE')) THEN
        INSERT INTO users_analytics.streaming_americas VALUES (NEW.*);
    ELSE
        INSERT INTO users_analytics.streaming_data VALUES (NEW.*);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Триггер для вставки
CREATE TRIGGER insert_streaming_data_trigger
BEFORE INSERT ON users_analytics.streaming_data
FOR EACH ROW EXECUTE FUNCTION streaming_data_insert_trigger();

-- Создание индексов для улучшения производительности

-- Индексы для artist_content
CREATE INDEX idx_artists_name ON artist_content.artists(name);
CREATE INDEX idx_albums_artist ON artist_content.albums(artist_id);
CREATE INDEX idx_tracks_album ON artist_content.tracks(album_id);
CREATE INDEX idx_royalty_rates_artist ON artist_content.royalty_rates(artist_id);

-- Индексы для sales_finance
CREATE INDEX idx_sales_track ON sales_finance.sales(track_id, album_id);
CREATE INDEX idx_sales_date ON sales_finance.sales(sale_date);
CREATE INDEX idx_sales_platform ON sales_finance.sales(platform_id);
CREATE INDEX idx_payments_artist ON sales_finance.payments(artist_id);

-- Индексы для users_analytics
CREATE INDEX idx_users_country ON users_analytics.users(country);
CREATE INDEX idx_streaming_data_user ON users_analytics.streaming_data(user_id);
CREATE INDEX idx_streaming_data_track ON users_analytics.streaming_data(track_id, album_id);
CREATE INDEX idx_streaming_data_date ON users_analytics.streaming_data(stream_date);