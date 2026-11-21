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
