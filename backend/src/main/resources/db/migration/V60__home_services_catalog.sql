-- Service definitions classify the existing Booking Engine's offers.
-- Prices, durations and active capacity belong to bookable partner offers.
CREATE TABLE marketplace.home_service_categories (
    code varchar(32) COLLATE "C" PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,31}$'),
    name_ru varchar(120) NOT NULL CHECK (length(btrim(name_ru)) > 0),
    name_kk varchar(120) NOT NULL CHECK (length(btrim(name_kk)) > 0),
    name_en varchar(120) NOT NULL CHECK (length(btrim(name_en)) > 0),
    icon varchar(40) NOT NULL CHECK (icon ~ '^[a-z][a-z0-9_]{1,39}$'),
    active boolean NOT NULL DEFAULT false,
    sort_order integer NOT NULL CHECK (sort_order >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE marketplace.home_service_definitions (
    code varchar(40) COLLATE "C" PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{1,39}$'),
    category_code varchar(32) COLLATE "C" NOT NULL REFERENCES marketplace.home_service_categories(code),
    name_ru varchar(120) NOT NULL CHECK (length(btrim(name_ru)) > 0),
    name_kk varchar(120) NOT NULL CHECK (length(btrim(name_kk)) > 0),
    name_en varchar(120) NOT NULL CHECK (length(btrim(name_en)) > 0),
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX home_service_definitions_category_idx
    ON marketplace.home_service_definitions (category_code, code);

INSERT INTO marketplace.home_service_categories (code, name_ru, name_kk, name_en, icon, active, sort_order) VALUES
    ('CLEANING', 'Уборка', 'Үй жинау', 'Cleaning', 'cleaning_services', true, 10),
    ('PLUMBING', 'Сантехника', 'Сантехника', 'Plumbing', 'plumbing', true, 20),
    ('ELECTRICAL', 'Электрика', 'Электр жұмыстары', 'Electrical', 'electrical_services', true, 30),
    ('REPAIR_INSTALLATION', 'Ремонт и установка', 'Жөндеу және орнату', 'Repair and installation', 'handyman', true, 40),
    ('FURNITURE', 'Сборка мебели', 'Жиһаз құрастыру', 'Furniture assembly', 'chair', true, 50),
    ('APPLIANCES', 'Ремонт техники', 'Техниканы жөндеу', 'Appliance repair', 'home_repair_service', true, 60),
    ('HANDYMAN', 'Мастер на час', 'Бір сағатқа шебер', 'Handyman', 'construction', true, 70),
    ('FINISHING', 'Покраска и отделка', 'Сырлау және әрлеу', 'Painting and finishing', 'format_paint', true, 80);

INSERT INTO marketplace.home_service_definitions (code, category_code, name_ru, name_kk, name_en) VALUES
    ('DEEP_CLEAN', 'CLEANING', 'Генеральная уборка', 'Күрделі тазалау', 'Deep cleaning'),
    ('REGULAR_CLEAN', 'CLEANING', 'Поддерживающая уборка', 'Күнделікті жинау', 'Regular cleaning'),
    ('POST_RENOVATION_CLEAN', 'CLEANING', 'Уборка после ремонта', 'Жөндеуден кейін тазалау', 'Post-renovation cleaning'),
    ('WINDOW_CLEAN', 'CLEANING', 'Мытьё окон', 'Терезе жуу', 'Window cleaning'),
    ('KITCHEN_CLEAN', 'CLEANING', 'Уборка кухни', 'Асүйді тазалау', 'Kitchen cleaning'),
    ('BATHROOM_CLEAN', 'CLEANING', 'Уборка санузла', 'Жуынатын бөлмені тазалау', 'Bathroom cleaning'),
    ('UPHOLSTERY_CLEAN', 'CLEANING', 'Химчистка мебели', 'Жиһазды химиялық тазалау', 'Upholstery cleaning'),
    ('OFFICE_CLEAN', 'CLEANING', 'Уборка офиса', 'Кеңсе тазалау', 'Office cleaning'),
    ('TAP_REPAIR', 'PLUMBING', 'Ремонт смесителя', 'Араластырғыш кранды жөндеу', 'Tap repair'),
    ('TAP_INSTALL', 'PLUMBING', 'Установка смесителя', 'Араластырғыш кран орнату', 'Tap installation'),
    ('LEAK_REPAIR', 'PLUMBING', 'Устранение протечки', 'Су ағуын тоқтату', 'Leak repair'),
    ('DRAIN_UNBLOCK', 'PLUMBING', 'Устранение засора', 'Бітелген құбырды ашу', 'Drain unblocking'),
    ('SINK_INSTALL', 'PLUMBING', 'Установка раковины', 'Қолжуғыш орнату', 'Sink installation'),
    ('TOILET_INSTALL', 'PLUMBING', 'Установка унитаза', 'Дәретхана жабдығын орнату', 'Toilet installation'),
    ('PIPE_REPAIR', 'PLUMBING', 'Ремонт труб', 'Құбырларды жөндеу', 'Pipe repair'),
    ('WASHER_CONNECTION', 'PLUMBING', 'Подключение стиральной машины', 'Кір жуғыш машинаны қосу', 'Washing machine hookup'),
    ('SOCKET_REPLACE', 'ELECTRICAL', 'Замена розетки', 'Розетканы ауыстыру', 'Socket replacement'),
    ('SWITCH_REPLACE', 'ELECTRICAL', 'Замена выключателя', 'Ажыратқышты ауыстыру', 'Light switch replacement'),
    ('LIGHT_FIXTURE_INSTALL', 'ELECTRICAL', 'Установка светильника', 'Шам орнату', 'Light fixture installation'),
    ('CHANDELIER_INSTALL', 'ELECTRICAL', 'Монтаж люстры', 'Аспалы шам орнату', 'Chandelier installation'),
    ('WIRING_DIAGNOSTICS', 'ELECTRICAL', 'Диагностика электропроводки', 'Электр сымдарын тексеру', 'Wiring diagnostics'),
    ('WIRING_REPAIR', 'ELECTRICAL', 'Ремонт электропроводки', 'Электр сымдарын жөндеу', 'Wiring repair'),
    ('CIRCUIT_BREAKER_INSTALL', 'ELECTRICAL', 'Установка автоматов', 'Автоматты ажыратқыш орнату', 'Circuit breaker installation'),
    ('APPLIANCE_CONNECTION', 'ELECTRICAL', 'Подключение бытовой техники', 'Тұрмыстық техниканы қосу', 'Appliance hookup'),
    ('HOUSEHOLD_REPAIR', 'REPAIR_INSTALLATION', 'Мелкий бытовой ремонт', 'Ұсақ тұрмыстық жөндеу', 'Minor household repairs'),
    ('SHELF_INSTALL', 'REPAIR_INSTALLATION', 'Установка полок', 'Сөре орнату', 'Shelf installation'),
    ('CURTAIN_ROD_INSTALL', 'REPAIR_INSTALLATION', 'Установка карнизов', 'Перде карнизін орнату', 'Curtain rod installation'),
    ('TV_MOUNT', 'REPAIR_INSTALLATION', 'Монтаж телевизора', 'Теледидарды бекіту', 'TV mounting'),
    ('DOOR_HARDWARE_INSTALL', 'REPAIR_INSTALLATION', 'Установка дверной фурнитуры', 'Есік фурнитурасын орнату', 'Door hardware installation'),
    ('LOCK_REPAIR', 'REPAIR_INSTALLATION', 'Ремонт замков', 'Құлыптарды жөндеу', 'Lock repair'),
    ('HOME_EQUIPMENT_INSTALL', 'REPAIR_INSTALLATION', 'Монтаж бытового оборудования', 'Тұрмыстық жабдықты орнату', 'Household equipment installation'),
    ('WARDROBE_ASSEMBLY', 'FURNITURE', 'Сборка шкафа', 'Шкаф құрастыру', 'Wardrobe assembly'),
    ('BED_ASSEMBLY', 'FURNITURE', 'Сборка кровати', 'Кереует құрастыру', 'Bed assembly'),
    ('TABLE_ASSEMBLY', 'FURNITURE', 'Сборка стола', 'Үстел құрастыру', 'Table assembly'),
    ('KITCHEN_ASSEMBLY', 'FURNITURE', 'Сборка кухни', 'Асүй жиһазын құрастыру', 'Kitchen assembly'),
    ('DRESSER_ASSEMBLY', 'FURNITURE', 'Сборка комода', 'Суырмалы шкаф құрастыру', 'Dresser assembly'),
    ('FURNITURE_DISASSEMBLY', 'FURNITURE', 'Разборка мебели', 'Жиһазды бөлшектеу', 'Furniture disassembly'),
    ('FURNITURE_REARRANGE', 'FURNITURE', 'Перестановка мебели', 'Жиһаздың орнын ауыстыру', 'Furniture rearrangement'),
    ('WASHER_REPAIR', 'APPLIANCES', 'Стиральные машины', 'Кір жуғыш машиналар', 'Washing machine repair'),
    ('FRIDGE_REPAIR', 'APPLIANCES', 'Холодильники', 'Тоңазытқыштар', 'Refrigerator repair'),
    ('DISHWASHER_REPAIR', 'APPLIANCES', 'Посудомоечные машины', 'Ыдыс жуғыш машиналар', 'Dishwasher repair'),
    ('OVEN_REPAIR', 'APPLIANCES', 'Духовые шкафы', 'Тұмшапештер', 'Oven repair'),
    ('AC_REPAIR', 'APPLIANCES', 'Кондиционеры', 'Кондиционерлер', 'Air conditioner repair'),
    ('SMALL_APPLIANCE_REPAIR', 'APPLIANCES', 'Мелкая бытовая техника', 'Шағын тұрмыстық техника', 'Small appliance repair'),
    ('HANDYMAN_REPAIR', 'HANDYMAN', 'Мелкие ремонтные работы', 'Ұсақ жөндеу жұмыстары', 'Small repairs'),
    ('ITEM_MOUNT', 'HANDYMAN', 'Крепление предметов', 'Заттарды бекіту', 'Mounting household items'),
    ('ACCESSORY_INSTALL', 'HANDYMAN', 'Установка аксессуаров', 'Аксессуарларды орнату', 'Accessory installation'),
    ('DOOR_ADJUST', 'HANDYMAN', 'Регулировка дверей', 'Есіктерді реттеу', 'Door adjustment'),
    ('HANDYMAN_INSTALL', 'HANDYMAN', 'Бытовые монтажные работы', 'Тұрмыстық құрастыру жұмыстары', 'General household installation'),
    ('WALL_PAINT', 'FINISHING', 'Покраска стен', 'Қабырға сырлау', 'Wall painting'),
    ('WALLPAPER', 'FINISHING', 'Поклейка обоев', 'Тұсқағаз жапсыру', 'Wallpapering'),
    ('WALL_FILLING', 'FINISHING', 'Шпаклёвка', 'Қабырғаны тегістеу', 'Wall filling'),
    ('LAMINATE_INSTALL', 'FINISHING', 'Укладка ламината', 'Ламинат төсеу', 'Laminate flooring installation'),
    ('SKIRTING_INSTALL', 'FINISHING', 'Установка плинтусов', 'Еден ернеулігін орнату', 'Skirting board installation'),
    ('MINOR_FINISHING', 'FINISHING', 'Мелкие отделочные работы', 'Ұсақ әрлеу жұмыстары', 'Minor finishing work');
