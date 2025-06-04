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

