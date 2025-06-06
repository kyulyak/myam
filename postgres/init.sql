-- Создаем схему для артистов и контента
CREATE SCHEMA IF NOT EXISTS artist_content;

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
    artist_id INTEGER NOT NULL REFERENCES artist_content.artists(artist_id),
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

-- Создаем схему для продаж и финансов
CREATE SCHEMA IF NOT EXISTS sales_finance;

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

-- Создаем схему для пользователей и аналитики
CREATE SCHEMA IF NOT EXISTS users_analytics;

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
    country VARCHAR(50) NOT NULL,
    PRIMARY KEY (stream_id),
    FOREIGN KEY (track_id, album_id) REFERENCES artist_content.tracks(track_id, album_id)
);

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
    -- Вставляем только негенерируемые столбцы
    IF (NEW.sale_date >= '2023-01-01' AND NEW.sale_date < '2024-01-01') THEN
        INSERT INTO sales_finance.sales_2023 (
            sale_id, track_id, album_id, sale_date, 
            platform_id, quantity, unit_price
        ) VALUES (
            NEW.sale_id, NEW.track_id, NEW.album_id, NEW.sale_date,
            NEW.platform_id, NEW.quantity, NEW.unit_price
        );
    ELSIF (NEW.sale_date >= '2024-01-01' AND NEW.sale_date < '2025-01-01') THEN
        INSERT INTO sales_finance.sales_2024 (
            sale_id, track_id, album_id, sale_date, 
            platform_id, quantity, unit_price
        ) VALUES (
            NEW.sale_id, NEW.track_id, NEW.album_id, NEW.sale_date,
            NEW.platform_id, NEW.quantity, NEW.unit_price
        );
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

-- Создаем индексы для улучшения производительности

-- Индексы для artist_content
CREATE INDEX idx_artists_name ON artist_content.artists(name);
CREATE INDEX idx_albums_artist ON artist_content.albums(artist_id);
CREATE INDEX idx_tracks_album ON artist_content.tracks(album_id);
CREATE INDEX idx_tracks_artist ON artist_content.tracks(artist_id);
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
CREATE INDEX idx_streaming_data_country ON users_analytics.streaming_data(country);

-- Заполняем таблицы данными
BEGIN;

-- Артисты
INSERT INTO artist_content.artists (name, genre, country, contract_start_date, contract_end_date) VALUES
('The Weeknd', 'R&B', 'Canada', '2012-01-01', '2025-12-31'),
('Taylor Swift', 'Pop', 'USA', '2010-06-01', '2026-06-01'),
('BTS', 'K-Pop', 'South Korea', '2015-07-01', '2027-07-01'),
('Billie Eilish', 'Alternative', 'USA', '2018-09-01', '2025-09-01'),
('Drake', 'Hip-Hop', 'Canada', '2011-02-01', '2024-02-01'),
('Adele', 'Soul', 'UK', '2009-03-01', '2025-03-01'),
('Ed Sheeran', 'Pop', 'UK', '2011-09-01', '2026-09-01'),
('Dua Lipa', 'Pop', 'UK', '2016-05-01', '2025-05-01'),
('Coldplay', 'Rock', 'UK', '2000-01-01', '2030-01-01'),
('Imagine Dragons', 'Rock', 'USA', '2012-07-01', '2025-07-01');

-- Альбомы
INSERT INTO artist_content.albums (artist_id, title, release_date, genre, total_tracks) VALUES
(1, 'After Hours', '2020-03-20', 'R&B', 14),
(1, 'Dawn FM', '2022-01-07', 'R&B', 16),
(2, 'Folklore', '2020-07-24', 'Indie Folk', 16),
(2, 'Midnights', '2022-10-21', 'Pop', 13),
(3, 'Map of the Soul: 7', '2020-02-21', 'K-Pop', 20),
(3, 'BE', '2020-11-20', 'K-Pop', 8),
(4, 'Happier Than Ever', '2021-07-30', 'Alternative', 16),
(5, 'Certified Lover Boy', '2021-09-03', 'Hip-Hop', 21),
(6, '30', '2021-11-19', 'Soul', 12),
(7, '=', '2021-10-29', 'Pop', 14);

-- Треки (с указанием artist_id)
INSERT INTO artist_content.tracks (album_id, artist_id, title, duration, is_single) VALUES
(1, 1, 'Blinding Lights', '00:03:20', TRUE),
(1, 1, 'Save Your Tears', '00:03:35', TRUE),
(1, 1, 'In Your Eyes', '00:03:58', FALSE),
(2, 1, 'Take My Breath', '00:05:39', TRUE),
(2, 1, 'Sacrifice', '00:03:08', FALSE),
(3, 2, 'cardigan', '00:03:59', TRUE),
(3, 2, 'exile', '00:04:45', FALSE),
(4, 2, 'Anti-Hero', '00:03:20', TRUE),
(4, 2, 'Lavender Haze', '00:03:22', FALSE),
(5, 3, 'ON', '00:04:06', TRUE),
(5, 3, 'Black Swan', '00:03:18', FALSE),
(6, 3, 'Life Goes On', '00:03:27', TRUE),
(7, 4, 'Happier Than Ever', '00:04:58', TRUE),
(7, 4, 'Therefore I Am', '00:02:54', FALSE),
(8, 5, 'Way 2 Sexy', '00:04:17', TRUE),
(9, 6, 'Easy On Me', '00:03:44', TRUE),
(10, 7, 'Bad Habits', '00:03:51', TRUE);

