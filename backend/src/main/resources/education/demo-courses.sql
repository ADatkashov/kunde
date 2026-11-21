-- Dedicated synthetic owner with no credentials or external bindings.
INSERT INTO identity.users (id) VALUES ('a00ed000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO marketplace.partners (id, display_name, verification_status, created_by_user_id)
VALUES ('a00ed000-0000-4000-8000-000000000002', 'Учебная студия KUNDE (синтетика)', 'APPROVED',
        'a00ed000-0000-4000-8000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO marketplace.education_courses (id, partner_id, category, title, description, city, language, status, synthetic)
SELECT id::uuid, 'a00ed000-0000-4000-8000-000000000002', category, title, description, 'Алматы', 'ru', 'PUBLISHED', true
FROM (VALUES
    ('a00ed000-0000-4000-8000-000000000101', 'IT', 'Python для начинающих', 'Переменные, условия и циклы на коротких примерах.'),
    ('a00ed000-0000-4000-8000-000000000102', 'LANGUAGES', 'Английский язык B1', 'Практика разговорного английского.'),
    ('a00ed000-0000-4000-8000-000000000103', 'DESIGN', 'Введение в UI/UX', 'Прототипирование и проверка пользовательских сценариев.')
) AS demo(id, category, title, description)
ON CONFLICT (id) DO NOTHING;

INSERT INTO marketplace.education_course_formats (course_id, format, price_minor, duration_minutes)
VALUES ('a00ed000-0000-4000-8000-000000000101', 'ONLINE_RECORDED', 3500000, 90),
       ('a00ed000-0000-4000-8000-000000000102', 'ONLINE_LIVE', 4900000, 60),
       ('a00ed000-0000-4000-8000-000000000103', 'OFFLINE_GROUP', 5600000, 120)
ON CONFLICT (course_id, format) DO NOTHING;

INSERT INTO marketplace.education_course_modules (course_id, position, title)
VALUES ('a00ed000-0000-4000-8000-000000000101', 1, 'Основы Python'),
       ('a00ed000-0000-4000-8000-000000000102', 1, 'Разговорная практика'),
       ('a00ed000-0000-4000-8000-000000000103', 1, 'Пользовательские сценарии')
ON CONFLICT (course_id, position) DO NOTHING;

INSERT INTO marketplace.education_course_lessons (course_id, module_position, position, title, duration_minutes)
VALUES ('a00ed000-0000-4000-8000-000000000101', 1, 1, 'Переменные', 30),
       ('a00ed000-0000-4000-8000-000000000101', 1, 2, 'Условия и циклы', 60),
       ('a00ed000-0000-4000-8000-000000000102', 1, 1, 'Разговор о работе и учёбе', 60),
       ('a00ed000-0000-4000-8000-000000000103', 1, 1, 'Прототип первого экрана', 120)
ON CONFLICT (course_id, module_position, position) DO NOTHING;

INSERT INTO marketplace.education_cohorts(id, course_id, format, starts_at, ends_at, capacity, open)
VALUES ('a00ed000-0000-4000-8000-000000000201', 'a00ed000-0000-4000-8000-000000000101',
        'ONLINE_RECORDED', NULL, NULL, 500, true),
       ('a00ed000-0000-4000-8000-000000000202', 'a00ed000-0000-4000-8000-000000000102',
        'ONLINE_LIVE', date_trunc('day', now(), 'Asia/Almaty') + interval '7 days 14 hours',
        date_trunc('day', now(), 'Asia/Almaty') + interval '7 days 15 hours', 12, true),
       ('a00ed000-0000-4000-8000-000000000203', 'a00ed000-0000-4000-8000-000000000103',
        'OFFLINE_GROUP', date_trunc('day', now(), 'Asia/Almaty') + interval '8 days 14 hours',
        date_trunc('day', now(), 'Asia/Almaty') + interval '8 days 16 hours', 8, true)
ON CONFLICT (id) DO NOTHING;

UPDATE marketplace.education_course_lessons
SET recorded_text = CASE position
    WHEN 1 THEN 'Переменная хранит значение. Запишите name = "KUNDE", затем print(name), чтобы вывести его.'
    WHEN 2 THEN 'Условие if выполняет код, когда выражение истинно. Цикл for перебирает значения. Попробуйте for n in range(3) и выведите n.'
END
WHERE course_id = 'a00ed000-0000-4000-8000-000000000101' AND module_position=1 AND position IN (1,2)
  AND recorded_text IS NULL;