-- Ставки роялти
INSERT INTO artist_content.royalty_rates (artist_id, rate_percentage, effective_date) VALUES
(1, 15.00, '2020-01-01'),
(2, 18.00, '2019-01-01'),
(3, 12.00, '2020-01-01'),
(4, 16.00, '2021-01-01'),
(5, 20.00, '2018-01-01'),
(6, 22.00, '2021-01-01'),
(7, 17.00, '2020-01-01'),
(8, 15.00, '2021-01-01'),
(9, 10.00, '2015-01-01'),
(10, 12.00, '2020-01-01');

-- Платформы распространения
INSERT INTO sales_finance.platforms (platform_name, revenue_share_percentage) VALUES
('Spotify', 30.00),
('Apple Music', 25.00),
('YouTube Music', 35.00),
('Amazon Music', 28.00),
('Deezer', 30.00),
('Tidal', 20.00);

-- Продажи
INSERT INTO sales_finance.sales (track_id, album_id, sale_date, platform_id, quantity, unit_price) VALUES
(1, 1, '2023-01-15 10:30:00', 1, 1000, 0.99),
(1, 1, '2023-02-20 14:45:00', 2, 500, 1.29),
(2, 1, '2023-03-10 09:15:00', 1, 800, 0.99),
(3, 1, '2023-04-05 16:20:00', 3, 300, 0.79),
(4, 2, '2023-05-12 11:10:00', 1, 1200, 0.99),
(5, 2, '2023-06-18 13:25:00', 4, 400, 1.09),
(6, 3, '2024-01-10 10:00:00', 1, 1500, 0.99),
(7, 3, '2024-02-15 15:30:00', 2, 600, 1.29),
(8, 4, '2024-03-20 09:45:00', 1, 2000, 0.99),
(9, 4, '2024-04-25 14:15:00', 3, 700, 0.79),
(10, 5, '2024-05-30 12:00:00', 1, 1800, 0.99);

-- Выплаты артистам
INSERT INTO sales_finance.payments (artist_id, amount, payment_date, period_start_date, period_end_date) VALUES
(1, 250000.00, '2023-03-01', '2023-01-01', '2023-02-28'),
(2, 1800000.00, '2023-03-01', '2023-01-01', '2023-02-28'),
(3, 1200000.00, '2023-03-01', '2023-01-01', '2023-02-28'),
(1, 300000.00, '2023-06-01', '2023-03-01', '2023-05-31'),
(4, 950000.00, '2023-06-01', '2023-03-01', '2023-05-31'),
(5, 1500000.00, '2023-06-01', '2023-03-01', '2023-05-31');

-- Пользователи
INSERT INTO users_analytics.users (email, registration_date, country, age_group) VALUES
('user1@example.com', '2022-01-15', 'US', '18-25'),
('user2@example.com', '2022-02-20', 'UK', '26-35'),
('user3@example.com', '2022-03-10', 'CA', '18-25'),
('user4@example.com', '2022-04-05', 'DE', '36-45'),
('user5@example.com', '2022-05-12', 'FR', '26-35'),
('user6@example.com', '2022-06-18', 'BR', '18-25'),
('user7@example.com', '2023-01-10', 'MX', '26-35'),
('user8@example.com', '2023-02-15', 'ES', '18-25'),
('user9@example.com', '2023-03-20', 'IT', '36-45'),
('user10@example.com', '2023-04-25', 'NL', '26-35');

-- Данные стриминга (с указанием страны)
INSERT INTO users_analytics.streaming_data (track_id, album_id, user_id, platform_id, stream_date, duration_played, country) VALUES
(1, 1, 1, 1, '2023-01-16 08:30:00', '00:03:20', 'US'),
(1, 1, 2, 1, '2023-01-17 12:45:00', '00:03:20', 'UK'),
(2, 1, 3, 2, '2023-02-21 09:15:00', '00:03:35', 'CA'),
(3, 1, 4, 3, '2023-03-11 18:20:00', '00:03:58', 'DE'),
(4, 2, 5, 1, '2023-04-06 14:10:00', '00:05:39', 'FR'),
(5, 2, 6, 4, '2023-05-13 16:25:00', '00:03:08', 'BR'),
(6, 3, 7, 1, '2024-01-11 10:00:00', '00:03:59', 'MX'),
(7, 3, 8, 2, '2024-02-16 15:30:00', '00:04:45', 'ES'),
(8, 4, 9, 1, '2024-03-21 09:45:00', '00:03:20', 'IT'),
(9, 4, 10, 3, '2024-04-26 14:15:00', '00:03:22', 'NL'),
(10, 5, 1, 1, '2024-05-31 12:00:00', '00:04:06', 'US');

COMMIT;

-- Проверка данных
SELECT 
    (SELECT COUNT(*) FROM artist_content.artists) AS artists_count,
    (SELECT COUNT(*) FROM artist_content.albums) AS albums_count,
    (SELECT COUNT(*) FROM artist_content.tracks) AS tracks_count,
    (SELECT COUNT(*) FROM sales_finance.sales) AS sales_count,
    (SELECT COUNT(*) FROM users_analytics.users) AS users_count,
    (SELECT COUNT(*) FROM users_analytics.streaming_data) AS streams_count;